import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showURLSheet = false
    @Published var navigateTo: NavigationTarget?

    enum NavigationTarget: Identifiable, Equatable {
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
    }

    let historyStore = HistoryStore.shared
    private let service = FirebaseService.shared
    private let fcm = FCMService.shared

    // MARK: - URL入力シートからの分析開始

    func analyzeFromInput() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "URLを入力してください"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let jobId = try await service.analyzeChat(url: trimmed, fcmToken: fcm.fcmToken)

            // 新規ジョブとして最低限の情報でhistoryに追加（後でリアルタイム更新される）
            let placeholder = AnalysisJob(id: jobId, videoId: extractVideoId(trimmed) ?? "", url: trimmed)
            historyStore.add(job: placeholder)

            showURLSheet = false
            urlText = ""
            navigateTo = .progress(jobId: jobId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - 履歴カードタップ

    func tapHistory(_ entry: HistoryEntry) {
        switch entry.status {
        case .done:
            // タイトル等が揃っていれば結果画面へ（AnalysisJobを復元）
            navigateTo = .progress(jobId: entry.id)
        case .fetching:
            navigateTo = .progress(jobId: entry.id)
        case .error:
            navigateTo = .progress(jobId: entry.id)
        }
    }

    // MARK: - Helpers

    private func extractVideoId(_ url: String) -> String? {
        let pattern = #"[?&]v=([^&]+)"#
        guard let range = url.range(of: pattern, options: .regularExpression),
              let vRange = url.range(of: "v=") else { return nil }
        let after = url[vRange.upperBound...]
        if let end = after.firstIndex(of: "&") {
            return String(after[after.startIndex..<end])
        }
        return String(after)
    }
}
