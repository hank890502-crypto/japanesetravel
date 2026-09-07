import UIKit

/// 我們用自訂的頂部列並隱藏了系統導覽列，iOS 會順便關掉「從左邊滑回上一頁」的手勢。
/// 這裡把手勢接回來：只要不是在第一頁，就可以側滑返回。
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
