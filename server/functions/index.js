const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

// ============================================================
// ユーティリティ
// ============================================================

function extractVideoId(url) {
  const match = url.match(/[?&]v=([^&]+)/);
  return match ? match[1] : null;
}

async function fetchContinuationToken(videoId) {
  const res = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    },
    signal: AbortSignal.timeout(15000),
  });
  const html = await res.text();

  const contMarker = '"continuation":"';
  const contIdx = html.indexOf(contMarker);
  if (contIdx === -1) throw new Error("continuationトークンが見つかりません");
  const contStart = contIdx + contMarker.length;
  return html.substring(contStart, html.indexOf('"', contStart));
}

function parseDuration(iso) {
  const m = iso.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!m) return null;
  return (Number(m[1] ?? 0) * 3600) + (Number(m[2] ?? 0) * 60) + Number(m[3] ?? 0);
}

async function fetchVideoMetadata(videoId) {
  const apiKey = process.env.YOUTUBE_API_KEY;
  if (!apiKey) throw new Error("YOUTUBE_API_KEY が設定されていません");

  const url = `https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=${videoId}&key=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!res.ok) throw new Error(`YouTube API エラー: ${res.status}`);

  const data = await res.json();
  const item = data.items?.[0];
  if (!item) throw new Error("動画が見つかりません");

  return {
    title: item.snippet.title ?? null,
    publishDate: item.snippet.publishedAt?.slice(0, 10) ?? null,
    lengthSeconds: parseDuration(item.contentDetails.duration ?? ""),
  };
}

async function fetchChatPage(continuation) {
  const res = await fetch(
    "https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      },
      body: JSON.stringify({
        context: {
          client: { clientName: "WEB", clientVersion: "2.20240101" },
        },
        continuation,
      }),
      signal: AbortSignal.timeout(15000),
    }
  );
  const data = await res.json();

  const liveChatContinuation =
    data?.continuationContents?.liveChatContinuation ?? {};
  const actions = liveChatContinuation.actions ?? [];

  let nextToken = null;
  for (const c of liveChatContinuation.continuations ?? []) {
    nextToken = c.liveChatReplayContinuationData?.continuation ?? null;
    if (nextToken) break;
  }

  const messages = [];
  for (const action of actions) {
    const replay = action.replayChatItemAction ?? {};
    const offsetMs = parseInt(replay.videoOffsetTimeMsec ?? "0", 10);
    if (offsetMs === 0) continue;

    for (const inner of replay.actions ?? []) {
      const item = inner.addChatItemAction?.item ?? {};
      const renderer =
        item.liveChatTextMessageRenderer ??
        item.liveChatPaidMessageRenderer ??
        null;
      if (!renderer) continue;

      const runs = renderer.message?.runs ?? [];
      const text = runs.map((r) => r.text ?? "").join("").trim();
      if (text) messages.push({ text, offsetMs });
    }
  }

  return { messages, nextToken };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function flushMessages(jobRef, messages, bucketCounts) {
  const byBucket = {};
  for (const msg of messages) {
    const idx = Math.floor(msg.offsetMs / 60000);
    bucketCounts[idx] = (bucketCounts[idx] ?? 0) + 1;
    if (!byBucket[idx]) byBucket[idx] = [];
    byBucket[idx].push({ text: msg.text, offsetMs: msg.offsetMs });
  }

  const entries = Object.entries(byBucket);
  const BATCH_SIZE = 500;
  for (let i = 0; i < entries.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const [idx, msgs] of entries.slice(i, i + BATCH_SIZE)) {
      const ref = jobRef.collection("comments").doc(String(idx));
      batch.set(ref, {
        bucketIndex: Number(idx),
        startMs: Number(idx) * 60000,
        endMs: (Number(idx) + 1) * 60000,
        messages: FieldValue.arrayUnion(...msgs),
      }, { merge: true });
    }
    await batch.commit();
  }
}

function buildTimeline(bucketCounts) {
  if (Object.keys(bucketCounts).length === 0) return [];
  const maxBucket = Math.max(...Object.keys(bucketCounts).map(Number));
  const timeline = [];
  for (let i = 0; i <= maxBucket; i++) {
    timeline.push({
      bucketIndex: i,
      startMs: i * 60000,
      endMs: (i + 1) * 60000,
      count: bucketCounts[i] ?? 0,
    });
  }
  return timeline;
}

function getTop5(timeline) {
  return [...timeline]
    .sort((a, b) => b.count - a.count)
    .slice(0, 5)
    .map((t) => ({ startMs: t.startMs, endMs: t.endMs, count: t.count }));
}

// ============================================================
// analyzeChat — ジョブを作成してすぐ jobId を返す
// ============================================================

exports.analyzeChat = onCall(
  { timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    const { url, fcmToken } = request.data;

    if (!url || typeof url !== "string") {
      throw new HttpsError("invalid-argument", "url が必要です");
    }

    const videoId = extractVideoId(url);
    if (!videoId) {
      throw new HttpsError("invalid-argument", "有効なYouTube URLではありません");
    }

    const videoRef = db.collection("videoAnalysis").doc(videoId);
    let jobRef;

    const existingJobId = await db.runTransaction(async (tx) => {
      const snap = await tx.get(videoRef);
      if (snap.exists) {
        const { status, jobId: existingId } = snap.data();
        if (status === "fetching") {
          if (fcmToken) {
            const existingJobRef = db.collection("analysisJobs").doc(existingId);
            tx.update(existingJobRef, { fcmTokens: FieldValue.arrayUnion(fcmToken) });
          }
          return existingId;
        }
        if (status === "done") return existingId;
      }
      jobRef = db.collection("analysisJobs").doc();
      tx.set(videoRef, { jobId: jobRef.id, status: "fetching" });
      tx.set(jobRef, {
        videoId,
        url,
        fcmTokens: fcmToken ? [fcmToken] : [],
        status: "fetching",
        progress: 0,
        totalMessages: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
      return null;
    });

    if (existingJobId) return { jobId: existingJobId };
    return { jobId: jobRef.id };
  }
);

// ============================================================
// onJobCreated — ジョブ作成を検知してチャット取得を開始
// ============================================================

exports.onJobCreated = onDocumentCreated(
  { document: "analysisJobs/{jobId}", timeoutSeconds: 1800, memory: "512MiB" },
  async (event) => {
    const jobId = event.params.jobId;
    const data = event.data?.data();
    if (!data) return;

    const { videoId, fcmTokens = [] } = data;
    const jobRef = db.collection("analysisJobs").doc(jobId);
    const videoRef = db.collection("videoAnalysis").doc(videoId);

    try {
      // メタデータとcontinuationトークンを並行取得
      const [initialToken, { title, publishDate, lengthSeconds }] = await Promise.all([
        fetchContinuationToken(videoId),
        fetchVideoMetadata(videoId),
      ]);

      const thumbnailUrl = `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;
      const metaUpdate = { thumbnailUrl };
      if (title) metaUpdate.title = title;
      if (publishDate) metaUpdate.publishDate = publishDate;
      if (lengthSeconds !== null) metaUpdate.lengthSeconds = lengthSeconds;
      await jobRef.update(metaUpdate);

      // チャット全件取得
      let continuation = initialToken;
      let pageMessages = [];
      const bucketCounts = {};
      let page = 0;
      let totalMessages = 0;

      while (continuation) {
        const { messages, nextToken } = await fetchChatPage(continuation);
        pageMessages.push(...messages);
        totalMessages += messages.length;
        page++;

        if (page % 50 === 0) {
          await flushMessages(jobRef, pageMessages, bucketCounts);
          pageMessages = [];
          await jobRef.update({ progress: page, totalMessages });
        }

        continuation = nextToken;
        await sleep(500);
      }

      if (pageMessages.length > 0) {
        await flushMessages(jobRef, pageMessages, bucketCounts);
      }

      const timeline = buildTimeline(bucketCounts);
      const top5 = getTop5(timeline);
      const completedAt = FieldValue.serverTimestamp();

      await Promise.all([
        jobRef.update({ status: "done", progress: page, totalMessages, timeline, top5, completedAt }),
        videoRef.update({ status: "done", completedAt }),
      ]);

      // FCMプッシュ通知（全購読者に送信）
      const validTokens = fcmTokens.filter((t) => typeof t === "string" && t.length > 0);
      if (validTokens.length > 0) {
        const message = {
          notification: {
            title: "分析完了！",
            body: `${title ?? "動画"}の分析が完了しました`,
          },
          data: { jobId },
        };
        if (validTokens.length === 1) {
          await getMessaging().send({ ...message, token: validTokens[0] });
        } else {
          await getMessaging().sendEachForMulticast({ ...message, tokens: validTokens });
        }
      }
    } catch (err) {
      await Promise.all([
        jobRef.update({ status: "error", errorMessage: err.message ?? "不明なエラー" }),
        videoRef.update({ status: "error" }),
      ]);
    }
  }
);
