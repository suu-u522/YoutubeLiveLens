import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

final class FirebaseService: ObservableObject {
    static let shared = FirebaseService()

    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - analyzeChat Callable Function の呼び出し

    func analyzeChat(url: String, fcmToken: String?) async throws -> String {
        if Auth.auth().currentUser == nil {
            try await Auth.auth().signInAnonymously()
        }

        var data: [String: Any] = ["url": url]
        if let token = fcmToken {
            data["fcmToken"] = token
        }
        let result = try await functions.httpsCallable("analyzeChat").call(data)
        guard let dict = result.data as? [String: Any],
              let jobId = dict["jobId"] as? String else {
            throw ServiceError.invalidResponse
        }
        return jobId
    }

    // MARK: - analysisJobs のリアルタイム監視

    func listenJob(jobId: String, onChange: @escaping (AnalysisJob) -> Void) -> ListenerRegistration {
        db.collection("analysisJobs").document(jobId)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data(),
                      let job = Self.decodeJob(id: jobId, data: data) else { return }
                onChange(job)
            }
    }

    // MARK: - ジョブ1件取得

    func fetchJob(jobId: String) async throws -> AnalysisJob {
        let snap = try await db.collection("analysisJobs").document(jobId).getDocument()
        guard let data = snap.data(),
              let job = Self.decodeJob(id: jobId, data: data) else {
            throw ServiceError.notFound
        }
        return job
    }

    // MARK: - コメント取得（バケツ単位）

    func fetchCommentBucket(jobId: String, bucketIndex: Int) async throws -> CommentBucket {
        let snap = try await db
            .collection("analysisJobs").document(jobId)
            .collection("comments").document(String(bucketIndex))
            .getDocument()
        guard let data = snap.data() else { throw ServiceError.notFound }
        return try Firestore.Decoder().decode(CommentBucket.self, from: data)
    }

    // MARK: - キーワード検索（全バケツをクライアント側でフィルタ）

    func fetchAllComments(jobId: String) async throws -> [Comment] {
        let snaps = try await db
            .collection("analysisJobs").document(jobId)
            .collection("comments")
            .getDocuments()
        return snaps.documents.compactMap { doc -> [Comment]? in
            guard let bucket = try? Firestore.Decoder().decode(CommentBucket.self, from: doc.data()) else { return nil }
            return bucket.messages
        }.flatMap { $0 }.sorted { $0.offsetMs < $1.offsetMs }
    }

    // MARK: - デコード

    private static func decodeJob(id: String, data: [String: Any]) -> AnalysisJob? {
        guard let videoId = data["videoId"] as? String,
              let url = data["url"] as? String,
              let statusRaw = data["status"] as? String,
              let status = JobStatus(rawValue: statusRaw) else { return nil }

        var job = AnalysisJob(
            id: id,
            videoId: videoId,
            url: url,
            status: status,
            progress: data["progress"] as? Int ?? 0,
            totalMessages: data["totalMessages"] as? Int ?? 0
        )
        job.title = data["title"] as? String
        job.thumbnailUrl = data["thumbnailUrl"] as? String
        job.publishDate = data["publishDate"] as? String
        job.lengthSeconds = data["lengthSeconds"] as? Int
        job.errorMessage = data["errorMessage"] as? String

        if let rawTimeline = data["timeline"] as? [[String: Any]] {
            job.timeline = rawTimeline.compactMap { t in
                guard let idx = t["bucketIndex"] as? Int,
                      let start = t["startMs"] as? Int,
                      let end = t["endMs"] as? Int,
                      let count = t["count"] as? Int else { return nil }
                return TimelineBucket(bucketIndex: idx, startMs: start, endMs: end, count: count)
            }
        }

        if let rawTop5 = data["top5"] as? [[String: Any]] {
            job.top5 = rawTop5.compactMap { t in
                guard let start = t["startMs"] as? Int,
                      let end = t["endMs"] as? Int,
                      let count = t["count"] as? Int else { return nil }
                return Top5Scene(startMs: start, endMs: end, count: count)
            }
        }

        return job
    }
}

enum ServiceError: LocalizedError {
    case invalidResponse
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "サーバーから無効なレスポンスが返されました"
        case .notFound: return "データが見つかりませんでした"
        }
    }
}
