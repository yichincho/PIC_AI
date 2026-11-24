# Android MIX 2 與覆蓋升級
- Android 9 (API 28) 或更新、64 位元 arm64-v8a。MIX 2 Snapdragon 835 / 6–8 GB RAM，尚需真機確認 OS 及速度；不假設 GPU 支援。Google 模型為選配，先用家人候選及本機相簿，分批索引、可暫停。
- 固定 applicationId: com.yichincho.pic_ai。第一版就用長期保管的正式簽章；以後相同簽章及更高 versionCode 更新。
- 不解除安裝、不清除 APP 資料、不修改原始照片。SQLite 固定檔名 pic_ai_v1.db；schema 1→2 新增 app_meta，原表保持。人臉套件模板及模型快取需真機驗證更新後保留。
- 正式發行前需確認第三方模型權重授權，以及 MIX 2 真機安裝、斷網、掃描、更新測試。
## 金鑰設定（一次性）
由專案擁有者在可信電腦建立並備份專用 release keystore。不要在公開 repo、對話或日誌貼上私鑰/密碼。在 GitHub Settings > Secrets and variables > Actions 設定 PIC_AI_KEYSTORE_B64、PIC_AI_STORE_PASSWORD、PIC_AI_KEY_ALIAS、PIC_AI_KEY_PASSWORD；另設 PIC_AI_CERT_SHA256 為 keytool 查得的 SHA-256 指紋（移除冒號），供 CI 驗證。不得每次建置重新生成金鑰。
## 更新驗收
先安裝簽署舊版，設定測試家人與地點、建立索引。再用 adb install -r 新版 APK（相同簽章、更高 versionCode），確認標籤、參考模板、模型快取與原始照片保持；失敗不得發布。若模型變更，僅重建不相容向量，不清除人物及地點。

## 建置修正（JVM target）
- `tools/bootstrap.py` 會在產生的 `android/gradle.properties` 加入 `kotlin.jvm.target.validation.mode=warning`（可重複執行、不重複寫入），修正 tflite_flutter 的 Java 1.8 與 Kotlin 17 不一致而使 `flutter build apk --debug` 失敗的問題。
- 僅能透過 CI 驗證，尚未在本機或 MIX 2 真機實測。
- 同一腳本也會在 `android/build.gradle.kts` 將 `org.tensorflow:tensorflow-lite*` 固定為 2.16.1，避免 TFLite 2.11 的 namespace `org.tensorflow.lite` 重複而在新版 AGP 建置失敗；GPU delegate 與 MIX 2 真機執行尚未驗證。
- compileSdk 低於 34 的外掛（如 tflite_flutter）會在建置時被提高到 36；minSdk 28 與 targetSdk 不變，因此 MIX 2 (Android 9) 的安裝目標不受影響。
- 正式版（release）建置修正：bootstrap 會停用 lintVital（lint 工具本身崩潰）、加入 `tensorflow-lite-gpu-api:2.16.1` 以解決 R8 找不到 GpuDelegateFactory，並在 `proguard-rules.pro` 保留 TFLite 類別；僅經 CI 驗證，GPU delegate 在 MIX 2 真機上尚未測試。
