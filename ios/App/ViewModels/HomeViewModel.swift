import Foundation
import FirebaseFirestore

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showURLSheet = false
    @Published var showLimitAlert = false
    @Published var navigationTarget: NavigationTarget?

    enum NavigationTarget: Identifiable, Hashable {
        case progress(jobId: String)
        case result(job: AnalysisJob)

        var id: String {
            switch self {
            case .progress(let jobId): return "progress-\(jobId)"
            case .result(let job): return "result-\(job.id)"
            }
        }

        static func == (lhs: NavigationTarget, rhs: NavigationTarget) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    // MARK: - 制限ロジック

    private static let freeLimit = 3
    private static let rewardedKey = "rewardedRemaining"

    var canAnalyze: Bool {
        let done = historyStore.entries.filter { $0.status == .done }.count
        return done < Self.freeLimit || rewardedRemaining > 0
    }

    var rewardedRemaining: Int {
        UserDefaults.standard.integer(forKey: Self.rewardedKey)
    }

    func grantRewardedAnalysis() {
        UserDefaults.standard.set(rewardedRemaining + 1, forKey: Self.rewardedKey)
    }

    private func consumeRewardedIfNeeded() {
        let done = historyStore.entries.filter { $0.status == .done }.count
        if done >= Self.freeLimit && rewardedRemaining > 0 {
            UserDefaults.standard.set(rewardedRemaining - 1, forKey: Self.rewardedKey)
        }
    }

    let historyStore = HistoryStore.shared
    private let service = FirebaseService.shared
    private let fcm = FCMService.shared
    private var listeners: [String: ListenerRegistration] = [:]
    private var jobCache: [String: AnalysisJob] = [:]

    init() {
        for entry in historyStore.entries where entry.status == .fetching {
            startListening(jobId: entry.id)
        }
        #if DEBUG
        navigationTarget = .result(job: Self.dummyJob)
        #endif
        NotificationCenter.default.addObserver(
            forName: .incomingAnalysisURL,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            self?.handleIncomingURL(url)
        }
    }

    // MARK: - 外部URLからの起動

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "livelens",
              url.host == "analyze",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let youtubeURL = components.queryItems?.first(where: { $0.name == "url" })?.value else { return }
        urlText = youtubeURL
        showURLSheet = true
    }

    // MARK: - 分析開始

    func analyzeFromInput() async {
        guard !isLoading else { return }
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "URLを入力してください"
            return
        }

        guard canAnalyze else {
            showLimitAlert = true
            return
        }

        if let result = await callAnalysisAPI(url: trimmed) {
            commitToHistory(jobId: result.jobId, url: trimmed, videoId: result.videoId)
        }
    }

// API呼び出しのみ（広告表示と並行して実行）
    func callAnalysisAPI(url: String) async -> (jobId: String, videoId: String)? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let jobId = try await service.analyzeChat(url: url, fcmToken: fcm.fcmToken)
            return (jobId, extractVideoId(url) ?? "")
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // 履歴保存・リスナー開始（広告報酬獲得後に呼ぶ）
    func commitToHistory(jobId: String, url: String, videoId: String) {
        consumeRewardedIfNeeded()
        let placeholder = AnalysisJob(id: jobId, videoId: videoId, url: url)
        historyStore.add(job: placeholder)
        startListening(jobId: jobId)
        showURLSheet = false
        urlText = ""
    }

    // MARK: - カードタップ

    func tapHistory(_ entry: HistoryEntry) {
        switch entry.status {
        case .done:
            Task {
                if let job = await fetchJob(jobId: entry.id) {
                    navigationTarget = .result(job: job)
                }
            }
        case .fetching, .error:
            navigationTarget = .progress(jobId: entry.id)
        }
    }

    // MARK: - Firestoreリアルタイム監視

    private func startListening(jobId: String) {
        guard listeners[jobId] == nil else { return }
        let reg = service.listenJob(jobId: jobId) { [weak self] job in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.historyStore.update(
                    jobId: job.id,
                    title: job.title,
                    thumbnailUrl: job.thumbnailUrl,
                    publishDate: job.publishDate,
                    status: job.status,
                    totalMessages: job.totalMessages,
                    progress: job.progress,
                    errorMessage: job.errorMessage
                )
                if job.status != .fetching {
                    if job.status == .done { self.jobCache[jobId] = job }
                    self.listeners[jobId]?.remove()
                    self.listeners[jobId] = nil
                }
            }
        }
        listeners[jobId] = reg
    }

    func fetchJob(jobId: String) async -> AnalysisJob? {
        if let cached = jobCache[jobId] { return cached }
        let job = try? await service.fetchJob(jobId: jobId)
        if let job { jobCache[jobId] = job }
        return job
    }

    // MARK: - Helpers

    #if DEBUG
    static let dummyJob: AnalysisJob = {
        let counts = [12, 18, 25, 30, 22, 45, 60, 88, 120, 95, 74, 55, 62, 78, 110, 145, 200, 180, 135, 98, 76, 54, 42, 38, 50, 65, 80, 110, 95, 72]
        let timeline = counts.enumerated().map { i, count in
            TimelineBucket(bucketIndex: i, startMs: i * 60000, endMs: (i + 1) * 60000, count: count)
        }
        let top5 = [
            Top5Scene(startMs: 960000,  endMs: 1020000, count: 200),
            Top5Scene(startMs: 900000,  endMs:  960000, count: 180),
            Top5Scene(startMs: 840000,  endMs:  900000, count: 145),
            Top5Scene(startMs: 780000,  endMs:  840000, count: 135),
            Top5Scene(startMs: 1020000, endMs: 1080000, count: 120),
        ]
        var job = AnalysisJob(
            id: "dummyResult",
            platform: .youtube,
            videoId: "dummyResult",
            url: "https://www.youtube.com/watch?v=dummyResult",
            status: .done,
            totalMessages: 54321
        )
        job.title = "【8時間耐久】年末大感謝祭ライブ2024 ～みんなありがとう！～"
        job.publishDate = "2024-12-31"
        job.lengthSeconds = 28800
        job.timeline = timeline
        job.top5 = top5
        return job
    }()
    #endif

    private func extractVideoId(_ url: String) -> String? {
        guard let vRange = url.range(of: "v=") else { return nil }
        let after = url[vRange.upperBound...]
        if let end = after.firstIndex(of: "&") {
            return String(after[after.startIndex..<end])
        }
        return String(after)
    }
}
