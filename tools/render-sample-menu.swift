// 在 Mac 上畫一張兩欄的測試菜單圖：swift tools/render-sample-menu.swift samples/example-rendered-menu.png
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "sample-menu.png"
let size = NSSize(width: 1400, height: 900)
let image = NSImage(size: size)
image.lockFocus()
NSColor(white: 0.97, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
let title: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 60), .foregroundColor: NSColor.black]
let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44, weight: .medium), .foregroundColor: NSColor.black]
func draw(_ text: String, x: CGFloat, yFromTop: CGFloat, _ attributes: [NSAttributedString.Key: Any]) {
    let string = NSAttributedString(string: text, attributes: attributes)
    string.draw(at: NSPoint(x: x, y: size.height - yFromTop - string.size().height))
}
draw("居酒屋 酒津屋", x: 480, yFromTop: 40, title)
let left: [(String, String)] = [("揚げ物", ""), ("若どり唐揚げ", "¥540"), ("手羽先", "430円"), ("味噌串カツ", "¥540")]
let right: [(String, String)] = [("焼き物", ""), ("ねぎま", "180円"), ("つくね", "¥200"), ("生ビール", "¥650")]
for (index, row) in left.enumerated() {
    draw(row.0, x: 60, yFromTop: CGFloat(180 + index * 110), body)
    draw(row.1, x: 520, yFromTop: CGFloat(180 + index * 110), body)
}
for (index, row) in right.enumerated() {
    draw(row.0, x: 760, yFromTop: CGFloat(180 + index * 110), body)
    draw(row.1, x: 1200, yFromTop: CGFloat(180 + index * 110), body)
}
draw("※価格は税込です", x: 60, yFromTop: 780, body)
image.unlockFocus()
let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
print("寫入 \(output)")
