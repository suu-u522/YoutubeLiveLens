import SwiftUI

// TODO: 次フェーズで本実装
struct ResultView: View {
    let job: AnalysisJob

    var body: some View {
        Text("結果画面（実装予定）\n\(job.title ?? job.videoId)")
            .multilineTextAlignment(.center)
            .navigationTitle("分析結果")
            .navigationBarTitleDisplayMode(.inline)
    }
}
