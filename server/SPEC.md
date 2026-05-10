# Firebase Functions 仕様書

## analyzeChat

YouTube過去ライブ配信のチャットを全件取得・集計するCallable Function。

### リクエスト

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `url` | string | ✅ | YouTube動画URL（`?v=` 形式） |
| `fcmToken` | string | - | 完了通知先のFCMデバイストークン |

### レスポンス

```json
{ "jobId": "abc123" }
```

分析中・完了済みの動画を再リクエストした場合も、既存の `jobId` を返す（後述）。

### 処理フロー

```
1. videoId をURLから抽出
2. videoAnalysis/{videoId} をトランザクションで確認
   - fetching / done → 既存 jobId を即返却（重複実行防止）
   - error / 未作成  → 新規ジョブを作成してロック
3. YouTubeページHTMLから continuationトークンを取得
4. youtubei内部APIでチャットをページネーション全件取得（0.5秒間隔）
5. 5分バケツで集計 → timeline / top5 を生成
6. Firestoreに結果を保存
7. FCMプッシュ通知（fcmToken があれば）
```

### タイムアウト・メモリ

| 項目 | 値 |
|---|---|
| タイムアウト | 1800秒（30分） |
| メモリ | 512MB |

8時間配信の全件取得（約500〜1000ページ、0.5秒間隔）でも約10分以内に完了する想定。

---

## Firestoreスキーマ

### videoAnalysis/{videoId}

同一動画の重複分析を防ぐロック兼インデックス。

| フィールド | 型 | 説明 |
|---|---|---|
| `jobId` | string | 対応する analysisJobs のドキュメントID |
| `status` | string | `fetching` / `done` / `error` |
| `completedAt` | timestamp | 完了時刻（doneのみ） |

### analysisJobs/{jobId}

分析の進捗・結果を保持。iOSクライアントはこのドキュメントをリアルタイムリスナーで監視する。

| フィールド | 型 | 説明 |
|---|---|---|
| `videoId` | string | YouTube動画ID |
| `url` | string | 元のリクエストURL |
| `title` | string | 動画タイトル（HTMLから取得、失敗時は未セット） |
| `thumbnailUrl` | string | サムネイルURL（`hqdefault.jpg`、videoIdから生成） |
| `publishDate` | string | 配信日（ISO 8601形式、例: `2024-01-15`。HTMLから取得できない場合は未セット） |
| `lengthSeconds` | number | 配信時間（秒、HTMLから取得できない場合は未セット） |
| `status` | string | `fetching` / `done` / `error` |
| `progress` | number | 取得済みページ数（50ページごとに更新） |
| `totalMessages` | number | 取得済みコメント数（50ページごとに更新） |
| `timeline` | array | 5分バケツの集計結果（下記参照） |
| `top5` | array | 盛り上がりTOP5シーン（下記参照） |
| `errorMessage` | string | エラー内容（errorのみ） |
| `createdAt` | timestamp | ジョブ作成時刻 |
| `completedAt` | timestamp | 完了時刻（doneのみ） |

#### timeline の要素

```json
{
  "bucketIndex": 3,
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
グラフの山をタップした際は該当 `bucketIndex` のドキュメント1件だけ取得してコメント一覧を表示できる。

#### top5 の要素

```json
{
  "startMs": 900000,
  "endMs": 1200000,
  "count": 42
}
```

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
