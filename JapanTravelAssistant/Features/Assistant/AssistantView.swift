import SwiftUI

/// 「我想問問題」：和 Apple 智慧對話。大字、大按鈕、可以唸給我聽。
/// 這台裝置不能用時，整頁只顯示說明卡（為什麼不能用、可以改用什麼），不會出現輸入框。
struct AssistantView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var dependencies
    @State private var chat = AssistantChat()
    @State private var input = ""
    @State private var speakingId: UUID?
    /// 助手還在想的時候按了送出：文字留在輸入框，並顯示這個提示
    @State private var showWaitHint = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if chat.availability.isAvailable {
                chatView
            } else {
                unavailableView
            }
        }
        .elderlyScreen(title: "我想問問題")
        .onDisappear {
            // 離開這一頁就停止朗讀，不然回到首頁聲音還在講
            Task { await dependencies.speech.stop() }
        }
    }

    // MARK: - 可以用：對話畫面

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if chat.messages.isEmpty {
                            intro
                        }

                        ForEach(chat.messages) { message in
                            bubble(message).id(message.id)
                        }

                        if chat.isThinking {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("想一下…").font(.app(.body)).foregroundStyle(AppColors.secondaryText)
                            }
                            .id("thinking")
                        }
                    }
                    .padding(AccessibilityMetrics.screenPadding)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(chat.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: chat.isThinking) { _, thinking in
                    if thinking {
                        withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                    } else {
                        showWaitHint = false
                    }
                }
            }
            inputBar
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可以問我日本旅遊、商品、餐廳、交通的事。用說的也可以：按鍵盤上的麥克風。")
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)
            Text("常見問題，點一下就問：")
                .font(.app(.caption))
                .foregroundStyle(AppColors.secondaryText)
            ForEach(AssistantChat.suggestions, id: \.self) { question in
                Button {
                    Task { await chat.send(question) }
                } label: {
                    Text(question)
                        .font(.app(.body))
                        .foregroundStyle(AppColors.accent)
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget, alignment: .leading)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(CardPressStyle())
                .disabled(chat.isThinking)
            }
            Text("小提醒：它沒有連網，今天的匯率、營業時間、價格請以現場或官網為準。")
                .font(.app(.caption))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.top, 8)
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        let isSpeakingThis = speakingId == message.id
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(.app(.body))
                    .foregroundStyle(isUser ? .white : (message.isError ? AppColors.error : AppColors.primaryText))
                    .textSelection(.enabled)
                if !isUser, !message.isError, dependencies.speech.isAvailable {
                    if isSpeakingThis {
                        // 播放中：一定要有辦法停下來
                        Button {
                            Task { await dependencies.speech.stop() }
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                                .font(.app(.caption).weight(.semibold))
                                .foregroundStyle(AppColors.error)
                                .frame(minHeight: 44)
                        }
                        .accessibilityLabel("停止朗讀")
                    } else {
                        Button {
                            Task { await speak(message) }
                        } label: {
                            Label("唸給我聽", systemImage: AppIcon.speak)
                                .font(.app(.caption).weight(.semibold))
                                .foregroundStyle(speakingId == nil ? AppColors.accent : AppColors.secondaryText)
                                .frame(minHeight: 44)
                        }
                        .disabled(speakingId != nil)
                    }
                }
            }
            .padding(16)
            .background(isUser ? AppColors.accent : AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "我" : "助手")：\(message.text)")
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("想問什麼？也可以按麥克風說", text: $input, axis: .vertical)
                    .font(.app(.body))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .padding(14)
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(inputFocused ? AppColors.accent : AppColors.separator, lineWidth: 2))
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: AccessibilityMetrics.minimumTapTarget, height: AccessibilityMetrics.minimumTapTarget)
                        .background(canSend ? AppColors.accent : AppColors.secondaryText, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("送出")
            }
            if showWaitHint && chat.isThinking {
                Label("等我回答完再送，你打的字還留著。", systemImage: "hourglass")
                    .font(.app(.caption))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !chat.messages.isEmpty {
                Button("重新開始對話") { chat.reset() }
                    .font(.app(.caption))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(minHeight: 40)
            }
        }
        .padding(.horizontal, AccessibilityMetrics.screenPadding)
        .padding(.vertical, 10)
        .background(AppColors.screenBackground)
    }

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmedInput.isEmpty && !chat.isThinking }

    // MARK: - 不能用：說明卡

    private var unavailableView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "questionmark.bubble")
                            .font(.app(.cardTitle))
                            .foregroundStyle(AppColors.secondaryText)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("這台手機不能用「我想問問題」")
                                .font(.app(.cardTitle))
                                .foregroundStyle(AppColors.primaryText)
                            Text(chat.availability.reason ?? "目前無法使用 Apple 智慧。")
                                .font(.app(.body))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    Text("這個功能是用手機裡的 Apple 智慧來回答，不是這個 App 壞掉。其他功能都可以照常使用。")
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .padding(AccessibilityMetrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                .accessibilityElement(children: .combine)

                Text("你可以改用：")
                    .font(.app(.sectionTitle))
                    .accessibilityAddTraits(.isHeader)

                LargeActionCard(title: "我要跟人說話", subtitle: "飯店、餐廳、購物常用的日文句子，點一下就能給店員看", systemImage: AppIcon.talk, tint: AppColors.talk) {
                    router.push(.communicationCategories)
                }
                LargeActionCard(title: "用 ChatGPT 問問題", subtitle: "打開 ChatGPT，用中文問它日本旅遊的事（需要網路）", systemImage: AppIcon.sparkles, tint: AppColors.go) {
                    ExternalApps.openChatGPT()
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
    }

    // MARK: - Actions

    private func send() {
        let text = trimmedInput
        guard !text.isEmpty else { return }
        guard !chat.isThinking else {
            // 還在想：文字留在輸入框，提示一下，等回答完再送
            withAnimation { showWaitHint = true }
            return
        }
        input = ""
        Task {
            if await !chat.send(text) {
                // 沒被接受（極少見）：把字還給輸入框，不要無聲吞掉
                input = text
            }
        }
    }

    private func speak(_ message: ChatMessage) async {
        speakingId = message.id
        await dependencies.speech.speak(message.text, language: .traditionalChinese)
        speakingId = nil
    }
}

#Preview {
    NavigationStack { AssistantView() }
        .environment(AppRouter())
        .environment(\.dependencies, .preview)
}
