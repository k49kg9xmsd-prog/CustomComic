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
