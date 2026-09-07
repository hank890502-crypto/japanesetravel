import SwiftUI
import UIKit

/// 用 ChatGPT 一次匯入整趟行程：複製提示文字 → 丟到討論行程的對話 → 貼回來。
struct TripImportView: View {
    let tripId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store

    @State private var didCopy = false
    @State private var showPrompt = false
    @State private var pastedText = ""
    @State private var error: UserFacingError?
    @State private var importedCount: Int?
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let importedCount {
                    doneView(importedCount)
                } else {
                    stepsView
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .elderlyScreen(title: "用 ChatGPT 匯入行程")
    }

    private var stepsView: some View {
        Group {
            Text("把之前和 ChatGPT 討論好的行程，一次變成這趟旅程的地點清單。")
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)

            stepCard(number: 1, title: "複製提示文字") {
                PrimaryButton(title: didCopy ? "已複製，去 ChatGPT 貼上" : "複製提示文字", systemImage: didCopy ? AppIcon.check : AppIcon.copy) {
                    UIPasteboard.general.string = ChatGPTTripPrompt.text
                    withAnimation { didCopy = true }
                }
                Button { withAnimation { showPrompt.toggle() } } label: {
                    Label(showPrompt ? "收起提示文字" : "看提示文字內容", systemImage: showPrompt ? "chevron.up" : "chevron.down")
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.accent)
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                }
                if showPrompt {
                    Text(ChatGPTTripPrompt.text)
                        .font(.system(.footnote))
                        .textSelection(.enabled)
                        .padding(12)
                        .background(AppColors.screenBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            stepCard(number: 2, title: "到「討論行程」的那個 ChatGPT 對話貼上") {
                Text("要貼在原本那個對話裡，ChatGPT 才知道你的行程。送出後把回覆整段複製。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                SecondaryButton(title: "打開 ChatGPT", systemImage: AppIcon.openApp) { openChatGPT() }
            }

            stepCard(number: 3, title: "把回覆貼回來") {
                SecondaryButton(title: "貼上 ChatGPT 的回覆", systemImage: AppIcon.paste) {
                    if let text = UIPasteboard.general.string?.nilIfBlank { pastedText = text; error = nil }
                    else { error = UserFacingError(title: "剪貼簿裡沒有文字", message: "請先到 ChatGPT 長按回覆，選「複製」。") }
                }
                TextEditor(text: $pastedText)
                    .font(.app(.body))
                    .focused($editorFocused)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(AppColors.screenBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(editorFocused ? AppColors.accent : AppColors.separator, lineWidth: 2))
                    .accessibilityLabel("ChatGPT 的回覆")
            }

            if let error { ErrorBanner(error: error) }

            PrimaryButton(title: "匯入到這趟旅程", systemImage: AppIcon.check, isEnabled: !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                importPasted()
            }
        }
    }

    private func stepCard<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.app(.cardTitle))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(AppColors.accent, in: Circle())
                    .accessibilityHidden(true)
                Text(title).font(.app(.cardTitle))
            }
            content()
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
    }

    private func doneView(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: AppIcon.check).font(.system(size: 44)).foregroundStyle(AppColors.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("匯入完成").font(.app(.sectionTitle))
                    Text("加入了 \(count) 個地點。App 會在背景幫它們找座標。").font(.app(.body)).foregroundStyle(AppColors.secondaryText)
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
            PrimaryButton(title: "看這趟的地點", systemImage: AppIcon.go) { router.popOrPush(.tripPlaces(tripId)) }
        }
    }

    private func importPasted() {
        editorFocused = false
        let result = TripImportParser.parse(pastedText)
        guard !result.places.isEmpty else {
            error = UserFacingError(title: "看不懂貼上的內容", message: "請確認貼的是 ChatGPT 的回覆，格式是「地點 | 中文名 | 日文名 | 地址 | 類型 | 備註」。可以回 ChatGPT 說「請照原本的格式重新輸出」。")
            return
        }
        error = nil
        if var trip = store.trip(id: tripId) {
            if trip.name.isEmpty || trip.name == "新的旅程", let name = result.tripName { trip.name = name }
            if trip.startDate == nil { trip.startDate = result.startDate }
            if trip.endDate == nil { trip.endDate = result.endDate }
            store.updateTrip(trip)
        }
        let places = result.places.map { p in
            Place(name: p.name, address: p.address, category: p.category, note: p.note, japaneseName: p.japaneseName, dayLabel: p.dayLabel)
        }
        store.addMany(places, to: tripId)
        importedCount = places.count
    }

    private func openChatGPT() {
        let app = URL(string: "chatgpt://")!, web = URL(string: "https://chatgpt.com")!
        UIApplication.shared.open(UIApplication.shared.canOpenURL(app) ? app : web)
    }
}

#Preview {
    let store = PlaceStore(directory: nil)
    let trip = store.addTrip(name: "9 月名古屋")
    return NavigationStack { TripImportView(tripId: trip.id) }
        .environment(AppRouter())
        .environment(store)
}
