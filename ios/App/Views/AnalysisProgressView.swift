import SwiftUI

struct AnalysisProgressView: View {
    let jobId: String
    @StateObject private var vm: AnalysisViewModel
    @State private var navigateToResult = false

    init(jobId: String) {
        self.jobId = jobId
        _vm = StateObject(wrappedValue: AnalysisViewModel(jobId: jobId))
    }

    var body: some View {
        Group {
            if let job = vm.job {
                content(job: job)
                    .onChange(of: job.status) { status in
                        if status == .done {
                            // Firestoreの書き込みが全て完了するよう少し待ってから遷移
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                navigateToResult = true
                            }
                        }
                        HistoryStore.shared.update(
                            jobId: job.id,
                            title: job.title,
                            thumbnailUrl: job.thumbnailUrl,
                            publishDate: job.publishDate,
                            status: status,
                            totalMessages: job.totalMessages
                        )
                    }
            } else {
                loadingPlaceholder
            }
        }
        .navigationTitle("分析中")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(vm.job?.status == .fetching)
        .navigationDestination(isPresented: $navigateToResult) {
            if let job = vm.job {
                ResultView(job: job)
            }
        }
    }

    // MARK: - メインコンテンツ

    private func content(job: AnalysisJob) -> some View {
        VStack(spacing: 0) {
            // サムネイル
            thumbnail(job: job)

            VStack(spacing: 32) {
                // タイトル
                Text(job.title ?? "タイトル取得中...")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                switch job.status {
                case .fetching:
                    fetchingView(job: job)
                case .done:
                    doneView
                case .error:
                    errorView(message: job.errorMessage)
                }
            }
            .padding(.top, 32)

            Spacer()
        }
    }

    // MARK: - 取得中

    private func fetchingView(job: AnalysisJob) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.red)
                .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text("チャットを取得中...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label("\(job.totalMessages.formatted()) 件", systemImage: "bubble.left.and.bubble.right")
                    Label("\(job.progress) ページ", systemImage: "doc.text")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 完了

    private var doneView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("分析完了！")
                .font(.headline)
        }
    }

    // MARK: - エラー

    private func errorView(message: String?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("エラーが発生しました")
                .font(.headline)
            if let msg = message {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - サムネイル

    private func thumbnail(job: AnalysisJob) -> some View {
        AsyncImage(url: job.thumbnailUrl.flatMap(URL.init)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
            default:
                Rectangle()
                    .foregroundStyle(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    // MARK: - 初期ローディング

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("読み込み中...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
