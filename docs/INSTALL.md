# 安裝及操作（0.1 開發版，尚未完成真機驗證）

## 開發安裝
需要近期 Flutter stable（包含支援 MediaPipe retrieval 0.4.1 的 Dart SDK）、Python 3、Git。Android 需 Android Studio SDK；iOS 需 Mac、Xcode、Apple 簽署帳號。

    git clone https://github.com/yichincho/PIC_AI.git
    cd PIC_AI
    python3 tools/bootstrap.py
    flutter pub get
    flutter analyze
    flutter test
    flutter run

Windows 可用 python 代替 python3。Android 也可執行 flutter build apk --debug，產物位於 build/app/outputs/flutter-apk/app-debug.apk。iOS 必須在 Xcode 設定 Signing & Capabilities、唯一 bundle ID、開發團隊，使用 flutter run 或經 Archive/TestFlight 安裝。未簽署 iOS 產物不能直接安裝。

## 操作
1. 授權照片；若只授權部分，僅掃描可存取照片。
2. 按讀取照片查看 GPS 資訊。建立 AI 索引會使用 Google 官方 Flutter 套件下載並初始化 440M 模型（首次需網路及足夠空間），以 512 縮圖建立本機 SQLite 向量。
3. 搜尋中文場景，依相似度排序。結果僅為內容相似，非地點證明。
4. 新增家人名稱；點選照片後人工標記。家人標籤不是自動人臉辨識。
5. 長按照片查看原始 GPS、人工地點與前後 30 分鐘的其他 GPS 照片線索。沒有 GPS 或讀取受限時，不可宣稱還原了原始位置。
6. 可清除本機索引及標籤，不刪除原照片。

## 已知限制
尚未執行 Flutter build 或真機測試；自動人臉辨識、多人交集、OCR 地點候選、地圖及簽署發行仍待實作或驗證。iCloud 照片可能需要下載；Android GPS 可能因權限受限。相簿資料庫尚未額外加密，避免備份或分享資料庫。語意模型分數不是身分辨識準確率。
