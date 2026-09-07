import SwiftUI
import UIKit

/// 要給店員看的內容：一句日文，可選擇附上一張照片（例如要找的商品）。
struct StaffDisplayContent: Identifiable, Hashable, Sendable {
    var id: String
    var japanese: String
    var chinese: String?
    var reading: String?
    var image: UIImage?

    init(id: String = UUID().uuidString, japanese: String, chinese: String? = nil, reading: String? = nil, image: UIImage? = nil) {
        self.id = id
        self.japanese = japanese
        self.chinese = chinese
        self.reading = reading
        self.image = image
    }

    init(phrase: Phrase, image: UIImage? = nil) {
        self.init(id: phrase.id, japanese: phrase.japanese, chinese: phrase.chinese, reading: phrase.reading, image: image)
    }
}

/// 「給店員看」全螢幕：極簡、大日文、一個播放鍵、一個關閉鍵。
/// 強制亮色、高對比，並在顯示期間不讓螢幕自動關閉。
struct StaffDisplayView: View {
    let content: StaffDisplayContent
    let onClose: () -> Void

    @Environment(\.dependencies) private var dependencies
    @ScaledMetric(relativeTo: .largeTitle) private var heroFontSize: CGFloat = 52
    @State private var isSpeaking = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: AppIcon.close)
                        Text("關閉")
                    }
                    .font(.app(.buttonLabel))
                    .foregroundStyle(.black)
                    .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                    .padding(.horizontal, 20)
                    .background(Color(white: 0.92), in: Capsule())
                }
                .accessibilityLabel("關閉，回到上一頁")
            }
            .padding(AccessibilityMetrics.screenPadding)

            if let image = content.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                    .padding(.horizontal, AccessibilityMetrics.screenPadding)
                    .accessibilityLabel("要給店員看的商品照片")
            }

            // 日文放在可捲動的區塊：地址那種 5～7 行的內容、或字體開很大時，不縮小也不截斷，往下捲就看得到全部。
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        Text(content.japanese)
                            .font(.system(size: Self.heroFontSize(base: heroFontSize, hasImage: content.image != nil, text: content.japanese), weight: .heavy))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .accessibilityLabel("日文：\(content.japanese)")
                        if let reading = content.reading?.nilIfBlank {
                            Text(reading)
                                .font(.app(.body))
                                .foregroundStyle(Color(white: 0.35))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, AccessibilityMetrics.screenPadding)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)   // 內容短的時候維持置中
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: 16) {
                if let chinese = content.chinese?.nilIfBlank {
                    Text("中文：\(chinese)")
                        .font(.app(.caption))
                        .foregroundStyle(Color(white: 0.35))
                        .multilineTextAlignment(.center)
                }
                if dependencies.speech.isAvailable {
                    PrimaryButton(title: isSpeaking ? "播放中…" : "播放日文", systemImage: AppIcon.speak, isEnabled: !isSpeaking) {
                        Task { await speak() }
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Task { await dependencies.speech.stop() }
        }
    }

    private func speak() async {
        isSpeaking = true
        await dependencies.speech.speak(content.japanese, language: .japanese)
        isSpeaking = false
    }

    /// 超過這個長度（或有換行，例如「店名＋地址」）就算長內容
    static let longTextThreshold = 20
    /// 長內容時字級的上限：地址不需要像一句話那麼大，先放得下、看得全比較重要
    static let longTextMaxFontSize: CGFloat = 44

    /// 主要日文的字級：一句話用最大字；附照片時縮 0.8；長內容（地址）把上限壓在 44pt。
    static func heroFontSize(base: CGFloat, hasImage: Bool, text: String) -> CGFloat {
        let size = hasImage ? base * 0.8 : base
        let isLong = text.contains("\n") || text.count > longTextThreshold
        return isLong ? min(size, longTextMaxFontSize) : size
    }
}

#Preview("句子") {
    StaffDisplayView(
        content: StaffDisplayContent(japanese: "こちらの商品はありますか？", chinese: "請問有這個商品嗎？", reading: "こちらの しょうひんは ありますか"),
        onClose: {}
    )
    .environment(\.dependencies, .preview)
}

#Preview("地址給司機看") {
    StaffDisplayView(
        content: StaffDisplayContent(
            japanese: "ここまでお願いします。\n東京ステーションホテル\n〒100-0005 東京都千代田区丸の内1丁目9-1",
            chinese: "請載我到這裡：東京車站飯店"
        ),
        onClose: {}
    )
    .environment(\.dependencies, .preview)
    .dynamicTypeSize(.accessibility3)
}

#Preview("附照片") {
    StaffDisplayView(
        content: StaffDisplayContent(
            japanese: "こちらの商品はありますか？",
            chinese: "請問有這個商品嗎？",
            image: UIImage(systemName: "photo")
        ),
        onClose: {}
    )
    .environment(\.dependencies, .preview)
}
