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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        AppLogoView(size: 28)
                        Text("LiveLens")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
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
                            .allowsHitTesting(entry.status != .fetching)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    historyStore.remove(id: entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
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
                .foregroundStyle(.secondary)
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
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
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
                Text("取得中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
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
    @State private var previewTitle: String?
    @State private var isLiveVideo: Bool?
    @State private var fetchTask: Task<Void, Never>?

    private var videoId: String? {
        guard let range = vm.urlText.range(of: "v=") else { return nil }
        let after = vm.urlText[range.upperBound...]
        if let end = after.firstIndex(of: "&") {
            return String(after[after.startIndex..<end])
        }
        return after.isEmpty ? nil : String(after)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer().frame(height: 4)
                // サムネイル＋タイトルプレビュー
                if let vid = videoId,
                   let thumbURL = URL(string: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg") {
                    ZStack(alignment: .bottomLeading) {
                        AsyncImage(url: thumbURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Rectangle().foregroundStyle(Color(.systemGray5))
                                    .overlay { ProgressView() }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()

                        if let title = previewTitle {
                            Text(title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.black.opacity(0.55))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .onChange(of: vid) { newId in
                        fetchVideoInfo(videoId: newId)
                    }
                    .onAppear { fetchVideoInfo(videoId: vid) }
                }

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

                if isLiveVideo == false {
                    Text("終了したライブ配信のアーカイブのみ対応しています")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                let isDisabled = vm.urlText.isEmpty || vm.isLoading || isLiveVideo == false
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
                    .background(isDisabled ? Color(.systemGray4) : Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isDisabled)

                Spacer()
            }
            .padding(20)
            .navigationTitle("新たに分析する")
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
            .confirmationDialog("無料の分析回数を使い切りました", isPresented: $vm.showLimitAlert, titleVisibility: .visible) {
                Button("広告を見て続ける") {
                    showAd()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("広告を視聴すると分析を続けられます")
            }
        }
        .presentationDetents([.medium])
    }

    private func showAd() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = window.rootViewController else { return }

        var vc = rootVC
        while let presented = vc.presentedViewController { vc = presented }

        let adService = RewardedAdService.shared
        guard adService.isAdReady else {
            vm.errorMessage = "広告を準備中です。少し待ってからお試しください"
            return
        }

        let url = vm.urlText.trimmingCharacters(in: .whitespaces)

        adService.show(from: vc) {
            // 広告完了後にAPI呼び出し開始
            Task { @MainActor in
                if let result = await vm.callAnalysisAPI(url: url) {
                    vm.grantRewardedAnalysis()
                    vm.commitToHistory(jobId: result.jobId, url: url, videoId: result.videoId)
                }
            }
        }
    }

    private func fetchVideoInfo(videoId: String) {
        previewTitle = nil
        isLiveVideo = nil
        fetchTask?.cancel()
        fetchTask = Task {
            guard let pageURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: pageURL),
                  let html = String(data: data, encoding: .utf8) else { return }
            guard !Task.isCancelled else { return }

            let isArchive = html.contains("\"isLiveContent\":true") && !html.contains("\"isLive\":true")
            let title: String? = {
                guard let range = html.range(of: "<title>"),
                      let end = html.range(of: "</title>", range: range.upperBound..<html.endIndex) else { return nil }
                let raw = String(html[range.upperBound..<end.lowerBound])
                return raw.hasSuffix(" - YouTube") ? String(raw.dropLast(10)) : raw
            }()

            await MainActor.run {
                isLiveVideo = isArchive
                previewTitle = title
            }
        }
    }
}

// MARK: - アプリロゴ

struct AppLogoView: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(
                    LinearGradient(
                        colors: [Color.red, Color(red: 0.75, green: 0, blue: 0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            VStack(spacing: size * 0.05) {
                RoundedPlayShape()
                    .fill(Color.white)
                    .frame(width: size * 0.38, height: size * 0.40)
                    .offset(x: size * 0.03)

                HStack(alignment: .bottom, spacing: size * 0.05) {
                    ForEach([0.45, 0.75, 1.0, 0.65, 0.55], id: \.self) { ratio in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.9))
                            .frame(width: size * 0.08, height: size * 0.22 * ratio)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct RoundedPlayShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * 0.10
        let topLeft    = CGPoint(x: rect.minX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let right      = CGPoint(x: rect.maxX, y: rect.midY)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addArc(tangent1End: topLeft,    tangent2End: right,      radius: r)
        path.addArc(tangent1End: right,      tangent2End: bottomLeft, radius: r)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft,    radius: r)
        path.closeSubpath()
        return path
    }
}
