# YoutubeLiveLens - プロジェクトコンテキスト

## アプリ概要

YouTubeの過去ライブ配信URLを入力して、チャットコメントの量や盛り上がりを分析・検索できるiOSアプリ。

---

## ターゲットユーザー

- YouTubeライブのライトなファン
- TikTok向けに切り抜き動画を作りたい人
- 「この配信のどこが一番盛り上がったか」をスマホでサクッと知りたい人

**ポジショニング**
- Chrome拡張（YCS、Highlight Analyzerなど）は既存競合あり → PC・本気ユーザー向け
- iOSアプリはほぼ空白地帯 → ライトユーザー向けとして差別化

---

## コア機能

1. URLを入力する
2. コメント量の時系列グラフを表示
3. グラフの山をタップ → YouTubeアプリでその時間から再生
4. キーワード検索
5. 盛り上がりTOP5シーンを自動表示

**対象：ライブチャットリプレイ（通常コメントではない）**

---

## マネタイズ

| プラン | 内容 |
|--------|------|
| 無料 | 1日1本まで分析可能 |
| 2本目以降 | リワード広告（約30秒）を見て1回追加 |
| Pro 買い切り600円 | 広告なし・無制限 |

---

## 技術スタック

### iOSアプリ
- Swift / SwiftUI
- Firebase SDK（Firestore, FCM）

### バックエンド
- Firebase Functions（Node.js）
- Firestore（進捗・結果保存）
- FCM（完了プッシュ通知）

### チャット取得方式
- YouTube Data API v3は**アーカイブに非対応**のため不使用
- **YouTubeの内部API**（`youtubei/v1/live_chat/get_live_chat_replay`）を使用
- APIキー不要・ページネーションで全件取得

---

## アーキテクチャ

```
[iOS App]
　└ URLを入力
　└ Firebase Functionsにリクエスト
　└ Firestoreをリアルタイム監視（進捗表示）
　└ FCMで完了通知を受信
　└ 結果（グラフ・検索）を表示

[Firebase Functions]
　└ URLからvideoIdを抽出
　└ YouTubeページからcontinuationトークンを取得
　└ 内部APIで全件取得（ページネーション）
　└ 待機室コメント（offsetMs=0）を除外
　└ 5分単位で集計
　└ Firestoreに結果を保存
　└ FCMでプッシュ通知
```

---

## Firebase Functionsのタイムアウト設定

```javascript
exports.analyzeChat = functions
  .runWith({ timeoutSeconds: 1800 }) // 最大30分
  .https.onCall(async (data) => { ... })
```

HTTP/Callable Functionsの上限は3600秒（60分）なので、8時間配信の全件取得も問題なし。

---

## 技術検証済みの内容

### チャット取得フロー（Python検証済み）

```python
# 1. YouTubeページからcontinuationトークンを取得
url = f"https://www.youtube.com/watch?v={video_id}"
# HTMLから `"continuation":"xxxxx"` を抽出

# 2. 内部APIでチャット取得
api_url = "https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay"
payload = {
    "context": {
        "client": {
            "clientName": "WEB",
            "clientVersion": "2.20240101"
        }
    },
    "continuation": continuation_token
}

# 3. レスポンス構造
# continuationContents.liveChatContinuation.actions[] に各メッセージ
# action.replayChatItemAction.videoOffsetTimeMsec → タイムスタンプ（ms）
# action.replayChatItemAction.actions[].addChatItemAction.item
#   .liveChatTextMessageRenderer.message.runs[].text → コメント本文

# 4. 次ページトークン
# continuationContents.liveChatContinuation.continuations[]
#   .liveChatReplayContinuationData.continuation
```

### 重要な仕様

- **待機室コメント**：`videoOffsetTimeMsec = "0"` のものは配信前コメントなので除外
- **1ページあたり**：約30〜60件（ページによってバラつきあり）
- **取得間隔**：0.3秒スリープ推奨（サーバー負荷軽減）

### 検証済みURL

```
https://www.youtube.com/watch?v=IrbY2vcec64
タイトル：【アーマード・コアVI】#2週目 続！シリーズ完全初見プレイッ！！【にじさんじ/鈴原るる】
配信時間：約8時間半（2026-05-09 13:30〜22:06 UTC）
```

---

## リポジトリ構成

```
GitHub（どちらもPrivate）
　├ YoutubeLiveLens-ios   → Xcodeプロジェクト（.gitignore: Swift）
　└ YoutubeLiveLens-server → Firebase Functions（.gitignore: Node）
```

---

## 次のステップ

- [ ] GitHubリポジトリ2つ作成（YoutubeLiveLens-ios / YoutubeLiveLens-server）
- [ ] Firebase プロジェクト作成
- [ ] Firebase Functions の初期実装（チャット取得API）
- [ ] Xcode プロジェクト作成
- [ ] iOS側のUI実装（URL入力 → 進捗画面 → グラフ表示）
