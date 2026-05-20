# Firebase Functions 仕様書

## 関数一覧

| 関数名 | 種別 | タイムアウト | メモリ |
|---|---|---|---|
| `analyzeChat` | Callable (HTTPS) | 60秒 | 256MiB |
| `onJobCreated` | Firestore onCreate トリガー | 540秒 | 256MiB（maxInstances: 5） |

---

## analyzeChat

ジョブドキュメントを作成して即座に `jobId` を返す。重い処理は `onJobCreated` に委譲。

### リクエスト

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `url` | string | ✅ | YouTube動画URL（`?v=` 形式） |
| `fcmToken` | string | - | 完了通知先のFCMデバイストークン（複数ユーザーが同一動画をリクエストした場合も全員に通知） |

### レスポンス

```json
{ "jobId": "abc123" }
```

分析中・完了済みの動画を再リクエストした場合も、既存の `jobId` を返す。

### 認証

Firebase Authentication が必須。未認証リクエストは `unauthenticated` エラーを返す。
iOSクライアントは匿名認証（Anonymous Auth）を使用。

### 処理フロー

```
1. 認証チェック（未認証 → HttpsError unauthenticated）
2. videoId をURLから抽出
3. YouTube Data API で liveStreamingDetails を確認
   - 存在しない → HttpsError（ライブ以外は分析不可）
4. YouTubeページHTMLから continuationトークンを取得
   - 取得できない → HttpsError（チャットリプレイなし）
5. videoAnalysis/{videoId} をトランザクションで確認
   - fetching → 既存 jobId を返却 + fcmToken を fcmTokens 配列に追加（ファンアウト通知）
   - done    → 既存 jobId を即返却
   - error / 未作成 → 新規ジョブを作成してロック
6. analysisJobs/{jobId} を作成（fcmTokens 配列を含む）
7. jobId を即返却 → onJobCreated トリガーが後続処理を担う
```

---

## onJobCreated

`analysisJobs/{jobId}` の作成を検知して、メタデータ取得・チャット全件取得・集計・通知を行う。

### 処理フロー

```
1. YouTubeページHTMLから continuationトークンを取得
2. YouTube Data API v3 でタイトル・配信日・配信時間を取得（並行実行）
3. メタデータを jobドキュメントに保存（title, thumbnailUrl, publishDate, lengthSeconds）
4. youtubei内部APIでチャットをページネーション全件取得（0.5秒間隔）
5. 50ページごとにFirestoreへflush・進捗更新
6. 1分バケツで集計 → timeline / top5 を生成
7. Firestoreに最終結果を保存（status: done）
8. FCMプッシュ通知（fcmTokens の全トークンに送信、本文にタイトルは含めない）
```

---

## Firestoreスキーマ

### videoAnalysis/{platform}_{videoId}

同一動画の重複分析を防ぐロック兼インデックス。キーは `youtube_xxx` のようにプラットフォームプレフィックスを付与する。

| フィールド | 型 | 説明 |
|---|---|---|
| `jobId` | string | 対応する analysisJobs のドキュメントID |
| `status` | string | `fetching` / `done` / `error` |
| `completedAt` | timestamp | 完了時刻（doneのみ） |

### analysisJobs/{jobId}

分析の進捗・結果を保持。iOSクライアントはこのドキュメントをリアルタイムリスナーで監視する。

| フィールド | 型 | 説明 |
|---|---|---|
| `platform` | string | 動画プラットフォーム（現在は `youtube` のみ） |
| `videoId` | string | 動画ID（プラットフォーム固有） |
| `url` | string | 元のリクエストURL |
| `fcmTokens` | array | FCMデバイストークンの配列（複数ユーザーが同一動画をリクエストした場合に蓄積） |
| `title` | string | 動画タイトル（onJobCreated で更新） |
| `thumbnailUrl` | string | サムネイルURL（`hqdefault.jpg`、videoIdから生成） |
| `publishDate` | string | 配信日（ISO 8601形式、例: `2024-01-15`） |
| `lengthSeconds` | number | 配信時間（秒） |
| `status` | string | `fetching` / `done` / `error` |
| `progress` | number | 取得済みページ数（50ページごとに更新） |
| `totalMessages` | number | 取得済みコメント数（50ページごとに更新） |
| `timeline` | array | 1分バケツの集計結果（下記参照） |
| `top5` | array | 盛り上がりTOP5シーン（下記参照） |
| `errorMessage` | string | エラー内容（errorのみ） |
| `createdAt` | timestamp | ジョブ作成時刻 |
| `completedAt` | timestamp | 完了時刻（doneのみ） |

#### timeline の要素

バケツ単位は1分（60,000ms）。iOSクライアント側で5分・10分に集約して表示。

```json
{
  "bucketIndex": 3,
  "startMs": 180000,
  "endMs": 240000,
  "count": 42
}
```

#### top5 の要素

```json
{
  "startMs": 900000,
  "endMs": 1200000,
  "count": 42
}
```

### analysisJobs/{jobId}/comments/{bucketIndex}

コメント本文をバケツ単位で保存するサブコレクション。キーワード検索・コメント一覧表示に使用。

| フィールド | 型 | 説明 |
|---|---|---|
| `bucketIndex` | number | バケツ番号（0始まり） |
| `startMs` | number | バケツ開始時刻（ms） |
| `endMs` | number | バケツ終了時刻（ms） |
| `messages` | array | `{ text: string, offsetMs: number }` の配列 |

キーワード検索はiOS側で全ドキュメントを取得してクライアントフィルタリング。
グラフの山をタップした際は該当 `bucketIndex` のドキュメント1件だけ取得してコメント一覧を表示。

---

## YouTube内部API

公式ドキュメント非公開のInnertubeエンドポイントを使用。APIキー不要。

### チャット取得エンドポイント

```
POST https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay
```

- 1ページあたり約30〜60件
- レスポンス内の `liveChatReplayContinuationData.continuation` が次ページトークン
- トークンが返ってこなければ最終ページ
- `videoOffsetTimeMsec === "0"` のコメントは待機室コメントのため除外

### レートリミット

公式仕様は非公開。GCPの固定IPからの集中リクエストで429 / IPブロックのリスクあり。
現在は0.5秒間隔で運用。ユーザー数増加時はCloud NAT + 複数IPの構成を検討。

---

## YouTube Data API v3

動画メタデータ（タイトル・配信日・配信時間）の取得に使用。

- 環境変数 `YOUTUBE_API_KEY` が必要
- ライブチェック: `part=liveStreamingDetails` のみで事前確認（analyzeChat 内）
- メタデータ取得: `part=snippet,contentDetails`（onJobCreated 内）
- `liveStreamingDetails` が存在しない場合は analyzeChat で HttpsError を返す
- `publishedAt` の先頭10文字（`YYYY-MM-DD`）を `publishDate` として保存
- `contentDetails.duration`（ISO 8601形式）を秒数に変換して `lengthSeconds` として保存

---

## ローカル開発

```bash
cd server
firebase emulators:start --only functions,firestore
```

| エミュレーター | URL |
|---|---|
| Functions | http://127.0.0.1:5001 |
| Firestore | http://127.0.0.1:8080 |
| UI | http://127.0.0.1:4000 |

環境変数は `functions/.env` に記載（`.gitignore` 対象）。
