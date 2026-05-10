import SwiftUI

struct AnalysisProgressView: View {
    let jobId: String
    @ObservedObject private var historyStore = HistoryStore.shared
    @EnvironmentObject private var homeVM: HomeViewModel
    @State private var navigateToResult = false
    @State private var resultJob: AnalysisJob?

    private var entry: HistoryEntry? {
        historyStore.entries.first { $0.id == jobId }
    }

    var body: some View {
        Group {
            if let entry {
                content(entry: entry)
                    .onChange(of: entry.status) { status in
                        if status == .done {
                            Task {
                                resultJob = await homeVM.fetchJob(jobId: jobId)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    navigateToResult = true
                                }
                            }
                        }
                    }
            } else {
                loadingPlaceholder
            }
        }
        .navigationTitle("分析中")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(entry?.status == .fetching)
        .navigationDestination(isPresented: $navigateToResult) {
            if let job = resultJob {
                ResultView(job: job)
            }
        }
    }

    // MARK: - メインコンテンツ

    private func content(entry: HistoryEntry) -> some View {
        VStack(spacing: 0) {
            thumbnail(entry: entry)

            VStack(spacing: 32) {
                Text(entry.title ?? "タイトル取得中...")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                switch entry.status {
                case .fetching:
                    fetchingView(entry: entry)
                case .done:
                    doneView
                case .error:
                    errorView(message: entry.errorMessage)
                }
            }
            .padding(.top, 32)

            Spacer()
        }
    }

    // MARK: - 取得中

    private func fetchingView(entry: HistoryEntry) -> some View {
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
                    Label("\(entry.totalMessages.formatted()) 件", systemImage: "bubble.left.and.bubble.right")
                    Label("\(entry.progress ?? 0) ページ", systemImage: "doc.text")
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

    private func thumbnail(entry: HistoryEntry) -> some View {
        AsyncImage(url: entry.thumbnailUrl.flatMap(URL.init)) { phase in
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
