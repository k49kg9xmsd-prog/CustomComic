# 自訂漫畫庫－Codemagic 雲端 IPA 版

本版本沒有任何隱藏資料夾或隱藏檔案。

根目錄可直接看到：

- codemagic.yaml
- project.yml
- CustomComic/
- README.md

## 使用方法

1. 將本壓縮檔解壓。
2. 把所有內容上傳到 GitHub repository。
3. 到 Codemagic 登入並連接該 GitHub repository。
4. Codemagic 會讀取根目錄的 `codemagic.yaml`。
5. 選擇 `Build CustomComic unsigned IPA` 並開始編譯。
6. 完成後在 Artifacts 下載 `CustomComic-unsigned.ipa`。
7. 用 SideStore、AltStore 或其他簽名工具簽名安裝。

注意：
- 這是未簽名 IPA。
- 不需要把 Apple 帳號或憑證放進專案。
- 圖片匯入後會保存在 App 內，可離線閱讀。


## v3 修正
- 移除只支援 iOS 17 的 `ContentUnavailableView`
- 改用自製空白書庫畫面
- 保持最低支援 iOS 16


## v4 修正
- `ComicLibrary.swift` 加入 `import Combine`
- 修正 `ObservableObject` 與 `@Published` 無法編譯


## v5 更新
- 已加入正式 App 圖標
- 圖標位置：`CustomComic/Assets.xcassets/AppIcon.appiconset`
- XcodeGen 已設定 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`


## v6 更新
- 匯入方式由資料夾改為 ZIP
- ZIP 可包含多層子資料夾
- 自動找出 JPEG、PNG、WebP 等圖片
- 未自訂封面時，隨機選一張漫畫圖片當封面
- 加入 ZIPFoundation Swift Package
