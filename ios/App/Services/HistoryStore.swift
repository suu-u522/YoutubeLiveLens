import Foundation

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let key = "analysisHistory"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        load()
    }

    func add(job: AnalysisJob) {
        let entry = HistoryEntry(
            id: job.id,
            videoId: job.videoId,
            title: job.title,
            thumbnailUrl: job.thumbnailUrl,
            publishDate: job.publishDate,
            createdAt: Date(),
            status: job.status,
            totalMessages: job.totalMessages
        )
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        save()
    }

    func update(jobId: String, title: String?, thumbnailUrl: String?, publishDate: String?, status: JobStatus, totalMessages: Int, progress: Int? = nil, errorMessage: String? = nil) {
        guard let idx = entries.firstIndex(where: { $0.id == jobId }) else { return }
        entries[idx].title = title ?? entries[idx].title
        entries[idx].thumbnailUrl = thumbnailUrl ?? entries[idx].thumbnailUrl
        entries[idx].publishDate = publishDate ?? entries[idx].publishDate
        entries[idx].status = status
        entries[idx].totalMessages = totalMessages
        if let progress { entries[idx].progress = progress }
        if let errorMessage { entries[idx].errorMessage = errorMessage }
        save()
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? decoder.decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    #if DEBUG
    func loadDummyEntries() {
        entries = [
            HistoryEntry(
                id: "dummy1",
                videoId: "dummy1",
                title: "【年末大感謝祭】2024 総決算ライブ ～ありがとう10万人！～",
                thumbnailUrl: nil,
                publishDate: "2024-12-31",
                createdAt: Date().addingTimeInterval(-3600),
                status: .done,
                totalMessages: 142830
            ),
            HistoryEntry(
                id: "dummy2",
                videoId: "dummy2",
                title: "【ドラクエ3リメイク】初見プレイ！勇者と仲間たちと世界を救う旅へ【後編】",
                thumbnailUrl: nil,
                publishDate: "2024-11-15",
                createdAt: Date().addingTimeInterval(-86400),
                status: .done,
                totalMessages: 87654
            ),
            HistoryEntry(
                id: "dummy3",
                videoId: "dummy3",
                title: "【スト6】シーズン2新キャラ解禁！ランクマ深夜まで潜ります",
                thumbnailUrl: nil,
                publishDate: "2024-10-03",
                createdAt: Date().addingTimeInterval(-172800),
                status: .done,
                totalMessages: 53201
            ),
        ]
    }
    #endif

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
