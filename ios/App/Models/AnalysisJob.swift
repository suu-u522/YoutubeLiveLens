import Foundation

struct TimelineBucket: Identifiable, Codable {
    var id: Int { bucketIndex }
    let bucketIndex: Int
    let startMs: Int
    let endMs: Int
    let count: Int

    var startTime: String {
        formatMs(startMs)
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

struct Top5Scene: Identifiable, Codable {
    var id: Int { startMs }
    let startMs: Int
    let endMs: Int
    let count: Int

    var timeRange: String {
        "\(formatMs(startMs)) 〜 \(formatMs(endMs))"
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

enum JobStatus: String, Codable {
    case fetching
    case done
    case error
}

struct AnalysisJob: Identifiable, Codable {
    let id: String
    let videoId: String
    let url: String
    var title: String?
    var thumbnailUrl: String?
    var status: JobStatus
    var progress: Int
    var totalMessages: Int
    var timeline: [TimelineBucket]
    var top5: [Top5Scene]
    var errorMessage: String?

    init(
        id: String,
        videoId: String,
        url: String,
        status: JobStatus = .fetching,
        progress: Int = 0,
        totalMessages: Int = 0
    ) {
        self.id = id
        self.videoId = videoId
        self.url = url
        self.status = status
        self.progress = progress
        self.totalMessages = totalMessages
        self.timeline = []
        self.top5 = []
    }
}
