import Foundation
import UIKit

@MainActor
final class ResultViewModel: ObservableObject {
    @Published var bucketMinutes: Int = 5

    let job: AnalysisJob
    private let service = FirebaseService.shared

    init(job: AnalysisJob) {
        self.job = job
    }

    var aggregatedTimeline: [TimelineBucket] {
        let source = job.timeline
        guard !source.isEmpty else { return [] }
        guard bucketMinutes > 1 else { return source }

        var grouped: [Int: Int] = [:]
        for bucket in source {
            let groupIdx = bucket.bucketIndex / bucketMinutes
            grouped[groupIdx] = (grouped[groupIdx] ?? 0) + bucket.count
        }

        let maxGroup = grouped.keys.max() ?? 0
        return (0...maxGroup).map { idx in
            let startMs = idx * bucketMinutes * 60000
            let endMs = startMs + bucketMinutes * 60000
            return TimelineBucket(
                bucketIndex: idx,
                startMs: startMs,
                endMs: endMs,
                count: grouped[idx] ?? 0
            )
        }
    }

    func openInYouTube(startMs: Int) {
        let seconds = startMs / 1000
        let videoId = job.videoId
        if let url = URL(string: "youtube://www.youtube.com/watch?v=\(videoId)&t=\(seconds)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)&t=\(seconds)") {
            UIApplication.shared.open(url)
        }
    }
}
