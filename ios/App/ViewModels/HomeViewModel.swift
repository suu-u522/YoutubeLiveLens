import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showURLSheet = false
    @Published var navigationJobId: String?
    var isNavigating: Bool {
        get { navigationJobId != nil }
        set { if !newValue { navigationJobId = nil } }
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
            navigationJobId = jobId
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
            navigationJobId = entry.id
        case .fetching:
            navigationJobId = entry.id
        case .error:
            navigationJobId = entry.id
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
