# PIC_AI｜私人家庭照片搜尋

本機照片索引、EmbeddingGemma 2 語意搜尋、家人標籤與拍攝地點回溯。目標平台：iOS / Android（Flutter）。目前為 0.1 開發版，不是已發布的手機安裝包。

## 隱私
照片、索引與標籤僅存裝置內；首次下載模型需要網路。不上傳相簿、不修改原始照片。家人標籤由使用者確認；自動人臉身分辨識尚未驗證，不可把語意相似度當作人臉辨識。

## 位置
原始 GPS、鄰近時間照片的 GPS 候選、人工確認地點分開保存。沒有 GPS 不代表可以還原定位；候選只供參考。不要把私人照片、向量、家人姓名提交到此公開倉庫。

模型：[EmbeddingGemma 2](https://huggingface.co/google/embeddinggemma-2)；[Google Universal Embedder](https://developers.google.com/edge/mediapipe/solutions/retrieval/universal_embedder)。
