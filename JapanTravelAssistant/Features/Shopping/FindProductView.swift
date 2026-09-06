import PhotosUI
import SwiftUI

/// 找商品：從相簿選一張照片 → 選一個問題 → 照片 + 日文一起給店員看。
struct FindProductView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var dependencies

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var isLoadingImage = false
    @State private var questions: [Phrase] = []
    @State private var error: UserFacingError?
    @State private var showAIUnavailable = false
    @State private var isAnalyzing = false
    @State private var analysis: ProductAnalysis?

    /// 找商品時最常用的問題（來自 phrases.json 的購物分類）。
    private let questionIds = ["shop-have-this", "shop-where", "shop-stock", "shop-size", "shop-color", "shop-price"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error {
                    ErrorBanner(error: error)
                }

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                        .accessibilityLabel("你選的商品照片")

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ChangePhotoLabel()
                    }

                    SecondaryButton(title: isAnalyzing ? "AI 辨識中…" : "AI 幫我認這個商品", systemImage: "wand.and.stars", isEnabled: !isAnalyzing) {
                        Task { await analyze(image) }
                    }
                    if showAIUnavailable {
                        AIUnavailableBanner()
                    }
                    if let analysis {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(analysis.chineseName ?? analysis.productName ?? "看不出是什麼商品")
                                .font(.app(.cardTitle))
                            if let name = analysis.productName, analysis.chineseName != nil {
                                Text(name).font(.app(.japanese)).foregroundStyle(AppColors.secondaryText)
                            }
                            if let price = analysis.price, let text = PriceFormatter.string(price) {
                                Text("參考價格 \(text)").font(.app(.body))
                            }
                            if let notes = analysis.notes?.nilIfBlank {
                                Text(notes).font(.app(.caption)).foregroundStyle(AppColors.secondaryText)
                            }
                        }
                        .padding(AccessibilityMetrics.screenPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                    }

                    Text("接下來，選一個想問店員的問題：")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    ForEach(questions) { phrase in
                        JapanesePhraseCard(phrase: phrase) {
                            router.showToStaff(StaffDisplayContent(phrase: phrase, image: image))
                        }
                    }
                } else {
                    Text("先從相簿選一張商品的照片，接著就可以拿給店員看，並問他有沒有這個商品。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let isLoading = isLoadingImage
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        PickPhotoLabel(isLoading: isLoading)
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel("從相簿選照片")
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "找商品")
        .task {
            questions = (try? await dependencies.phrases.phrases(ids: questionIds)) ?? []
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadImage(from: newItem) }
        }
    }

    private func analyze(_ image: UIImage) async {
        guard dependencies.ai.isEnabled else {
            withAnimation { showAIUnavailable = true }
            return
        }
        showAIUnavailable = false
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            analysis = try await dependencies.ai.analyzeProduct(image: image)
            error = nil
        } catch {
            self.error = UserFacingError.from(error)
        }
    }

    private func loadImage(from item: PhotosPickerItem) async {
        isLoadingImage = true
        defer { isLoadingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let loaded = UIImage(data: data)
            else {
                error = UserFacingError(title: "無法讀取這張照片", message: "請換一張照片試試看。")
                return
            }
            image = loaded.downscaled(maxDimension: 1600)
            error = nil
        } catch {
            self.error = UserFacingError(title: "無法讀取這張照片", message: "請換一張照片試試看。")
        }
    }
}

/// PhotosPicker 的 label 是獨立的 View，避免在 Sendable closure 裡引用 MainActor 屬性。
private struct ChangePhotoLabel: View {
    var body: some View {
        Label("換一張照片", systemImage: AppIcon.photoLibrary)
            .font(.app(.buttonLabel))
            .foregroundStyle(AppColors.accent)
            .elderlyTapTarget()
    }
}

private struct PickPhotoLabel: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: AppIcon.photoLibrary)
            }
            Text(isLoading ? "讀取照片中…" : "從相簿選照片")
        }
        .font(.app(.buttonLabel))
        .foregroundStyle(.white)
        .elderlyTapTarget()
        .padding(.horizontal, 16)
        .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    NavigationStack { FindProductView() }
        .environment(AppRouter())
        .environment(\.dependencies, .preview)
}
