import SwiftUI

struct PaywallView: View {
    let url: String
    let onPurchased: (String, String) -> Void  // (jobId, videoId)

    @StateObject private var purchase = PurchaseService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            VStack(spacing: 16) {
                AppLogoView(size: 72)
                    .padding(.top, 48)

                Text("LiveLens")
                    .font(.largeTitle.bold())

                Text("無料での分析は3本までです")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)

            // 特典リスト
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "infinity", text: "分析本数が無制限に")
                featureRow(icon: "chart.bar.fill", text: "コメント推移グラフを何度でも")
                featureRow(icon: "magnifyingglass", text: "キーワード検索が使い放題")
            }
            .padding(.horizontal, 32)

            Spacer()

            // エラー
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            // 購入ボタン
            Button {
                Task { await doPurchase() }
            } label: {
                Group {
                    if purchase.isLoading {
                        ProgressView()
                    } else {
                        Text("980円で無制限に解放")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(purchase.isLoading)
            .padding(.horizontal, 24)

            // 復元
            Button {
                Task { await doRestore() }
            } label: {
                Text("購入を復元する")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            .disabled(purchase.isLoading)

            Text("価格はApp Storeに表示される金額です。購入は一度のみです。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
        }
    }

    private func doPurchase() async {
        errorMessage = nil
        do {
            try await purchase.purchase()
            if purchase.isPurchased {
                // 購入完了後に分析API呼び出し
                let service = FirebaseService.shared
                let fcmToken = FCMService.shared.fcmToken
                if let jobId = try? await service.analyzeChat(url: url, fcmToken: fcmToken) {
                    let videoId = url.components(separatedBy: "v=").dropFirst().first?
                        .components(separatedBy: "&").first ?? ""
                    onPurchased(jobId, videoId)
                }
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func doRestore() async {
        errorMessage = nil
        do {
            try await purchase.restore()
            if purchase.isPurchased { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
