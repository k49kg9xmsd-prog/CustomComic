# Robot Planner iOS — Codemagic unsigned IPA

這個專案維持 Codemagic + XcodeGen 的打包方式。Codemagic 會根據 `project.yml` 產生 Xcode 專案，再以 `CODE_SIGNING_ALLOWED=NO` 編譯並封裝 unsigned IPA。

## 使用方式
1. 把整個資料夾上傳到 GitHub repository。
2. 在 Codemagic 加入該 repository。
3. Codemagic 讀取根目錄的 `codemagic.yaml`。
4. 執行 workflow：`ios-unsigned`。
5. 在 Artifacts 下載 `RobotPlanner-unsigned.ipa`。
6. 再用自己的簽名方式安裝。

## iPhone / iPad 操作
- 點一下空白賽墊：新增路徑點。
- 單指拖曳點位、機器人、障礙物：移動。
- 單指拖曳賽墊空白處：平移賽墊。
- 雙指捏合：縮放賽墊。
- 長按點位／已放置物件：開啟管理選單。
- 點一下機器人／障礙物卡片：選取，再點賽墊放置。
- 長按機器人／障礙物卡片：重新命名、編輯、匯出或刪除。
- 資源列表：點一下載入，長按重新命名或刪除。
- 物件編輯器：手指直接繪製／擦除／拖曳；點一下方向標記可輸入角度。

## iOS 插件系統
本版已恢復真正可運作的 iOS Mod Loader，不再是只有插件管理頁面。

支援：
- 直接選擇 `.zip` 安裝插件。
- `mod.json` 掃描與插件 ID / 版本 / 作者 / 權限顯示。
- 插件啟用、停用、刪除、儲存後重新載入。
- `depends`、`conflicts`、`load_after`、`load_before`。
- `main.js` 或 `ios_entry` JavaScript 入口。
- `pre_load`、`core_load`、`ui_load`、`app_ready` 階段。
- CSS / JavaScript / HTML 注入。
- 動態新增 Robot Planner 頁面。
- Event Bus。
- Service registry。
- replaceGlobal / hookGlobal / patchMethod。
- 插件自己的 JSON 資料讀寫。
- 讀取插件內文字與圖片／其他 assets。
- 插件錯誤回報與管理器顯示。
- 一鍵備份已安裝插件 ZIP。

### iOS 插件格式
```text
MyPlugin.zip
├─ mod.json
├─ main.js
└─ assets/
```

最小 `mod.json`：
```json
{
  "id": "example.plugin",
  "name": "Example Plugin",
  "version": "1.0.0",
  "ios_entry": "main.js"
}
```

Windows + iOS 共用 ZIP 建議：
```text
MyPlugin.zip
├─ mod.json
├─ main.py      # Windows / Python 版
├─ main.js      # iOS 版
└─ assets/
```

```json
{
  "id": "example.plugin",
  "entry": "main.py",
  "ios_entry": "main.js"
}
```

只有 `main.py` 的舊插件也可以匯入保存，但管理器會標示「需要轉換」，不會假裝已經能在 iOS 執行。之後可以用獨立的插件轉換網站產生 `main.js`。

## 插件測試
專案內附：
`TestPlugins/Hello_iOS_Plugin.zip`

安裝並啟用後，如果插件系統正常，頂部導覽會多出「🧩 插件測試」頁面。

## iOS 版架構
- Robot Planner HTML / CSS / JavaScript / SVG 核心：`RobotPlanner/index.html`
- iOS App 外殼：`WKWebView`
- Native Bridge：`RobotPlanner/RobotBridge.swift`
- iOS Mod Runtime：`RobotPlanner/PluginRuntime.js`
- 插件、地圖、存檔、校正、Robot、Obstacle：iOS Application Support
- `.rpo` / `.rpr`：iOS 文件選擇器匯入與分享面板匯出
- 插件 ZIP 壓縮／解壓使用 ZIPFoundation Swift Package

## 最低版本
- iOS 16.0
- iPhone / iPad


## iPad touch drag update
Object cards can now be dragged directly to the mat with touch. Horizontal swiping still scrolls the library, long-press keeps the management menu, and tap-then-tap placement remains as a fallback.
