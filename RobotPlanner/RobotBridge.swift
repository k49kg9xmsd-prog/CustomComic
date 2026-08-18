import Foundation
import UIKit
import WebKit
import UniformTypeIdentifiers

final class RobotBridge: NSObject, WKScriptMessageHandler, UIDocumentPickerDelegate {
    private weak var webView: WKWebView?
    private weak var host: UIViewController?
    private let store = RobotStore()
    private var pendingPicker: (id: String, method: String)?

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
        case "listPlugins": resolve(id, [])
        case "pluginSystemInfo":
            resolve(id, "{\"safeMode\":false,\"loaderVersion\":\"iOS\",\"platform\":\"iOS\",\"loaded\":[]}")
        case "installPluginZip":
            resolve(id, "{\"ok\":false,\"error\":\"iOS 版無法執行 Robot Planner 的 Python Full Access 插件。\"}")
        case "openPluginsFolder", "openAIPluginGuide", "applyPluginChanges": resolve(id, false)
        default: resolve(id, NSNull())
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
        if let p = pendingPicker { resolve(p.id, "") }
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
            resolve(p.id, dst.path)
        } catch { resolve(p.id, "") }
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

    func importPackagedObject(path:String,type:String)->String {
        let p=URL(fileURLWithPath:path); guard let d=try? Data(contentsOf:p), let pack=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any], var obj=pack["data"] as? [String:Any] else{return ""}
        let expected = type=="robot" ? "Robot Planner Robot":"Robot Planner Object"; guard (pack["format"] as? String)==expected, (pack["object_type"] as? String)==type else{return ""}
        obj["id"]="\(type)_\(Int(Date().timeIntervalSince1970*1000))_\(UUID().uuidString.prefix(6))"; if type=="robot"{obj["objectType"]="robot"}; let name=(obj["name"] as? String) ?? p.deletingPathExtension().lastPathComponent; obj["name"]=name; let kind:RobotFolder=type=="robot" ? .robots:.obstacles; let dst=unique(folder(kind),stem:safeStem(name,fallback:type),suffix:".json"); return writeJSON(obj,to:dst) ? dst.lastPathComponent:""
    }
    func writeJSON(_ obj:Any,to url:URL)->Bool { do{let d=try JSONSerialization.data(withJSONObject:obj,options:[.prettyPrinted,.withoutEscapingSlashes]);try d.write(to:url,options:.atomic);return true}catch{return false} }
}
