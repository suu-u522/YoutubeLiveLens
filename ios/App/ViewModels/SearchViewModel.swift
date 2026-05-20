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
        #if DEBUG
        allComments = Self.dummyComments
        keyword = "草"
        return
        #endif
        isLoading = true
        do {
            allComments = try await service.fetchAllComments(jobId: jobId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    #if DEBUG
    private static let dummyComments: [Comment] = [
        Comment(text: "草", offsetMs: 3_720_000),
        Comment(text: "ここ好きすぎる", offsetMs: 3_780_000),
        Comment(text: "草生えた", offsetMs: 4_200_000),
        Comment(text: "wwwww", offsetMs: 4_260_000),
        Comment(text: "神回すぎる", offsetMs: 4_320_000),
        Comment(text: "草", offsetMs: 5_100_000),
        Comment(text: "ここは草", offsetMs: 5_160_000),
        Comment(text: "草草草", offsetMs: 5_400_000),
        Comment(text: "爆笑した", offsetMs: 6_000_000),
        Comment(text: "草生える", offsetMs: 6_060_000),
    ]
    #endif
}
