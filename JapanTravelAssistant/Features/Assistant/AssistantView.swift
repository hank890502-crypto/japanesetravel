import SwiftUI

/// 「我想問問題」：和 Apple 智慧對話。大字、大按鈕、可以唸給我聽。
struct AssistantView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var chat = AssistantChat()
    @State private var input = ""
    @State private var speakingId: UUID?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !chat.availability.isAvailable {
                            ErrorBanner(error: UserFacingError(title: "Apple 智慧目前無法使用", message: chat.availability.reason ?? "", isRetryable: false))
                        }

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
                    if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            inputBar
        }
        .elderlyScreen(title: "我想問問題")
    }

    // MARK: - 區塊

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
            }
            Text("小提醒：它沒有連網，今天的匯率、營業時間、價格請以現場或官網為準。")
                .font(.app(.caption))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.top, 8)
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(.app(.body))
                    .foregroundStyle(isUser ? .white : (message.isError ? AppColors.error : AppColors.primaryText))
                    .textSelection(.enabled)
                if !isUser, !message.isError, dependencies.speech.isAvailable {
                    Button {
                        Task { await speak(message) }
                    } label: {
                        Label(speakingId == message.id ? "播放中…" : "唸給我聽", systemImage: AppIcon.speak)
                            .font(.app(.caption).weight(.semibold))
                            .foregroundStyle(AppColors.accent)
                            .frame(minHeight: 44)
                    }
                    .disabled(speakingId != nil)
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
                        .background(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.isThinking ? AppColors.secondaryText : AppColors.accent, in: Circle())
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.isThinking)
                .accessibilityLabel("送出")
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

    // MARK: - Actions

    private func send() {
        let text = input
        input = ""
        Task { await chat.send(text) }
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
