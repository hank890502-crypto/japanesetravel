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
    @State private var importedSummary: (places: Int, stops: Int, recommendations: Int)?
    /// 這趟已經有時間表：解析好的內容先放著，等使用者決定要取代還是加在後面
    @State private var pendingResult: TripImportParser.Result?
    @State private var askReplace = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let importedSummary {
                    doneView(importedSummary)
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
            Text("把之前和 ChatGPT 討論好的行程，一次變成這趟的時間表、地點清單和推薦景點。同一個地方（例如飯店）每天出現也只會存一份。")
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
            .confirmationDialog("這趟已經有時間表了", isPresented: $askReplace, titleVisibility: .visible) {
                Button("換成這次貼上的時間表") { commitPending(replaceExisting: true) }
                Button("加在原本的後面（只補新的）") { commitPending(replaceExisting: false) }
                Button("取消", role: .cancel) { pendingResult = nil }
            } message: {
                Text("「換成」會把原本的時間表換掉，已經存的地點和它們的資料會保留。「加在後面」只會補上原本沒有的。")
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

    private func doneView(_ summary: (places: Int, stops: Int, recommendations: Int)) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: AppIcon.check).font(.system(size: 44)).foregroundStyle(AppColors.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("匯入完成").font(.app(.sectionTitle))
                    Text(summary.stops == 0 && summary.places == 0 && summary.recommendations == 0
                         ? "這些內容原本就都在這趟旅程裡了，沒有新增任何東西。"
                         : "時間表新增 \(summary.stops) 站、會去的地點新增 \(summary.places) 個、推薦景點 \(summary.recommendations) 個。App 會在背景幫它們找座標。")
                        .font(.app(.body)).foregroundStyle(AppColors.secondaryText)
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
        // 這趟已經有時間表：同一段回覆再貼一次、或 ChatGPT 改了行程再貼，要先問是取代還是補在後面
        if !store.sortedStops(in: tripId).isEmpty, !result.itinerary.isEmpty {
            pendingResult = result
            askReplace = true
            return
        }
        commit(result, replaceExisting: false)
    }

    private func commitPending(replaceExisting: Bool) {
        guard let result = pendingResult else { return }
        pendingResult = nil
        commit(result, replaceExisting: replaceExisting)
    }

    private func commit(_ result: TripImportParser.Result, replaceExisting: Bool) {
        if var trip = store.trip(id: tripId) {
            if trip.name.isEmpty || trip.name == "新的旅程", let name = result.tripName { trip.name = name }
            if trip.startDate == nil { trip.startDate = result.startDate }
            if trip.endDate == nil { trip.endDate = result.endDate }
            store.updateTrip(trip)
        }
        let stops = result.itinerary.map { p in
            (place: Place(name: p.name, address: p.address, category: p.category, note: p.note, japaneseName: p.japaneseName), dayLabel: p.dayLabel)
        }
        let recommendations = result.recommendations.map { p in
            Place(name: p.name, address: p.address, category: p.category, japaneseName: p.japaneseName, isRecommendation: true, recommendationReason: p.note)
        }
        importedSummary = store.importItinerary(stops: stops, recommendations: recommendations, into: tripId, replaceExisting: replaceExisting)
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
