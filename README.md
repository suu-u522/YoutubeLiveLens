# LiveLens

YouTubeの過去ライブ配信URLを入力して、チャットコメントの量や盛り上がりを分析できるiOSアプリ。

## 機能

1. URLを入力する
2. コメント量の時系列グラフを表示（1分 / 5分 / 10分単位で切り替え可）
3. 盛り上がりTOP5シーンを自動表示
4. グラフの山をタップ → YouTubeアプリでその時間から再生

> 対象はライブチャットリプレイ（通常コメントではない）

## ターゲットユーザー

- YouTubeライブのライトなファン
- TikTok向けに切り抜き動画を作りたい人
- 「この配信のどこが一番盛り上がったか」をスマホでサクッと知りたい人

既存のChrome拡張（YCS、Highlight Analyzerなど）はPC・本気ユーザー向けであり、iOSアプリはほぼ空白地帯のため、ライトユーザー向けとして差別化。

## マネタイズ

| プラン | 内容 |
|--------|------|
| 無料 | 3本まで分析可能 |
| 4本目以降 | リワード広告（約30秒）を視聴して追加 |

## 技術スタック

### iOSアプリ
- Swift / SwiftUI
- Firebase SDK（Firestore, Messaging, Functions）
- Google Mobile Ads SDK（リワード広告）
- XcodeGen

### バックエンド
- Firebase Functions（Node.js）
- Firestore（進捗・結果保存）
- FCM（完了プッシュ通知）

### チャット取得方式

YouTube Data API v3はアーカイブに非対応のため、YouTubeの内部API（`youtubei/v1/live_chat/get_live_chat_replay`）を使用。APIキー不要でページネーションにより全件取得。

## アーキテクチャ

```
[iOS App]
　└ URLを入力
　└ Firebase Functionsにリクエスト（jobId を即時返却）
　└ Firestoreをリアルタイム監視（進捗表示）
　└ FCMで完了通知を受信
　└ 結果（グラフ・TOP5）を表示

[Firebase Functions]
　└ analyzeChat（Callable）: jobIdを即時返却してFirestoreにjobを作成
　└ onJobCreated（Firestoreトリガー）: チャット取得・集計・結果保存・FCM通知
　　　├ YouTubeページからcontinuationトークンを取得
　　　├ 内部APIで全件取得（ページネーション）
　　　├ 待機室コメント（offsetMs=0）を除外
　　　├ 1分単位で集計（クライアント側で5分/10分に集約）
　　　└ Firestoreに結果を保存 → FCMでプッシュ通知
```

## リポジトリ構成

```
LiveLens（Private）
　├ ios/    → Xcodeプロジェクト（Swift / SwiftUI）
　└ server/ → Firebase Functions（Node.js）
```
