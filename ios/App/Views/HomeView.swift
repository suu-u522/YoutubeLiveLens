import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var historyStore = HistoryStore.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                historyList
                fab
            }
            .navigationTitle("YoutubeLiveLens")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $vm.showURLSheet) {
                URLInputSheet(vm: vm)
            }
            .navigationDestination(isPresented: Binding(
                get: { vm.isNavigating },
                set: { vm.isNavigating = $0 }
            )) {
                switch vm.navigationTarget {
                case .progress(let jobId):
                    AnalysisProgressView(jobId: jobId)
                case .result(let job):
                    ResultView(job: job)
                case nil:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - 履歴リスト

    private var historyList: some View {
        Group {
            if historyStore.entries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(historyStore.entries) { entry in
                        HistoryCard(entry: entry)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onTapGesture { vm.tapHistory(entry) }
                            .opacity(entry.status == .fetching ? 1.0 : 1.0)
                            .allowsHitTesting(entry.status != .fetching)
                    }
                    .onDelete { indexSet in
                        indexSet.map { historyStore.entries[$0].id }.forEach {
                            historyStore.remove(id: $0)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - 空の状態

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("分析した動画がここに表示されます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("右下の ＋ ボタンでYouTube URLを入力")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            vm.showURLSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.bold())
                .frame(width: 56, height: 56)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - 履歴カード

struct HistoryCard: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            info
            Spacer()
            statusBadge
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var thumbnail: some View {
        AsyncImage(url: entry.thumbnailUrl.flatMap(URL.init)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure, .empty:
                Rectangle()
                    .foregroundStyle(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(.secondary)
                    }
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: 100, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title ?? "タイトル取得中...")
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if entry.status == .fetching {
                Text("\(entry.totalMessages.formatted()) 件取得中...")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateLabel: String {
        if let pub = entry.publishDate {
            return "配信日: \(pub)"
        }
        return entry.createdAt.formatted(.relative(presentation: .named))
    }

    private var statusBadge: some View {
        Group {
            switch entry.status {
            case .fetching:
                ProgressView()
                    .scaleEffect(0.8)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - URL入力シート

struct URLInputSheet: View {
    @ObservedObject var vm: HomeViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YouTube 動画URL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("https://www.youtube.com/watch?v=...", text: $vm.urlText)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isFocused)

                        if !vm.urlText.isEmpty {
                            Button {
                                vm.urlText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // クリップボードから貼り付け
                    if let clip = UIPasteboard.general.string, clip.contains("youtube.com/watch") {
                        Button {
                            vm.urlText = clip
                        } label: {
                            Label("クリップボードから貼り付け", systemImage: "doc.on.clipboard")
                                .font(.caption)
                        }
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await vm.analyzeFromInput() }
                } label: {
                    Group {
                        if vm.isLoading {
                            ProgressView()
                        } else {
                            Text("分析を開始する")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(vm.urlText.isEmpty ? Color(.systemGray4) : Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(vm.urlText.isEmpty || vm.isLoading)

                Spacer()
            }
            .padding(20)
            .navigationTitle("新しい分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        vm.showURLSheet = false
                        vm.errorMessage = nil
                    }
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }
}
