import Foundation
import UIKit
import WebKit
import UniformTypeIdentifiers
import ZIPFoundation

final class RobotBridge: NSObject, WKScriptMessageHandler, UIDocumentPickerDelegate {
    private weak var webView: WKWebView?
    private weak var host: UIViewController?
    private let store = RobotStore()
    private var pendingPicker: (id: String, method: String)?
    private var loadedPluginIDs = Set<String>()
    private var pluginRuntimeErrors: [String: String] = [:]

    init(webView: WKWebView, host: UIViewController) {
        self.webView = webView
        self.host = host
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "robotBridge",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let method = body["method"] as? String else { return }
        let args = body["args"] as? [Any] ?? []
        DispatchQueue.main.async { [weak self] in self?.handle(id: id, method: method, args: args) }
    }

    private func argString(_ args: [Any], _ i: Int) -> String { i < args.count ? (args[i] as? String ?? "") : "" }
    private func argDouble(_ args: [Any], _ i: Int) -> Double {
        guard i < args.count else { return 0 }
        if let n = args[i] as? NSNumber { return n.doubleValue }
        return Double(args[i] as? String ?? "") ?? 0
    }

    private func handle(id: String, method: String, args: [Any]) {
        switch method {
        case "listMaps": resolve(id, store.listMaps())
        case "saveMap": resolve(id, store.saveMap(name: argString(args,0), dataURL: argString(args,1)))
        case "readMap": resolve(id, store.readMap(name: argString(args,0)))
        case "listQuick": resolve(id, store.listQuick())
        case "saveQuick": resolve(id, store.saveQuick(name: argString(args,0), c: argDouble(args,1), r: argDouble(args,2)))
        case "renameQuick": resolve(id, store.renameQuick(old: argString(args,0), newName: argString(args,1)))
        case "listObstacles": resolve(id, store.listJSON(in: .obstacles))
        case "saveObstacle": resolve(id, store.saveJSON(name: argString(args,0), json: argString(args,1), kind: .obstacles, forceRobot: false))
        case "updateObstacle": resolve(id, store.updateJSON(file: argString(args,0), json: argString(args,1), kind: .obstacles, forceRobot: false))
        case "renameObstacle": resolve(id, store.renameJSON(old: argString(args,0), newName: argString(args,1), kind: .obstacles, forceRobot: false))
        case "listRobots": resolve(id, store.listJSON(in: .robots))
        case "saveRobot": resolve(id, store.saveJSON(name: argString(args,0), json: argString(args,1), kind: .robots, forceRobot: true))
        case "updateRobot": resolve(id, store.updateJSON(file: argString(args,0), json: argString(args,1), kind: .robots, forceRobot: true))
        case "renameRobot": resolve(id, store.renameJSON(old: argString(args,0), newName: argString(args,1), kind: .robots, forceRobot: true))
        case "renameResource": resolve(id, store.renameResource(kind: argString(args,0), old: argString(args,1), newName: argString(args,2)))
        case "deleteResource": resolve(id, store.deleteResource(kind: argString(args,0), name: argString(args,1)))
        case "saveState": resolve(id, store.saveState(name: argString(args,0), json: argString(args,1)))
        case "saveCalibrationSettings": resolve(id, store.saveCalibration(argString(args,0)))
        case "loadCalibrationSettings": resolve(id, store.loadCalibration())
        case "listSaves": resolve(id, store.listSaves())
        case "readSave": resolve(id, store.readSave(argString(args,0)))
        case "chooseObstacleObjectFile": chooseDocument(id: id, method: method, extensions: ["rpo"])
        case "chooseRobotObjectFile": chooseDocument(id: id, method: method, extensions: ["rpr"])
        case "importObstacleObject": resolve(id, store.importPackagedObject(path: argString(args,0), type: "obstacle"))
        case "importRobotObject": resolve(id, store.importPackagedObject(path: argString(args,0), type: "robot"))
        case "exportObstacleObject": exportObject(id: id, name: argString(args,0), json: argString(args,1), type: "obstacle", ext: "rpo")
        case "exportRobotObject": exportObject(id: id, name: argString(args,0), json: argString(args,1), type: "robot", ext: "rpr")
        case "exportCalibration": exportCalibration(id: id, json: argString(args,0))
        case "listPlugins":
            resolve(id, store.listPlugins(loaded: loadedPluginIDs, runtimeErrors: pluginRuntimeErrors))
        case "pluginSystemInfo":
            resolve(id, store.pluginSystemInfo(loaded: loadedPluginIDs))
        case "installPluginZip":
            chooseDocument(id: id, method: method, extensions: ["zip"])
        case "openPluginsFolder":
            sharePluginsBackup(id: id)
        case "openAIPluginGuide":
            sharePluginGuide(id: id)
        case "applyPluginChanges":
            let ok = store.applyPluginChanges(argString(args, 0))
            resolve(id, ok)
            if ok {
                loadedPluginIDs.removeAll()
                pluginRuntimeErrors.removeAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    self?.webView?.reload()
                }
            }
        case "pluginReadData":
            resolve(id, store.pluginReadData(pluginID: argString(args,0), name: argString(args,1)))
        case "pluginWriteData":
            resolve(id, store.pluginWriteData(pluginID: argString(args,0), name: argString(args,1), json: argString(args,2)))
        case "pluginReadText":
            resolve(id, store.pluginReadText(pluginID: argString(args,0), relativePath: argString(args,1)))
        case "pluginReadAsset":
            resolve(id, store.pluginReadAsset(pluginID: argString(args,0), relativePath: argString(args,1)))
        case "pluginReportError":
            let pid = argString(args,0)
            if !pid.isEmpty { pluginRuntimeErrors[pid] = argString(args,1) }
            resolve(id, true)
            refreshPluginManagerSoon()
        case "pluginMarkLoaded":
            let pid = argString(args,0)
            if !pid.isEmpty { loadedPluginIDs.insert(pid); pluginRuntimeErrors.removeValue(forKey: pid) }
            resolve(id, true)
            refreshPluginManagerSoon()
        default: resolve(id, NSNull())
        }
    }

    private func refreshPluginManagerSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.webView?.evaluateJavaScript("if(typeof loadPluginManager==='function')loadPluginManager();")
        }
    }

    func pageReady() {
        loadedPluginIDs.removeAll()
        pluginRuntimeErrors.removeAll()

        guard let runtimeURL = Bundle.main.url(forResource: "PluginRuntime", withExtension: "js"),
              let runtime = try? String(contentsOf: runtimeURL, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript(runtime) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.pluginRuntimeErrors["__runtime__"] = error.localizedDescription
                return
            }
            self.injectEnabledPlugins()
        }
    }

    private func injectEnabledPlugins() {
        let payloads = store.enabledPluginPayloads()
        for payload in payloads {
            guard let pid = payload["id"] as? String,
                  let data = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes]),
                  let json = String(data: data, encoding: .utf8) else { continue }
            webView?.evaluateJavaScript("window.__robotPlannerLoadPlugin(\(json));") { [weak self] _, error in
                if let error { self?.pluginRuntimeErrors[pid] = error.localizedDescription }
            }
        }
    }

    private func shareFile(id: String, url: URL, successValue: Any = true) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = host?.view
            pop.sourceRect = host?.view.bounds ?? .zero
        }
        host?.present(vc, animated: true)
        resolve(id, successValue)
    }

    private func sharePluginsBackup(id: String) {
        do {
            let url = try store.makePluginsBackup()
            shareFile(id: id, url: url)
        } catch {
            resolve(id, false)
        }
    }

    private func sharePluginGuide(id: String) {
        let guide = """
        Robot Planner iOS 插件開發指南

        插件 ZIP：
        MyPlugin.zip
        ├─ mod.json
        ├─ main.js
        └─ assets/...

        mod.json 最少需要：
        {"id":"example.plugin","name":"Example Plugin","version":"1.0.0","ios_entry":"main.js"}

        iOS 入口使用 JavaScript。main.js 可直接使用 ctx，或 export/module.exports 下列階段：
        pre_load(ctx), core_load(ctx), ui_load(ctx), app_ready(ctx)

        常用 API：
        ctx.injectCSS(css)
        ctx.injectJS(js)
        ctx.injectHTML(html)
        ctx.addPage(id, title, html, icon)
        ctx.on(event, callback)
        ctx.emit(event, ...args)
        await ctx.readData(name, defaultValue)
        await ctx.writeData(name, data)
        await ctx.readText("assets/file.txt")
        await ctx.asset("assets/image.png")

        Windows + iOS 共用 ZIP 建議同時放 main.py 與 main.js，並在 mod.json 使用 entry 與 ios_entry 分別指定。
        """
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Robot Planner iOS 插件開發指南.txt")
            try guide.data(using: .utf8)?.write(to: url, options: .atomic)
            shareFile(id: id, url: url)
        } catch {
            resolve(id, false)
        }
    }

    private func resolve(_ id: String, _ value: Any) {
        let safeValue: Any
        if JSONSerialization.isValidJSONObject([value]) { safeValue = value } else { safeValue = String(describing: value) }
        guard let data = try? JSONSerialization.data(withJSONObject: safeValue, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        let idJSON = String(data: try! JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed]), encoding: .utf8) ?? "\"\""
        webView?.evaluateJavaScript("window.__robotBridgeResolve(\(idJSON), \(json));")
    }

    private func chooseDocument(id: String, method: String, extensions: [String]) {
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types.isEmpty ? [.data] : types, asCopy: true)
        pendingPicker = (id, method)
        picker.delegate = self
        host?.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if let p = pendingPicker {
            if p.method == "installPluginZip" {
                resolve(p.id, "{\"ok\":false,\"cancelled\":true}")
            } else {
                resolve(p.id, "")
            }
        }
        pendingPicker = nil
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let p = pendingPicker else { return }
        defer { pendingPicker = nil }
        guard let src = urls.first else { resolve(p.id, ""); return }
        do {
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + src.pathExtension)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
            if p.method == "installPluginZip" {
                resolve(p.id, store.installPluginZip(at: dst))
                try? FileManager.default.removeItem(at: dst)
            } else {
                resolve(p.id, dst.path)
            }
        } catch {
            if p.method == "installPluginZip" {
                resolve(p.id, store.pluginResultJSON(["ok": false, "error": error.localizedDescription]))
            } else {
                resolve(p.id, "")
            }
        }
    }

    private func exportObject(id: String, name: String, json: String, type: String, ext: String) {
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { resolve(id, ""); return }
        let package: [String: Any] = [
            "format": type == "robot" ? "Robot Planner Robot" : "Robot Planner Object",
            "extension": ".\(ext)", "format_version": 1,
            "object_type": type, "data": object
        ]
        shareJSON(id: id, object: package, filename: store.safeStem(name, fallback: type) + "." + ext)
    }

    private func exportCalibration(id: String, json: String) {
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { resolve(id, ""); return }
        let package: [String: Any] = ["format":"Robot Planner Calibration","extension":".rpc","format_version":1,"data":object]
        shareJSON(id: id, object: package, filename: "Robot Planner Calibration.rpc")
    }

    private func shareJSON(id: String, object: Any, filename: String) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = vc.popoverPresentationController {
                pop.sourceView = host?.view
                pop.sourceRect = host?.view.bounds ?? .zero
            }
            host?.present(vc, animated: true)
            resolve(id, url.path)
        } catch { resolve(id, "") }
    }
}

private enum RobotFolder: String { case maps, quick = "quick_add", saves, obstacles, robots, plugins, pluginData = "plugins_data" }

private final class RobotStore {
    let base: URL
    let fm = FileManager.default

    init() {
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        base = root.appendingPathComponent("RobotPlanner", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        for f in [RobotFolder.maps,.quick,.saves,.obstacles,.robots,.plugins,.pluginData] {
            try? fm.createDirectory(at: folder(f), withIntermediateDirectories: true)
        }
    }

    func folder(_ f: RobotFolder) -> URL { base.appendingPathComponent(f.rawValue, isDirectory: true) }
    func safeStem(_ name: String, fallback: String = "item") -> String {
        var s = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let bad = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        s = s.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return s.isEmpty ? fallback : s
    }
    func unique(_ dir: URL, stem: String, suffix: String) -> URL {
        var p = dir.appendingPathComponent(stem + suffix); var n = 2
        while fm.fileExists(atPath: p.path) { p = dir.appendingPathComponent("\(stem) (\(n))\(suffix)"); n += 1 }
        return p
    }
    func contents(_ dir: URL) -> [URL] { (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] }

    func listMaps() -> [String] {
        let ok = Set(["png","jpg","jpeg","webp","bmp","gif"])
        return contents(folder(.maps)).filter { ok.contains($0.pathExtension.lowercased()) }.map(\.lastPathComponent).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    func saveMap(name: String, dataURL: String) -> String {
        guard let comma = dataURL.firstIndex(of: ","), let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return "" }
        let mime = String(dataURL[..<comma]).lowercased()
        var ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if !["png","jpg","jpeg","webp","bmp","gif"].contains(ext) {
            if mime.contains("jpeg") { ext="jpg" } else if mime.contains("webp") { ext="webp" } else if mime.contains("gif") { ext="gif" } else { ext="png" }
        }
        let p = unique(folder(.maps), stem: safeStem(name,fallback:"map"), suffix:"."+ext)
        do { try data.write(to:p,options:.atomic); return p.lastPathComponent } catch { return "" }
    }
    func readMap(name: String) -> String {
        let p=folder(.maps).appendingPathComponent(URL(fileURLWithPath:name).lastPathComponent)
        guard let data=try? Data(contentsOf:p) else{return ""}
        let ext=p.pathExtension.lowercased(); let mime = ext=="jpg" || ext=="jpeg" ? "image/jpeg" : "image/\(ext.isEmpty ? "png":ext)"
        return "data:\(mime);base64,"+data.base64EncodedString()
    }

    func listQuick() -> [[String:Any]] {
        contents(folder(.quick)).filter{$0.pathExtension.lowercased()=="json"}.sorted{$0.lastPathComponent<$1.lastPathComponent}.compactMap { u in
            guard let d=try? Data(contentsOf:u), var o=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any] else{return nil}
            o["file"]=u.lastPathComponent; return o
        }
    }
    func saveQuick(name:String,c:Double,r:Double)->String {
        let stem=safeStem(name,fallback:"point"), p=unique(folder(.quick),stem:stem,suffix:".json")
        let o:[String:Any]=["name":name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? stem:name,"c":c,"r":r]
        return writeJSON(o,to:p) ? p.lastPathComponent:""
    }
    func renameQuick(old:String,newName:String)->String {
        let src=folder(.quick).appendingPathComponent(URL(fileURLWithPath:old).lastPathComponent)
        guard let d=try? Data(contentsOf:src), var o=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any] else{return ""}
        o["name"]=newName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? safeStem(newName,fallback:"point"):newName
        let dst=unique(folder(.quick),stem:safeStem(newName,fallback:"point"),suffix:".json")
        guard writeJSON(o,to:dst) else{return ""}; try? fm.removeItem(at:src); return dst.lastPathComponent
    }

    func listJSON(in kind:RobotFolder)->[[String:Any]] {
        contents(folder(kind)).filter{$0.pathExtension.lowercased()=="json"}.sorted{$0.lastPathComponent<$1.lastPathComponent}.compactMap { u in
            guard let d=try? Data(contentsOf:u), var o=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any] else{return nil}; o["file"]=u.lastPathComponent; return o
        }
    }
    func parseObject(_ json:String)->[String:Any]? { guard let d=json.data(using:.utf8) else{return nil}; return (try? JSONSerialization.jsonObject(with:d)) as? [String:Any] }
    func saveJSON(name:String,json:String,kind:RobotFolder,forceRobot:Bool)->String {
        guard var o=parseObject(json) else{return ""}; let stem=safeStem(name,fallback:forceRobot ? "robot":"obstacle"); o["name"]=name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? stem:name; if forceRobot{o["objectType"]="robot"}
        let p=unique(folder(kind),stem:stem,suffix:".json"); return writeJSON(o,to:p) ? p.lastPathComponent:""
    }
    func updateJSON(file:String,json:String,kind:RobotFolder,forceRobot:Bool)->Bool {
        let p=folder(kind).appendingPathComponent(URL(fileURLWithPath:file).lastPathComponent); guard fm.fileExists(atPath:p.path), var o=parseObject(json) else{return false}; if forceRobot{o["objectType"]="robot"}; return writeJSON(o,to:p)
    }
    func renameJSON(old:String,newName:String,kind:RobotFolder,forceRobot:Bool)->String {
        let src=folder(kind).appendingPathComponent(URL(fileURLWithPath:old).lastPathComponent); guard let d=try? Data(contentsOf:src), var o=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any] else{return ""}; o["name"]=newName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? safeStem(newName):newName; if forceRobot{o["objectType"]="robot"}; let dst=unique(folder(kind),stem:safeStem(newName),suffix:".json"); guard writeJSON(o,to:dst) else{return ""}; try? fm.removeItem(at:src); return dst.lastPathComponent
    }

    func folderForKind(_ kind:String)->RobotFolder? { ["maps":.maps,"saves":.saves,"quick":.quick,"obstacles":.obstacles,"robots":.robots][kind] }
    func renameResource(kind:String,old:String,newName:String)->String {
        guard let k=folderForKind(kind) else{return ""}; let src=folder(k).appendingPathComponent(URL(fileURLWithPath:old).lastPathComponent); guard fm.fileExists(atPath:src.path) else{return ""}; let suffix=kind=="maps" ? (src.pathExtension.isEmpty ? "":"."+src.pathExtension):".json"; let dst=unique(folder(k),stem:safeStem(newName,fallback:src.deletingPathExtension().lastPathComponent),suffix:suffix); do{try fm.moveItem(at:src,to:dst); return dst.lastPathComponent}catch{return ""}
    }
    func deleteResource(kind:String,name:String)->Bool { guard let k=folderForKind(kind) else{return false}; let p=folder(k).appendingPathComponent(URL(fileURLWithPath:name).lastPathComponent); if fm.fileExists(atPath:p.path){do{try fm.removeItem(at:p)}catch{return false}}; return true }
    func saveState(name:String,json:String)->String { guard let d=json.data(using:.utf8), (try? JSONSerialization.jsonObject(with:d)) != nil else{return ""}; let p=unique(folder(.saves),stem:safeStem(name,fallback:"save"),suffix:".json"); do{try d.write(to:p,options:.atomic);return p.lastPathComponent}catch{return ""} }
    func listSaves() -> [String] {
        contents(folder(.saves))
            .filter { $0.pathExtension.lowercased() == "json" }
            .map(\.lastPathComponent)
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }
    func readSave(_ name:String)->String { let p=folder(.saves).appendingPathComponent(URL(fileURLWithPath:name).lastPathComponent); return (try? String(contentsOf:p,encoding:.utf8)) ?? "" }
    func saveCalibration(_ json:String)->Bool { guard let d=json.data(using:.utf8), (try? JSONSerialization.jsonObject(with:d)) != nil else{return false}; do{try d.write(to:base.appendingPathComponent("calibration.json"),options:.atomic);return true}catch{return false} }
    func loadCalibration()->String { (try? String(contentsOf:base.appendingPathComponent("calibration.json"),encoding:.utf8)) ?? "" }


    // MARK: - iOS JavaScript Mod Loader

    private struct PluginRecord {
        let id: String
        let folder: URL
        let manifest: [String: Any]
        let iosEntry: String?
        let compatible: Bool
        let staticError: String?
    }

    private var pluginConfigURL: URL { base.appendingPathComponent("plugins.json") }

    private func readPluginConfig() -> [String: Bool] {
        guard let data = try? Data(contentsOf: pluginConfigURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let enabled = root["enabled"] as? [String: Any] else { return [:] }
        var out: [String: Bool] = [:]
        for (key, value) in enabled {
            if let b = value as? Bool { out[key] = b }
            else if let n = value as? NSNumber { out[key] = n.boolValue }
        }
        return out
    }

    private func writePluginConfig(_ enabled: [String: Bool]) -> Bool {
        writeJSON(["enabled": enabled], to: pluginConfigURL)
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let a = value as? [String] { return a }
        if let a = value as? [Any] { return a.map { String(describing: $0) } }
        if let s = value as? String, !s.isEmpty { return [s] }
        return []
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    private func validPluginID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    private func normalizedPluginRelativePath(_ raw: String) -> String? {
        let path = raw.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        guard let first = parts.first, !first.contains(":") else { return nil }
        return parts.map(String.init).joined(separator: "/")
    }

    private func resolveIOSEntry(manifest: [String: Any], root: URL) -> (String?, String?) {
        let explicit = (manifest["ios_entry"] as? String) ?? (manifest["iosEntry"] as? String)
        let legacy = manifest["entry"] as? String
        var candidate: String?

        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidate = explicit
        } else if let legacy, URL(fileURLWithPath: legacy).pathExtension.lowercased() == "js" {
            candidate = legacy
        } else if fm.fileExists(atPath: root.appendingPathComponent("main.js").path) {
            candidate = "main.js"
        }

        guard let candidate else {
            return (nil, "需要轉換：此插件只有 Python 入口，iOS 版需要 main.js 或 ios_entry。")
        }
        guard let rel = normalizedPluginRelativePath(candidate) else {
            return (nil, "iOS 插件入口路徑不安全：\(candidate)")
        }
        let file = root.appendingPathComponent(rel).standardizedFileURL
        let rootPath = root.standardizedFileURL.path + "/"
        guard file.path.hasPrefix(rootPath), fm.fileExists(atPath: file.path) else {
            return (rel, "找不到 iOS 插件入口：\(rel)")
        }
        return (rel, nil)
    }

    private func scanPluginRecords() -> [PluginRecord] {
        var out: [PluginRecord] = []
        for dir in contents(folder(.plugins)).sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            var isDir: ObjCBool = false
            guard !dir.lastPathComponent.hasPrefix("."), fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let manifestURL = dir.appendingPathComponent("mod.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let id = ((manifest["id"] as? String) ?? dir.lastPathComponent).trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = resolveIOSEntry(manifest: manifest, root: dir)
            let idError = validPluginID(id) ? nil : "插件 id 無效：\(id)"
            let error = idError ?? entry.1
            out.append(PluginRecord(id: id, folder: dir, manifest: manifest, iosEntry: entry.0, compatible: error == nil, staticError: error))
        }
        return out
    }

    private func configuredEnabled(_ record: PluginRecord, config: [String: Bool]) -> Bool {
        if let value = config[record.id] { return value }
        return boolValue(record.manifest["enabled_by_default"])
    }

    private func orderedEnabledPlugins() -> ([PluginRecord], [String: String]) {
        let records = scanPluginRecords()
        let config = readPluginConfig()
        var enabled: [String: PluginRecord] = [:]
        for r in records where configuredEnabled(r, config: config) { enabled[r.id] = r }
        var errors: [String: String] = [:]

        for (id, r) in enabled {
            if let e = r.staticError { errors[id] = e; continue }
            let missing = stringArray(r.manifest["depends"]).filter { enabled[$0] == nil }
            if !missing.isEmpty { errors[id] = "缺少依賴：" + missing.joined(separator: ", "); continue }
            let conflicts = stringArray(r.manifest["conflicts"]).filter { enabled[$0] != nil }
            if !conflicts.isEmpty { errors[id] = "插件衝突：" + conflicts.joined(separator: ", ") }
        }

        var valid = enabled.filter { errors[$0.key] == nil }
        var changed = true
        while changed {
            changed = false
            var removeIDs: [String] = []
            for (id, r) in valid {
                let unavailable = stringArray(r.manifest["depends"]).filter { valid[$0] == nil }
                if !unavailable.isEmpty {
                    errors[id] = "依賴插件無法載入：" + unavailable.joined(separator: ", ")
                    removeIDs.append(id)
                }
            }
            if !removeIDs.isEmpty {
                for id in removeIDs { valid.removeValue(forKey: id) }
                changed = true
            }
        }

        var edges: [String: Set<String>] = [:]
        for id in valid.keys { edges[id] = [] }
        for (id, r) in valid {
            for dep in stringArray(r.manifest["depends"]) + stringArray(r.manifest["load_after"]) where valid[dep] != nil {
                edges[id, default: []].insert(dep)
            }
            for later in stringArray(r.manifest["load_before"]) where valid[later] != nil {
                edges[later, default: []].insert(id)
            }
        }

        var remaining = Set(valid.keys)
        var ordered: [PluginRecord] = []
        while !remaining.isEmpty {
            let ready = remaining.filter { (edges[$0] ?? []).intersection(remaining).isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if ready.isEmpty {
                for id in remaining { errors[id] = "插件依賴／載入順序形成循環" }
                break
            }
            for id in ready {
                if let r = valid[id] { ordered.append(r) }
                remaining.remove(id)
            }
        }
        return (ordered, errors)
    }

    func listPlugins(loaded: Set<String>, runtimeErrors: [String: String]) -> [[String: Any]] {
        let records = scanPluginRecords()
        let config = readPluginConfig()
        let (_, validationErrors) = orderedEnabledPlugins()
        return records.map { r in
            let m = r.manifest
            let error = runtimeErrors[r.id] ?? validationErrors[r.id] ?? r.staticError ?? ""
            return [
                "id": r.id,
                "name": (m["name"] as? String) ?? r.id,
                "version": (m["version"] as? String) ?? "0.0.0",
                "author": (m["author"] as? String) ?? "",
                "description": (m["description"] as? String) ?? "",
                "enabled": configuredEnabled(r, config: config),
                "loaded": loaded.contains(r.id),
                "error": error,
                "permissions": stringArray(m["permissions"]),
                "folder": r.folder.lastPathComponent,
                "requiresRestart": false,
                "compatible": r.compatible,
                "needsConversion": !r.compatible && r.iosEntry == nil,
                "iosEntry": r.iosEntry ?? ""
            ]
        }
    }

    func pluginSystemInfo(loaded: Set<String>) -> String {
        pluginResultJSON([
            "safeMode": false,
            "loaderVersion": "iOS-JS-1.0",
            "platform": "iOS",
            "runtime": "JavaScript",
            "loaded": Array(loaded).sorted()
        ])
    }

    func enabledPluginPayloads() -> [[String: Any]] {
        let (records, _) = orderedEnabledPlugins()
        var out: [[String: Any]] = []
        for r in records {
            guard let entry = r.iosEntry,
                  let source = try? String(contentsOf: r.folder.appendingPathComponent(entry), encoding: .utf8) else { continue }
            out.append(["id": r.id, "manifest": r.manifest, "code": source])
        }
        return out
    }

    func pluginResultJSON(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    func installPluginZip(at zipURL: URL) -> String {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("rp_plugin_" + UUID().uuidString, isDirectory: true)
        let installing = folder(.plugins).appendingPathComponent(".installing_" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: staging); try? fm.removeItem(at: installing) }

        do {
            guard zipURL.pathExtension.lowercased() == "zip" else { throw NSError(domain: "RobotPlanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "請選擇 .zip 插件壓縮檔"]) }

            let archive = try Archive(url: zipURL, accessMode: .read)
            var fileCount = 0
            var total: UInt64 = 0
            for entry in archive {
                let name = entry.path.replacingOccurrences(of: "\\", with: "/")
                let parts = name.split(separator: "/")
                if name.hasPrefix("/") || parts.contains(where: { $0 == ".." }) || (parts.first?.contains(":") ?? false) {
                    throw NSError(domain: "RobotPlanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "ZIP 內含不安全路徑：\(name)"])
                }
                fileCount += 1
                total += entry.uncompressedSize
                if fileCount > 5000 { throw NSError(domain: "RobotPlanner", code: 3, userInfo: [NSLocalizedDescriptionKey: "ZIP 檔案數過多（最多 5000 個）"]) }
                if total > UInt64(200 * 1024 * 1024) { throw NSError(domain: "RobotPlanner", code: 4, userInfo: [NSLocalizedDescriptionKey: "ZIP 解壓後大小超過 200 MB"]) }
            }

            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.unzipItem(at: zipURL, to: staging)

            var manifests: [URL] = []
            if let e = fm.enumerator(at: staging, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) {
                for case let u as URL in e {
                    let values = try? u.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values?.isSymbolicLink == true { throw NSError(domain: "RobotPlanner", code: 5, userInfo: [NSLocalizedDescriptionKey: "ZIP 不允許符號連結：\(u.lastPathComponent)"]) }
                    if u.lastPathComponent == "mod.json" && !u.path.contains("/__MACOSX/") { manifests.append(u) }
                }
            }
            guard manifests.count == 1, let manifestURL = manifests.first else {
                throw NSError(domain: "RobotPlanner", code: 6, userInfo: [NSLocalizedDescriptionKey: manifests.isEmpty ? "ZIP 裡找不到 mod.json" : "ZIP 裡有多個 mod.json，無法判斷插件根目錄"])
            }
            let manifestData = try Data(contentsOf: manifestURL)
            if manifestData.count > 2 * 1024 * 1024 { throw NSError(domain: "RobotPlanner", code: 7, userInfo: [NSLocalizedDescriptionKey: "mod.json 過大"]) }
            guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
                throw NSError(domain: "RobotPlanner", code: 8, userInfo: [NSLocalizedDescriptionKey: "mod.json 最外層必須是 JSON object"])
            }
            let root = manifestURL.deletingLastPathComponent()
            let id = ((manifest["id"] as? String) ?? root.lastPathComponent).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, validPluginID(id) else { throw NSError(domain: "RobotPlanner", code: 9, userInfo: [NSLocalizedDescriptionKey: "插件 id 只能使用英文、數字、點、底線與減號"]) }
            if scanPluginRecords().contains(where: { $0.id == id }) { throw NSError(domain: "RobotPlanner", code: 10, userInfo: [NSLocalizedDescriptionKey: "插件 \(id) 已存在，請先刪除舊版再安裝新版"] ) }

            let final = folder(.plugins).appendingPathComponent(id, isDirectory: true)
            guard !fm.fileExists(atPath: final.path) else { throw NSError(domain: "RobotPlanner", code: 11, userInfo: [NSLocalizedDescriptionKey: "plugins/\(id) 已存在"]) }
            try fm.createDirectory(at: installing, withIntermediateDirectories: true)
            for child in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                try fm.copyItem(at: child, to: installing.appendingPathComponent(child.lastPathComponent))
            }
            try fm.moveItem(at: installing, to: final)

            var config = readPluginConfig()
            config[id] = false
            guard writePluginConfig(config) else {
                try? fm.removeItem(at: final)
                throw NSError(domain: "RobotPlanner", code: 12, userInfo: [NSLocalizedDescriptionKey: "無法寫入 plugins.json"])
            }

            let entry = resolveIOSEntry(manifest: manifest, root: final)
            return pluginResultJSON([
                "ok": true,
                "id": id,
                "name": (manifest["name"] as? String) ?? id,
                "version": (manifest["version"] as? String) ?? "0.0.0",
                "files": fileCount,
                "source": zipURL.lastPathComponent,
                "compatible": entry.1 == nil,
                "needsConversion": entry.0 == nil,
                "warning": entry.1 ?? ""
            ])
        } catch {
            return pluginResultJSON(["ok": false, "error": error.localizedDescription])
        }
    }

    func applyPluginChanges(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        let records = scanPluginRecords()
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let deletes = stringArray(payload["delete"])
        for id in deletes {
            if let record = byID[id] { try? fm.removeItem(at: record.folder) }
        }
        let requested = payload["enabled"] as? [String: Any] ?? [:]
        let remaining = scanPluginRecords()
        let old = readPluginConfig()
        var next: [String: Bool] = [:]
        for r in remaining {
            if let b = requested[r.id] as? Bool { next[r.id] = b }
            else if let n = requested[r.id] as? NSNumber { next[r.id] = n.boolValue }
            else if let b = old[r.id] { next[r.id] = b }
            else { next[r.id] = boolValue(r.manifest["enabled_by_default"]) }
        }
        return writePluginConfig(next)
    }

    private func pluginRecord(_ id: String) -> PluginRecord? { scanPluginRecords().first { $0.id == id } }

    private func pluginFileURL(pluginID: String, relativePath: String) -> URL? {
        guard let record = pluginRecord(pluginID), let rel = normalizedPluginRelativePath(relativePath) else { return nil }
        let root = record.folder.standardizedFileURL
        let file = root.appendingPathComponent(rel).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        return file
    }

    func pluginReadText(pluginID: String, relativePath: String) -> String {
        guard let file = pluginFileURL(pluginID: pluginID, relativePath: relativePath) else { return "" }
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    func pluginReadAsset(pluginID: String, relativePath: String) -> String {
        guard let file = pluginFileURL(pluginID: pluginID, relativePath: relativePath), let data = try? Data(contentsOf: file) else { return "" }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mime);base64," + data.base64EncodedString()
    }

    func pluginReadData(pluginID: String, name: String) -> String {
        guard validPluginID(pluginID) else { return "" }
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        guard !safeName.isEmpty else { return "" }
        let dir = folder(.pluginData).appendingPathComponent(pluginID, isDirectory: true)
        let file = dir.appendingPathComponent(safeName)
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    func pluginWriteData(pluginID: String, name: String, json: String) -> Bool {
        guard validPluginID(pluginID), let data = json.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else { return false }
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        guard !safeName.isEmpty else { return false }
        let dir = folder(.pluginData).appendingPathComponent(pluginID, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(safeName), options: .atomic)
            return true
        } catch { return false }
    }

    func makePluginsBackup() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RobotPlanner-Plugins.zip")
        try? fm.removeItem(at: url)
        try fm.zipItem(at: folder(.plugins), to: url, shouldKeepParent: true, compressionMethod: .deflate)
        return url
    }

    func importPackagedObject(path:String,type:String)->String {
        let p=URL(fileURLWithPath:path); guard let d=try? Data(contentsOf:p), let pack=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any], var obj=pack["data"] as? [String:Any] else{return ""}
        let expected = type=="robot" ? "Robot Planner Robot":"Robot Planner Object"; guard (pack["format"] as? String)==expected, (pack["object_type"] as? String)==type else{return ""}
        obj["id"]="\(type)_\(Int(Date().timeIntervalSince1970*1000))_\(UUID().uuidString.prefix(6))"; if type=="robot"{obj["objectType"]="robot"}; let name=(obj["name"] as? String) ?? p.deletingPathExtension().lastPathComponent; obj["name"]=name; let kind:RobotFolder=type=="robot" ? .robots:.obstacles; let dst=unique(folder(kind),stem:safeStem(name,fallback:type),suffix:".json"); return writeJSON(obj,to:dst) ? dst.lastPathComponent:""
    }
    func writeJSON(_ obj:Any,to url:URL)->Bool { do{let d=try JSONSerialization.data(withJSONObject:obj,options:[.prettyPrinted,.withoutEscapingSlashes]);try d.write(to:url,options:.atomic);return true}catch{return false} }
}
