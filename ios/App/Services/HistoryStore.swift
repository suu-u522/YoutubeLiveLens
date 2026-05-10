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
            createdAt: Date(),
            status: job.status,
            totalMessages: job.totalMessages
        )
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        save()
    }

    func update(jobId: String, title: String?, thumbnailUrl: String?, status: JobStatus, totalMessages: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == jobId }) else { return }
        entries[idx].title = title ?? entries[idx].title
        entries[idx].thumbnailUrl = thumbnailUrl ?? entries[idx].thumbnailUrl
        entries[idx].status = status
        entries[idx].totalMessages = totalMessages
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

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
