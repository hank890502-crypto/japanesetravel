import AVFoundation
import SwiftUI
import VisionKit

/// 用相機掃 QR Code（iOS 內建的 DataScanner）。只在真機可用。
struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var didFire = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didFire else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    didFire = true
                    dataScanner.stopScanning()
                    onCode(payload)
                    return
                }
            }
        }
    }
}

/// 掃碼畫面現在能不能用；不能用時要分清楚原因，長輩才知道接下來能做什麼。
enum QRScanAvailability: Equatable {
    /// 還在問相機權限（系統對話框跳出來的時候）
    case checking
    /// 可以掃
    case ready
    /// 之前在權限對話框按了「不允許」：到「設定」打開就好
    case permissionDenied
    /// 被「螢幕使用時間」或裝置管理限制：設定裡沒有開關
    case permissionRestricted
    /// 這台裝置（或模擬器）沒有能掃描的相機
    case unsupported
    /// 相機暫時被別的 App 佔用
    case cameraBusy

    /// 先看權限，再看硬體，最後看相機現在有沒有空。
    static func resolve(status: AVAuthorizationStatus, isSupported: Bool, isAvailable: Bool) -> QRScanAvailability {
        switch status {
        case .notDetermined: return .checking
        case .denied: return .permissionDenied
        case .restricted: return .permissionRestricted
        case .authorized: break
        @unknown default: return .permissionDenied
        }
        guard isSupported else { return .unsupported }
        return isAvailable ? .ready : .cameraBusy
    }

    /// 給長輩看的標題與說明（白話，說清楚接下來可以做什麼）
    var title: String {
        switch self {
        case .checking: "正在準備相機…"
        case .ready: ""
        case .permissionDenied: "還沒有允許使用相機"
        case .permissionRestricted: "這台手機的相機被限制使用"
        case .unsupported: "這台裝置不能掃描"
        case .cameraBusy: "相機現在沒辦法使用"
        }
    }

    var message: String {
        switch self {
        case .checking: "如果跳出詢問，請按「允許」。"
        case .ready: ""
        case .permissionDenied: "掃 QR Code 需要用到相機。請按下面的按鈕打開「設定」，把「相機」打開，再回來掃一次。"
        case .permissionRestricted: "可能是「螢幕使用時間」或管理設定把相機關掉了。請改用輸入代碼，或請家人幫忙檢查。"
        case .unsupported: "請改用輸入代碼：請家人把 6 個字的房間代碼唸給你聽。"
        case .cameraBusy: "可能有別的 App 正在用相機。請先關掉那個 App 再試一次，或改用輸入代碼。"
        }
    }

    /// 只有「使用者自己按了不允許」這種情況，去設定才有開關可以打開
    var canOpenSettings: Bool { self == .permissionDenied }
}

/// 掃碼畫面：相機 + 大字說明 + 關閉。相機不能用時改成說明卡，被拒絕權限時附「前往設定」。
struct QRCodeScanSheet: View {
    let onCode: (String) -> Void
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var availability: QRScanAvailability = .checking

    var body: some View {
        ZStack(alignment: .top) {
            switch availability {
            case .ready:
                QRCodeScannerView(onCode: onCode)
                    .ignoresSafeArea()
            case .checking:
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text(availability.title).font(.app(.sectionTitle))
                    Text(availability.message).font(.app(.body)).foregroundStyle(AppColors.secondaryText)
                }
                .multilineTextAlignment(.center)
                .padding(AccessibilityMetrics.screenPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.screenBackground)
            default:
                unavailableCard
            }

            HStack {
                if availability == .ready {
                    Text("對準家人手機上的 QR Code")
                        .font(.app(.body).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
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
                    .background(Color.white, in: Capsule())
                }
                .accessibilityLabel("關閉，回到上一頁")
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            // 從「設定」回來再檢查一次
            if phase == .active { Task { await refresh() } }
        }
    }

    private var unavailableCard: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: availability.canOpenSettings ? "camera.badge.ellipsis" : "camera.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityHidden(true)
                Text(availability.title)
                    .font(.app(.sectionTitle))
                    .multilineTextAlignment(.center)
                Text(availability.message)
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)

                if availability.canOpenSettings {
                    PrimaryButton(title: "前往設定，打開相機", systemImage: "gearshape.fill") {
                        openSettings()
                    }
                }
                if availability == .cameraBusy {
                    PrimaryButton(title: "再試一次", systemImage: AppIcon.retry) {
                        Task { await refresh() }
                    }
                }
                SecondaryButton(title: "改用輸入代碼", systemImage: "keyboard") {
                    onClose()
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
            .padding(.top, AccessibilityMetrics.minimumTapTarget + AccessibilityMetrics.screenPadding * 2)   // 讓出上面「關閉」鍵的位置
            .readableWidth()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.screenBackground)
    }

    /// 沒問過就先問權限，再判斷能不能掃。
    private func refresh() async {
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            availability = .checking
            _ = await AVCaptureDevice.requestAccess(for: .video)
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
        availability = QRScanAvailability.resolve(
            status: status,
            isSupported: DataScannerViewController.isSupported,
            isAvailable: DataScannerViewController.isAvailable
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview("掃碼（模擬器上會顯示不能掃描）") {
    QRCodeScanSheet(onCode: { _ in }, onClose: {})
}
