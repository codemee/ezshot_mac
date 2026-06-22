# Ezshot

[English](README.md)

Ezshot 是一個原生 macOS 截圖與圖片標註工具。它提供選單列狀態圖示、全域快捷鍵、截圖後的多頁籤編輯視窗，並且只有在你按下 `Cmd+S` 時才會把目前頁籤存成檔案。

## 系統需求

- macOS 14 或更新版本
- Swift 6 toolchain
- 允許 Screen Recording 權限以進行截圖

## 功能

- 原生 macOS app，提供選單列狀態項目與自訂相機圖示。
- 會以一般 macOS app 形式出現在 `Cmd+Tab`，編輯視窗可透過 `Cmd+Tab` 取得焦點；app switcher 使用粉色圓角底的相機圖示。
- 全域截圖快捷鍵：
  - `Option+Shift+R`：框選螢幕區域。
  - `Option+Shift+A`：截取目前焦點視窗。
  - `Option+Shift+W`：點選要截取的視窗。
- 點選視窗截圖可以選取 Ezshot 自己的編輯視窗。
- 區域選取 overlay 具備十字準星、水平/垂直輔助線與拖曳框選。
- 可設定延遲截圖；選好截圖標的後會顯示倒數，再進行截圖。
- 多頁籤截圖編輯器。每次截圖會開成新的頁籤/視窗，未按 `Cmd+S` 前不會寫入檔案。
- 關閉編輯視窗時會隱藏編輯 UI 並清掉目前開啟的頁籤，但 app 仍會留在選單列可繼續使用。
- 可把圖片檔拖曳到空白或既有編輯視窗，匯入成新的可編輯頁籤；匯入頁籤會使用原始檔名作為標題。
- 編輯工具：
  - 常駐裁切控點與即時裁切預覽。
  - 畫筆、箭頭、矩形、馬賽克與文字工具。
  - 工具快捷鍵統一使用 `Option` 加工具字母，例如 `Option+L`、`Option+R` 與 `Option+T`。
  - 復原編輯。
  - 複製編修後圖片到剪貼簿。
  - 線條顏色與粗細設定。
  - 文字內容、字型與字體大小設定。
  - 圖片區域會依目前工具顯示不同游標。
- 編輯畫布背景會依淺色/深色外觀切換，讓圖片邊界保持清楚。
- 可切換截圖後自動複製到剪貼簿。
- 可設定登入後自動開啟。
- 語言設定支援依系統設定、繁體中文與英文；不支援的系統語言會 fallback 到英文。
- 外觀設定支援依系統主題、淺色與深色。

## 儲存

`Cmd+S` 只會儲存目前頁籤。第一次儲存會顯示 macOS 儲存面板並提供預設 PNG 檔名，之後再次儲存會直接覆寫同一路徑。

`Cmd+Shift+S` 會永遠顯示儲存面板以另存新檔。Ezshot 可以寫出 PNG、JPG 與 JPEG 檔案；成功儲存後，頁籤標題會更新為存檔檔名，文件也會記住該路徑供之後覆寫。

## 開發

```sh
swift build
swift run ezshot-core-tests
sh scripts/run-app.sh --rebuild
sh scripts/run-app.sh
```

這個 app 會提供選單列狀態項目。你可以從狀態選單開始截圖、顯示截圖視窗、切換自動複製與結束 app。

手動測試時請使用 `scripts/run-app.sh`，不要直接用 `swift run ezshot`。macOS Screen Recording 權限會綁定 app identity；`scripts/run-app.sh --rebuild` 會重新 build 並簽署 `.build/Ezshot.app`，一般的 `scripts/run-app.sh` 會重新啟動既有 bundle，避免反覆測試時干擾 Screen Recording 權限。本機 app bundle 會以一般 app 模式執行，因此編輯視窗可以用 `Cmd+Tab` 切換取得焦點。

## 專案結構

```text
src/EzshotApp/        AppKit 選單列 app、截圖流程、overlay、編輯 UI
src/EzshotCore/       文件與偏好設定模型
tests/EzshotCoreTests/ 輕量 executable test runner
scripts/run-app.sh    本機 build/sign/launch helper
```
