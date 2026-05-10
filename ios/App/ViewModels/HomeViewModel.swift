import Foundation
import FirebaseFirestore

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showURLSheet = false
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

        isLoading = true
        errorMessage = nil

        do {
            let jobId = try await service.analyzeChat(url: trimmed, fcmToken: fcm.fcmToken)
            let placeholder = AnalysisJob(id: jobId, videoId: extractVideoId(trimmed) ?? "", url: trimmed)
            historyStore.add(job: placeholder)
            startListening(jobId: jobId)

            showURLSheet = false
            urlText = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - カードタップ

    func tapHistory(_ entry: HistoryEntry) {
        switch entry.status {
        case .done:
            // Firestoreから最新のジョブデータを取得してResultViewへ
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
