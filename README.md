# Robot Planner iOS — Codemagic unsigned IPA

這個專案按照你提供的 Codemagic 參考包整理，不需要先建立 `.xcodeproj`。Codemagic 會先安裝 XcodeGen，根據 `project.yml` 生成 Xcode 專案，再以 `CODE_SIGNING_ALLOWED=NO` 編譯並封裝 unsigned IPA。

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
- 點一下下方「機器人／障礙物卡片」：選取要放置的物件，再點賽墊完成放置。
- 長按機器人／障礙物卡片：重新命名、編輯、匯出或刪除。
- 資源列表：點一下載入，長按重新命名或刪除。
- 物件編輯器：手指直接繪製／擦除／拖曳；點一下方向標記可輸入旋轉角度。
- 不需要滑鼠右鍵、Ctrl＋滾輪或滑鼠滾輪旋轉。

## iOS 版架構
- 原 Robot Planner 的 HTML / CSS / JavaScript / SVG 路線規劃核心保留在 `RobotPlanner/index.html`。
- Qt `QWebEngineView + QWebChannel` 改為 `WKWebView + WKScriptMessageHandler`。
- maps / quick_add / saves / obstacles / robots / calibration 改存到 iOS Application Support。
- `.rpo` / `.rpr` 使用 iOS 文件選擇器匯入；匯出叫出 iOS 分享面板。
- App Icon 已換成黑底白色 R 標誌。

## 與電腦版的差異
原版插件系統允許插件直接執行 Python Full Access。iOS 不適合照原版方式執行下載進 App 的任意 Python，因此目前 iOS 包保留主程式功能，但停用 Python 插件執行層。

## 最低版本
iOS 16.0，支援 iPhone / iPad。
