# YoutubeLiveLens - Server

YoutubeLiveLens iOSアプリのバックエンド（Firebase Functions）。

## セットアップ

```sh
npm install -g firebase-tools
firebase login
firebase use youtubelivelens
cd functions && npm install
```

## ローカル開発

```sh
firebase emulators:start --only functions,firestore
```

curlで動作確認：

```sh
curl -X POST http://127.0.0.1:5001/youtubelivelens/us-central1/analyzeChat \
  -H "Content-Type: application/json" \
  -d '{"data": {"url": "https://www.youtube.com/watch?v=VIDEO_ID"}}'
```

## デプロイ

```sh
firebase deploy --only functions
```

## ドキュメント

FirestoreスキーマとAPI仕様は [SPEC.md](SPEC.md) を参照。
