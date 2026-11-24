# PIC_AI development rules
繁體中文介面。預設本機執行。不得上傳原始照片、GPS、家人姓名或照片向量到公開 repo。任何地點候選應保留來源，人工確認和原始 GPS 分開。不得宣稱未經測試的功能已完成。專用人臉辨識需先確認模型授權、同意與誤判處理；一般 EmbeddingGemma 2 不得當作身分辨識。所有修改附測試或說明驗證限制。

## Android 更新不可破壞資料
只開發 Android，目標小米 MIX 2 (Android 9+, arm64)。固定 applicationId com.yichincho.pic_ai；正式 APK 從第一版開始使用同一支永久 release key，禁止公開 debug APK 當安裝版。每次正式版本 versionCode 嚴格遞增，保留 pic_ai_v1.db 與人臉套件儲存位置；新增 schema 用非破壞性 migration。模型不相容只重建相應索引，保留人工標籤與地點。每次發布前實測覆蓋安裝及資料保留，不可要求卸載舊版。禁止提交金鑰或密碼。