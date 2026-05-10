import Foundation
import UIKit

@MainActor
final class ResultViewModel: ObservableObject {
    @Published var selectedBucket: CommentBucket?
    @Published var isLoadingComments = false

    let job: AnalysisJob
    private let service = FirebaseService.shared

    init(job: AnalysisJob) {
        self.job = job
    }

    func selectBucket(_ bucket: TimelineBucket) async {
        isLoadingComments = true
        do {
            selectedBucket = try await service.fetchCommentBucket(
                jobId: job.id,
                bucketIndex: bucket.bucketIndex
            )
        } catch {
            selectedBucket = nil
        }
        isLoadingComments = false
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
