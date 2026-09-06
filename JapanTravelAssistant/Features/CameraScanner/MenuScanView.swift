import PhotosUI
import SwiftUI

/// 拍菜單：文件掃描（自動裁切拉正）或選圖 → 自動辨識 → 進入檢查頁。也可以跳過拍照直接手動輸入。
struct MenuScanView: View {
    @Environment(AppRouter.self) private var router
    @Environment(MenuDraftStore.self) private var store
    @Environment(\.dependencies) private var dependencies

    @State private var viewModel: MenuScanViewModel?
    @State private var showDocumentScanner = false
    @State private var showCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var confirmDeleteDraft = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let viewModel, viewModel.phase == .recognizing {
                    recognizingView(viewModel)
                } else {
                    if let viewModel, case .failed(let error) = viewModel.phase {
                        ErrorBanner(error: error)
                    }

                    Text("把菜單放平、拍清楚，App 會自動整理成清單。菜單有兩面可以連續拍。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if DocumentCameraScanner.isSupported {
                        LargeActionCard(title: "拍菜單", subtitle: "打開相機，會自動對準菜單", systemImage: AppIcon.camera, tint: AppColors.understand) {
                            showDocumentScanner = true
                        }
                    } else if CameraPicker.isAvailable {
                        LargeActionCard(title: "拍菜單", subtitle: "打開相機", systemImage: AppIcon.camera, tint: AppColors.understand) {
                            showCamera = true
                        }
                    }

                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        LargeActionCardLabel(title: "從相簿選照片", subtitle: "已經拍好的菜單照片，可以選多張", systemImage: AppIcon.photoLibrary, tint: AppColors.understand)
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel("從相簿選照片")

                    LargeActionCard(title: "用 ChatGPT 翻譯菜單", subtitle: "翻譯品質最好，需要有 ChatGPT", systemImage: AppIcon.sparkles, tint: AppColors.go) {
                        router.push(.chatGPTImport)
                    }

                    if let draft = store.draft, !draft.items.isEmpty || !draft.otherLines.isEmpty {
                        LargeActionCard(
                            title: "繼續上次的菜單",
                            subtitle: "已有 \(draft.items.count) 道菜",
                            systemImage: AppIcon.restaurant,
                            tint: AppColors.talk
                        ) {
                            router.push(.menuReview)
                        }
                        Button(role: .destructive) {
                            confirmDeleteDraft = true
                        } label: {
                            Label("刪除上次的菜單", systemImage: AppIcon.delete)
                                .font(.app(.buttonLabel))
                                .foregroundStyle(AppColors.error)
                                .elderlyTapTarget()
                        }
                        .confirmationDialog("確定要刪除上次的菜單嗎？", isPresented: $confirmDeleteDraft, titleVisibility: .visible) {
                            Button("刪除", role: .destructive) { store.clear() }
                            Button("不要刪除", role: .cancel) {}
                        } message: {
                            Text("刪掉就找不回來了。")
                        }
                    }

                    SecondaryButton(title: "不拍照，直接手動輸入", systemImage: AppIcon.edit) {
                        store.startNew()
                        router.push(.menuReview)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "拍菜單")
        .onAppear {
            if viewModel == nil { viewModel = MenuScanViewModel(recognizer: dependencies.menuRecognizer) }
        }
        .fullScreenCover(isPresented: $showDocumentScanner) {
            DocumentCameraScanner(
                onScan: { images in
                    showDocumentScanner = false
                    Task { await handle(images) }
                },
                onCancel: { showDocumentScanner = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onImage: { image in
                    showCamera = false
                    Task { await handle([image]) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await loadAndHandle(newItems) }
        }
    }

    private func recognizingView(_ viewModel: MenuScanViewModel) -> some View {
        VStack(spacing: 20) {
            if let image = viewModel.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
            }
            ProgressView()
                .controlSize(.large)
            Text("正在辨識菜單文字，請稍等…")
                .font(.app(.sectionTitle))
                .foregroundStyle(AppColors.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func loadAndHandle(_ items: [PhotosPickerItem]) async {
        pickerItems = []
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { return }
        await handle(images)
    }

    private func handle(_ images: [UIImage]) async {
        guard let viewModel else { return }
        if await viewModel.process(images: images, into: store) {
            router.push(.menuReview)
        }
    }
}

#Preview {
    NavigationStack { MenuScanView() }
        .environment(AppRouter())
        .environment(MenuDraftStore(directory: nil))
        .environment(\.dependencies, .preview)
}
