# 模型下載與協作
- Google EmbeddingGemma 2 text/vision 440M（約 388 MB），Apache-2.0，來源 Google LiteRT Hugging Face。媒體資料不傳送至模型網站。
- 使用 Google 官方 mediapipe_retrieval 0.4.1。ModelStore.allowDownloads=true，首次建立 AI 索引時由套件下載及驗證；沒有網路時先使用人工相簿功能。公開模型通常不需 Token。
- Flutter 第三方 offline_face_recognition 0.1.0 提供本機 MobileFaceNet 候選比對，套件已包含權重；套件 MIT 不代表訓練權重來源獨立確認。現階段僅測試用，公開二進位發行之前須查核權重來源授權、依賴與實機誤判。不要用搜尋結果作身分驗證。
- 遇 Hugging Face 登入、授權條款或 403：使用者本人至模型網頁完成授權，不分享密碼或 Token；回報錯誤碼與模型名稱即可。不要把 Token 加入 GitHub 或 APP。
- 官方模型 https://huggingface.co/google/embeddinggemma-2
- 套件 https://pub.dev/packages/mediapipe_retrieval
- 候選人臉套件 https://pub.dev/packages/offline_face_recognition
