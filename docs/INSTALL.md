# 安裝及操作 0.2 開發測試版
需 Flutter 3.44+（依套件實際要求）、Python 3、Git、Android Studio SDK。
```sh
git clone https://github.com/yichincho/PIC_AI.git
cd PIC_AI
python3 tools/bootstrap.py
flutter pub get
flutter analyze
flutter test
flutter run
```
Windows 可用 python 替代 python3。Android 9+（ARM64），以 MIX 2 為目標。Android 本機測試 APK：flutter build apk --debug，輸出 build/app/outputs/flutter-apk/app-debug.apk。正式 APK 需固定簽章，見 ANDROID_UPDATES.md。
## 操作
1. 授權照片，讀取相簿。首次按建立 AI 索引會下載約 388 MB 官方模型，需要網路。完成後本機搜尋。
2. 新增家人，取得本人同意後選 3–5 張每張只有同一人清晰臉孔的照片，按登錄參考人臉。
3. 按找家人候選，選家人，掃描後人工確認，選取正確結果再標記。候選不是身分證明。
4. 搜尋中文場景、家人標籤，長按照片查看 GPS/時間證據。選取多張可整批設定人工地點，不修改原始照片。
5. 清除本機索引與標籤會嘗試一併清除參考人臉資料。
## 注意
此版尚未真機驗證；第三方人臉模型權重授權尚未獨立確認，不建議正式分發。Android GPS 可能受權限限制。資料庫尚未額外加密。人臉候選須人工審查。Hugging Face 無需將 Token 交給任何人；見 MODELS.md。


正式版採覆蓋升級，不要解除安裝。見 [Android 更新規範](ANDROID_UPDATES.md)。debug APK 只供開發驗證，不是正式安裝版。
