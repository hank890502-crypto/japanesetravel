import SwiftUI

extension View {
    /// 鍵盤上方加一顆大字「完成」。數字鍵盤沒有 return 鍵，長輩常常不知道怎麼把鍵盤收起來；
    /// 一般鍵盤也一起加，全 App 收鍵盤的方式才一致。
    /// 用法：`.keyboardDoneButton { focusedField = nil }`
    func keyboardDoneButton(action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(action: action) {
                    Text("完成")
                        .font(.app(.buttonLabel))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("完成，收起鍵盤")
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var price = ""
        @FocusState private var focused: Bool
        var body: some View {
            VStack {
                TextField("價格", text: $price)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .padding()
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
            }
            .padding()
            .keyboardDoneButton { focused = false }
        }
    }
    return Demo()
}
