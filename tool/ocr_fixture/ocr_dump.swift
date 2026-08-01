// Mirrors the Vision code in macos/Runner/MainFlutterWindow.swift so the real
// recogniser output can be captured and replayed against the Dart parser.
import AppKit
import Foundation
import Vision

let path = CommandLine.arguments[1]
guard
  let image = NSImage(contentsOfFile: path),
  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
  FileHandle.standardError.write("could not open \(path)\n".data(using: .utf8)!)
  exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

var words: [[String: Any]] = []
for observation in request.results ?? [] {
  guard let candidate = observation.topCandidates(1).first else { continue }
  let text = candidate.string
  var cursor = text.startIndex
  for token in text.split(separator: " ", omittingEmptySubsequences: true) {
    guard
      let range = text.range(
        of: String(token), options: [], range: cursor..<text.endIndex),
      let box = try? candidate.boundingBox(for: range)
    else { continue }
    cursor = range.upperBound
    let rect = box.boundingBox
    words.append([
      "text": String(token),
      "left": rect.minX,
      "top": 1 - rect.maxY,
      "right": rect.maxX,
      "bottom": 1 - rect.minY,
    ])
  }
}

let data = try JSONSerialization.data(
  withJSONObject: words, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
