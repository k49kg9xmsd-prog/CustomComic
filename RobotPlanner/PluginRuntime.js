/* Robot Planner iOS JavaScript Mod Runtime v1.0 */
(function(){
  if(window.__robotPlannerPluginRuntimeReady)return;
  window.__robotPlannerPluginRuntimeReady=true;

  const owners=new Map();
  const eventHandlers=new Map();
  const services=new Map();

  function callBridge(method,...args){
    return new Promise(resolve=>{
      try{
        const fn=window.bridge && window.bridge[method];
        if(typeof fn!=="function"){ resolve(null); return; }
        fn(...args,resolve);
      }catch(e){
        console.error("Plugin bridge",method,e);
        resolve(null);
      }
    });
  }

  function report(pid,error){
    const text=String(error && (error.stack||error.message) || error || "Unknown plugin error");
    console.error(`[RobotPlanner:${pid}]`,text);
    try{ window.bridge?.pluginReportError?.(pid,text,()=>{}); }catch(_){}
  }

  function on(pid,event,callback){
    event=String(event);
    if(typeof callback!=="function")throw new TypeError("callback must be a function");
    const row={pid,callback};
    if(!eventHandlers.has(event))eventHandlers.set(event,[]);
    eventHandlers.get(event).push(row);
    return callback;
  }

  function emit(event,...args){
    const rows=[...(eventHandlers.get(String(event))||[])];
    const out=[];
    for(const row of rows){
      try{ out.push(row.callback(...args)); }
      catch(e){ report(row.pid,e); }
    }
    return out;
  }

  function offOwner(pid){
    for(const [event,rows] of eventHandlers){
      eventHandlers.set(event,rows.filter(r=>r.pid!==pid));
    }
  }

  function safeRel(path){
    path=String(path||"").replaceAll("\\","/");
    if(!path || path.startsWith("/") || path.split("/").some(x=>x==="..")){
      throw new Error("unsafe plugin relative path: "+path);
    }
    return path;
  }

  function createContext(pid,manifest){
    const ctx={
      pluginId:pid,
      id:pid,
      manifest,
      platform:"iOS",
      bridge:window.bridge,
      fullAccess:window,
      window,
      document,
      events:{
        on:(event,callback)=>on(pid,event,callback),
        emit:(event,...args)=>emit(event,...args),
        offOwner:()=>offOwner(pid)
      },
      services,
      log:(...parts)=>console.log(`[RobotPlanner:${pid}]`,...parts),
      on:(event,callback)=>on(pid,event,callback),
      emit:(event,...args)=>emit(event,...args),

      registerService(name,value,replace=false){
        name=String(name);
        if(services.has(name) && !replace)throw new Error("service already exists: "+name);
        services.set(name,value);
        return value;
      },
      replaceService(name,value){
        name=String(name);
        const old=services.get(name);
        services.set(name,value);
        return old;
      },
      getService(name,defaultValue=null){
        name=String(name);
        return services.has(name)?services.get(name):defaultValue;
      },

      injectCSS(css){
        const style=document.createElement("style");
        style.dataset.robotPlannerPlugin=pid;
        style.textContent=String(css??"");
        document.head.appendChild(style);
        return true;
      },

      injectJS(js){
        const source=String(js??"");
        const fn=new Function("ctx","window","document","bridge",source+`\n//# sourceURL=robotplanner-plugin://${encodeURIComponent(pid)}/injected.js`);
        return fn(ctx,window,document,window.bridge);
      },

      injectHTML(fragment,before="</body>"){
        const tpl=document.createElement("template");
        tpl.innerHTML=String(fragment??"");
        const nodes=[...tpl.content.childNodes];
        for(const node of nodes){
          if(node.nodeType===1)node.dataset.robotPlannerPlugin=pid;
        }
        if(before && before!=="</body>"){
          const target=document.querySelector(before);
          if(target)target.before(tpl.content);
          else document.body.appendChild(tpl.content);
        }else{
          document.body.appendChild(tpl.content);
        }
        return true;
      },

      addPage(pageId,title,html,icon="◆"){
        if(typeof window.robotPlannerAddPluginPage!=="function")throw new Error("Robot Planner page API is not ready");
        return window.robotPlannerAddPluginPage({id:pageId,title,html,icon,owner:pid});
      },

      runJS(js){ return ctx.injectJS(js); },

      replaceGlobal(name,value){
        name=String(name);
        const old=window[name];
        window[name]=value;
        return old;
      },

      hookGlobal(name,{before=null,after=null,override=null}={}){
        name=String(name);
        const original=window[name];
        if(typeof original!=="function")throw new Error("global callable not found: "+name);
        window[name]=function(...args){
          if(typeof before==="function"){
            const changed=before(args);
            if(Array.isArray(changed))args=changed;
          }
          let result=typeof override==="function" ? override(original.bind(this),...args) : original.apply(this,args);
          if(typeof after==="function"){
            const changed=after(result,args);
            if(changed!==undefined)result=changed;
          }
          return result;
        };
        return original;
      },

      patchMethod(target,name,{before=null,after=null,override=null}={}){
        if(!target)throw new Error("patch target missing");
        const original=target[name];
        if(typeof original!=="function")throw new Error("method not callable: "+name);
        target[name]=function(...args){
          if(typeof before==="function"){
            const changed=before(args);
            if(Array.isArray(changed))args=changed;
          }
          let result=typeof override==="function" ? override(original.bind(this),...args) : original.apply(this,args);
          if(typeof after==="function"){
            const changed=after(result,args);
            if(changed!==undefined)result=changed;
          }
          return result;
        };
        return original;
      },

      async readData(name,defaultValue=null){
        const raw=await callBridge("pluginReadData",pid,String(name));
        if(typeof raw!=="string" || !raw)return defaultValue;
        try{return JSON.parse(raw);}catch(_){return defaultValue;}
      },

      async writeData(name,data){
        let raw;
        try{raw=JSON.stringify(data);}catch(e){throw new Error("plugin data is not JSON serializable: "+e);}
        return !!(await callBridge("pluginWriteData",pid,String(name),raw));
      },

      async readText(path){
        return String(await callBridge("pluginReadText",pid,safeRel(path)) ?? "");
      },

      async asset(path){
        return String(await callBridge("pluginReadAsset",pid,safeRel(path)) ?? "");
      },

      async injectCSSFile(path){
        const css=await ctx.readText(path);
        if(!css)throw new Error("CSS file not found: "+path);
        return ctx.injectCSS(css);
      },

      async injectJSFile(path){
        const js=await ctx.readText(path);
        if(!js)throw new Error("JS file not found: "+path);
        return ctx.injectJS(js);
      }
    };

    // Python PluginContext naming aliases make later automatic conversion simpler.
    ctx.inject_css=ctx.injectCSS;
    ctx.inject_js=ctx.injectJS;
    ctx.inject_html=ctx.injectHTML;
    ctx.add_page=ctx.addPage;
    ctx.run_js=ctx.runJS;
    ctx.replace_global=ctx.replaceGlobal;
    ctx.hook_global=ctx.hookGlobal;
    ctx.patch_method=ctx.patchMethod;
    ctx.register_service=ctx.registerService;
    ctx.replace_service=ctx.replaceService;
    ctx.get_service=ctx.getService;
    ctx.read_data=ctx.readData;
    ctx.write_data=ctx.writeData;

    owners.set(pid,ctx);
    return ctx;
  }

  async function executePayload(payload){
    const pid=String(payload?.id||"");
    const manifest=payload?.manifest||{};
    const code=String(payload?.code||"");
    if(!pid || !code)throw new Error("invalid plugin payload");

    const ctx=createContext(pid,manifest);
    const module={exports:{}};
    const exports=module.exports;

    const body=`${code}\n\n;return {\n`+
      `moduleExports: module.exports,\n`+
      `legacy:{\n`+
      `pre_load:(typeof pre_load==='function'?pre_load:null),\n`+
      `core_load:(typeof core_load==='function'?core_load:null),\n`+
      `ui_load:(typeof ui_load==='function'?ui_load:null),\n`+
      `app_ready:(typeof app_ready==='function'?app_ready:null),\n`+
      `shutdown:(typeof shutdown==='function'?shutdown:null),\n`+
      `on_unload:(typeof on_unload==='function'?on_unload:null)\n`+
      `}};\n//# sourceURL=robotplanner-plugin://${encodeURIComponent(pid)}/main.js`;

    const factory=new Function("ctx","manifest","module","exports","bridge","window","document",body);
    const result=factory(ctx,manifest,module,exports,window.bridge,window,document) || {};
    let api=result.moduleExports;
    if(typeof api==="function"){
      await api(ctx);
      api={};
    }else if(!api || typeof api!=="object" || Object.keys(api).length===0){
      api=result.legacy||{};
    }else{
      api={...(result.legacy||{}),...api};
    }

    for(const phase of ["pre_load","core_load","ui_load"]){
      if(typeof api[phase]==="function")await api[phase](ctx);
      emit("loader_phase",phase,pid);
    }
    if(typeof api.app_ready==="function")await api.app_ready(ctx);
    emit("plugin_loaded",pid,ctx);
    try{window.bridge?.pluginMarkLoaded?.(pid,()=>{});}catch(_){}
    return true;
  }

  window.__robotPlannerLoadPlugin=function(payload){
    const pid=String(payload?.id||"unknown");
    Promise.resolve().then(()=>executePayload(payload)).catch(e=>report(pid,e));
    return true;
  };

  window.__robotPlannerUnloadPlugin=function(pid){
    pid=String(pid);
    offOwner(pid);
    document.querySelectorAll(`[data-robot-planner-plugin="${CSS.escape(pid)}"],[data-plugin-owner="${CSS.escape(pid)}"]`).forEach(el=>el.remove());
    owners.delete(pid);
    emit("plugin_unloaded",pid);
    return true;
  };
})();
