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

/// 掃碼畫面：相機 + 大字說明 + 關閉。
struct QRCodeScanSheet: View {
    let onCode: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if QRCodeScannerView.isSupported {
                QRCodeScannerView(onCode: onCode)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Text("這台裝置不能掃描")
                        .font(.app(.sectionTitle))
                    Text("請改用輸入代碼。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.screenBackground)
            }
            HStack {
                Text("對準家人手機上的 QR Code")
                    .font(.app(.body).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
    }
}
