# 柚子側載（YuzuSideload）基礎版

這是一個可直接上傳 GitHub，並交給 Codemagic 建置未簽名 IPA 的 SwiftUI 專案。

## 已有功能
- 匯入 `.ipa`
- 解析 Payload 內的 `Info.plist`
- 顯示 App 名稱、Bundle ID、版本、Build、檔案大小
- 嘗試讀取 App Icon
- 將 IPA 保存到 App 本機資料庫
- 搜尋、刪除、分享 IPA
- 可從分享選單轉交 SideStore、TrollStore 或其他安裝器
- iPhone／iPad，最低 iOS 16

## Codemagic 使用方式
1. 將本資料夾所有內容放在 GitHub 儲存庫根目錄。
2. Codemagic 新增 App，選擇該 GitHub 儲存庫。
3. 選擇 `codemagic.yaml` workflow。
4. 執行 `ios-unsigned`。
5. 在 Artifacts 下載 `YuzuSideload-unsigned.ipa`。

## 重要限制
未簽名 IPA 不能直接在所有正常 iOS 裝置安裝。一般裝置仍需 SideStore、AltStore、企業／開發者簽名等方式；只有相容 TrollStore 的系統可利用其方式永久安裝。
