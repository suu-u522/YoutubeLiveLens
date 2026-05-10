import SwiftUI

// TODO: 次フェーズで本実装
struct AnalysisProgressView: View {
    let jobId: String
    @StateObject private var vm: AnalysisViewModel

    init(jobId: String) {
        self.jobId = jobId
        _vm = StateObject(wrappedValue: AnalysisViewModel(jobId: jobId))
    }

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text("分析中...")
                .font(.headline)
            if let job = vm.job {
                Text("取得済み: \(job.totalMessages)件 (\(job.progress)ページ)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("分析中")
        .navigationBarTitleDisplayMode(.inline)
    }
}
