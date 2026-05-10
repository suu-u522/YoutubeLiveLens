import Foundation

struct HistoryEntry: Identifiable, Codable {
    let id: String        // jobId
    let videoId: String
    var title: String?
    var thumbnailUrl: String?
    var publishDate: String?
    let createdAt: Date
    var status: JobStatus
    var totalMessages: Int
}
