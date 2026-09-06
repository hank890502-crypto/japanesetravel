// 畫一張「直排 + 漢數字價格」的測試菜單：swift tools/render-vertical-menu.swift samples/example-vertical-menu.png
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "vertical.png"
let size = NSSize(width: 1400, height: 1000)
let image = NSImage(size: size)
image.lockFocus()
NSColor(white: 0.96, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
let font = NSFont(name: "HiraMinProN-W6", size: 48) ?? NSFont.systemFont(ofSize: 48, weight: .semibold)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]

/// 一個字一個字往下畫（直排）
func drawVertical(_ text: String, x: CGFloat, topY: CGFloat) {
    var y = topY
    for char in text {
        let s = NSAttributedString(string: String(char), attributes: attrs)
        let w = s.size().width
        s.draw(at: NSPoint(x: x - w / 2, y: size.height - y - s.size().height))
        y += 54
    }
}

let columns: [(String, String)] = [
    ("味噌串カツ定食", "八四〇円"),
    ("エビカツ定食", "九七〇円"),
    ("みそカツ丼（大）", "一一五〇円"),
    ("トンカツ定食", "一一五〇円"),
    ("味噌トンカツ定食", "一一五〇円"),
    ("焼きそば", "五四〇円"),
    ("お好み焼き", "四八〇円"),
    ("ライス（小）", "一八〇円"),
]
// 由右到左排欄（日文直排習慣）
for (index, column) in columns.enumerated() {
    let x = size.width - 100 - CGFloat(index) * 150
    drawVertical(column.0, x: x, topY: 80)
    drawVertical(column.1, x: x, topY: 640)
}
image.unlockFocus()
let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
print("寫入 \(output)")
