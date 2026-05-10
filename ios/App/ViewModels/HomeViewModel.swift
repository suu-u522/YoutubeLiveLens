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

    var isNavigating: Bool {
        get { navigationTarget != nil }
        set { if !newValue { navigationTarget = nil } }
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

    init() {
        for entry in historyStore.entries where entry.status == .fetching {
            startListening(jobId: entry.id)
        }
    }

    // MARK: - 分析開始

    func analyzeFromInput() async {
        guard !isLoading else { return }
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "URLを入力してください"
            return
        }

        guard await checkIsLiveVideo(url: trimmed) else {
            errorMessage = "ライブ配信のアーカイブのみ対応しています"
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

    private func checkIsLiveVideo(url: String) async -> Bool {
        guard let videoId = extractVideoId(url),
              let pageURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else { return false }
        guard let (data, _) = try? await URLSession.shared.data(from: pageURL),
              let html = String(data: data, encoding: .utf8) else { return true } // 取得失敗時はサーバーに委ねる
        return html.contains("\"isLiveContent\":true")
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
                    totalMessages: job.totalMessages
                )
                if job.status != .fetching {
                    self.listeners[jobId]?.remove()
                    self.listeners[jobId] = nil
                }
            }
        }
        listeners[jobId] = reg
    }

    private func fetchJob(jobId: String) async -> AnalysisJob? {
        try? await service.fetchJob(jobId: jobId)
    }

    // MARK: - Helpers

    private func extractVideoId(_ url: String) -> String? {
        guard let vRange = url.range(of: "v=") else { return nil }
        let after = url[vRange.upperBound...]
        if let end = after.firstIndex(of: "&") {
            return String(after[after.startIndex..<end])
        }
        return String(after)
    }
}
