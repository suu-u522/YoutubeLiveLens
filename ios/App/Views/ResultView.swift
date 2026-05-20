import SwiftUI
import Charts

struct ResultView: View {
    let job: AnalysisJob
    @StateObject private var vm: ResultViewModel
    @State private var showSearch = false

    init(job: AnalysisJob) {
        self.job = job
        _vm = StateObject(wrappedValue: ResultViewModel(job: job))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                thumbnail
                summaryHeader
                chartSection
                top5Section
                searchButton
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(job.title ?? "分析結果")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showSearch) {
            SearchView(jobId: job.id, videoId: job.videoId)
        }
        #if DEBUG
        .onAppear { showSearch = true }
        #endif
    }

    // MARK: - サムネイル

    private var thumbnail: some View {
        AsyncImage(url: job.thumbnailUrl.flatMap(URL.init)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Rectangle().foregroundStyle(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
        .clipped()
    }

    // MARK: - サマリー

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = job.title {
                Text(title)
                    .font(.headline)
                    .lineLimit(3)
            }
            if let pub = job.publishDate {
                Label(pub, systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let sec = job.lengthSeconds {
                Label(formatDuration(sec), systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Label("\(job.totalMessages.formatted()) コメント", systemImage: "bubble.left.and.bubble.right")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - グラフ

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("コメント推移")
                    .font(.headline)
                Spacer()
                Picker("粒度", selection: $vm.bucketMinutes) {
                    Text("1分").tag(1)
                    Text("5分").tag(5)
                    Text("10分").tag(10)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal, 16)

            if job.timeline.isEmpty {
                Text("データがありません")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                chartView
            }
        }
    }

    private var chartView: some View {
        let timeline = vm.aggregatedTimeline
        let maxCount = timeline.map(\.count).max() ?? 1
        let barWidth: CGFloat = 12
        let barSpacing: CGFloat = 4
        let chartWidth = CGFloat(timeline.count) * (barWidth + barSpacing) + 32
        let labelSpanMinutes: Int
        switch vm.bucketMinutes {
        case 1:  labelSpanMinutes = 15
        case 5:  labelSpanMinutes = 30
        default: labelSpanMinutes = 60
        }
        let labelInterval = labelSpanMinutes / vm.bucketMinutes

        return ScrollView(.horizontal, showsIndicators: false) {
            Chart(timeline) { bucket in
                BarMark(
                    x: .value("時間", bucket.startTime),
                    y: .value("コメント数", bucket.count),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(bucket.count == maxCount ? Color.red : Color.red.opacity(0.5))
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: timeline.filter { $0.bucketIndex % labelInterval == 0 }.map(\.startTime)) { value in
                    AxisValueLabel(anchor: .top) {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(size: 9))
                                .fixedSize()
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(width: chartWidth, height: 200)
            .padding(.top, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let x = location.x - 16
                let idx = Int(x / (barWidth + barSpacing))
                if idx >= 0 && idx < timeline.count {
                    vm.openInYouTube(startMs: timeline[idx].startMs)
                }
            }
        }
    }

    // MARK: - TOP5

    private var top5Section: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("盛り上がりTOP5", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            if job.top5.isEmpty {
                Text("データがありません")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(job.top5.enumerated()), id: \.offset) { index, scene in
                        Top5Row(rank: index + 1, scene: scene) {
                            vm.openInYouTube(startMs: scene.startMs)
                        }
                        if index < job.top5.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - 検索ボタン

    private var searchButton: some View {
        Button {
            showSearch = true
        } label: {
            Label("コメントをキーワード検索", systemImage: "magnifyingglass")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.secondarySystemGroupedBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)時間\(m)分" : "\(m)分"
    }
}

// MARK: - TOP5行

struct Top5Row: View {
    let rank: Int
    let scene: Top5Scene
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.title2.bold())
                .foregroundStyle(rankColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(scene.timeRange)
                    .font(.subheadline.weight(.medium))
                Label("\(scene.count) コメント", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .orange
        case 2: return Color(red: 0.75, green: 0.78, blue: 0.82)
        case 3: return .brown
        default: return .secondary
        }
    }
}
