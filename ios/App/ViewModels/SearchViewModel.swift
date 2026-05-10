import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword = ""
    @Published var allComments: [Comment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let jobId: String
    private let service = FirebaseService.shared

    init(jobId: String) {
        self.jobId = jobId
    }

    var filteredComments: [Comment] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allComments }
        return allComments.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    func loadIfNeeded() async {
        guard allComments.isEmpty else { return }
        isLoading = true
        do {
            allComments = try await service.fetchAllComments(jobId: jobId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
