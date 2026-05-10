import SwiftUI

struct SearchView: View {
    let jobId: String
    let videoId: String
    @StateObject private var vm: SearchViewModel

    init(jobId: String, videoId: String) {
        self.jobId = jobId
        self.videoId = videoId
        _vm = StateObject(wrappedValue: SearchViewModel(jobId: jobId))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultList
        }
        .navigationTitle("コメント検索")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadIfNeeded() }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("キーワードを入力...", text: $vm.keyword)
                .autocorrectionDisabled()
            if !vm.keyword.isEmpty {
                Button { vm.keyword = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var resultList: some View {
        if vm.isLoading {
            ProgressView("読み込み中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.filteredComments.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle).foregroundStyle(.secondary)
                Text(vm.keyword.isEmpty ? "コメントがありません" : "「\(vm.keyword)」は見つかりませんでした")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(vm.filteredComments) { comment in
                CommentRow(comment: comment, videoId: videoId)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - コメント行

struct CommentRow: View {
    let comment: Comment
    let videoId: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                openInYouTube(offsetMs: comment.offsetMs)
            } label: {
                Text(formatMs(comment.offsetMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.blue)
                    .underline()
            }
            .buttonStyle(.plain)

            Text(comment.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func openInYouTube(offsetMs: Int) {
        let seconds = offsetMs / 1000
        if let url = URL(string: "youtube://www.youtube.com/watch?v=\(videoId)&t=\(seconds)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)&t=\(seconds)") {
            UIApplication.shared.open(url)
        }
    }

    private func formatMs(_ ms: Int) -> String {
        let s = ms / 1000
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
