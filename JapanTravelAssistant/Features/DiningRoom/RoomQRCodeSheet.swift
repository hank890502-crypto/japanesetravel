import SwiftUI

/// 房主給家人掃的 QR Code：大大的 QR + 大字代碼。
struct RoomQRCodeSheet: View {
    let room: DiningRoom
    var webGuestURL: URL? = nil
    let onClose: () -> Void

    private var link: URL { DeepLinkParser.shareURL(code: room.roomCode, webGuestURL: webGuestURL) }

    var body: some View {
        VStack(spacing: 24) {
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
            }
            Text(webGuestURL == nil
                 ? "請家人打開 App，按「加入家人的點餐 → 掃 QR Code」"
                 : "用手機相機掃這個 QR Code 就能加入。有裝 App 的請在 App 裡掃。")
                .font(.app(.body))
                .foregroundStyle(Color(white: 0.35))
                .multilineTextAlignment(.center)
            if let image = QRCodeGenerator.image(for: link.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300)
                    .accessibilityLabel("加入房間的 QR Code")
            }
            VStack(spacing: 4) {
                Text("或輸入代碼")
                    .font(.app(.caption))
                    .foregroundStyle(Color(white: 0.35))
                Text(room.roomCode.map(String.init).joined(separator: " "))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
            }
            Spacer()
        }
        .padding(AccessibilityMetrics.screenPadding)
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

#Preview {
    RoomQRCodeSheet(room: DiningRoom(name: "酒津屋晚餐", roomCode: "A8F3K2", hostUserId: UUID()), onClose: {})
}
