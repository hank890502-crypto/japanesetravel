// 用法（在專案根目錄）：tools/ocr-debug.sh samples/menu1.jpg
// 跟 App 一樣：先用 Live Text（VisionKit）依閱讀順序解析；另外印出 Vision 的結果做對照。
import AppKit
import Foundation
import Vision
import VisionKit

setbuf(stdout, nil)
guard let path = CommandLine.arguments.dropFirst().first else {
    print("請給我一張圖片路徑")
    exit(1)
}
guard let nsImage = NSImage(contentsOfFile: path),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("讀不到圖片：\(path)")
    exit(1)
}

Task { @MainActor in
    let analyzer = ImageAnalyzer()
    let analysis = try await analyzer.analyze(cgImage, orientation: .up, configuration: ImageAnalyzer.Configuration([.text]))
    let lines = analysis.transcript.components(separatedBy: "\n")
    print("===== Live Text 讀到的文字（\(lines.count) 行，依閱讀順序）=====")
    for line in lines { print(line) }

    let result = MenuTranscriptParser.parse(lines: lines)
    print("\n===== 菜（\(result.items.count)）=====")
    for item in result.items {
        print("\(item.name)  ¥\(item.price.map { "\($0)" } ?? "?")")
    }
    print("\n===== 其他文字（\(result.otherLines.count)）=====")
    for line in result.otherLines { print(line.name) }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
    let blocks = (request.results ?? []).compactMap { o -> RecognizedTextBlock? in
        guard let c = o.topCandidates(1).first else { return nil }
        return RecognizedTextBlock(text: c.string, confidence: Double(c.confidence), boundingBox: o.boundingBox)
    }
    print("\n===== 對照：Vision 文字塊（\(blocks.count)）=====")
    for b in blocks.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) { print(b.text) }
    exit(0)
}
RunLoop.main.run()
