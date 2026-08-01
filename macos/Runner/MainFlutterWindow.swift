import Cocoa
import FlutterMacOS
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // ML Kit has no macOS build, so the Mac app reads timetable photos with
    // Vision instead. The Dart side treats both backends identically: a list
    // of words with boxes normalised to 0…1, origin top-left.
    let channel = FlutterMethodChannel(
      name: "attendance_tracker/ocr",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognise" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(
          FlutterError(
            code: "bad_arguments",
            message: "A file path is required.",
            details: nil))
        return
      }
      TimetableTextReader.recognise(path: path, result: result)
    }

    super.awakeFromNib()
  }
}

enum TimetableTextReader {
  static func recognise(path: String, result: @escaping FlutterResult) {
    guard
      let image = NSImage(contentsOfFile: path),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      result(
        FlutterError(
          code: "decode_failed",
          message: "That image could not be opened.",
          details: nil))
      return
    }

    // Vision runs synchronously on a background queue, so `result` is
    // delivered exactly once however the request ends.
    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      // Course codes such as "EE301" are not words; language correction only
      // damages them.
      request.usesLanguageCorrection = false

      do {
        try VNImageRequestHandler(cgImage: cgImage, options: [:])
          .perform([request])
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ocr_failed",
              message: error.localizedDescription,
              details: nil))
        }
        return
      }

      var words: [[String: Any]] = []
      for observation in request.results ?? [] {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let text = candidate.string
        var cursor = text.startIndex
        // Vision reports whole lines; asking for the box of each word keeps
        // the geometry the grid parser depends on.
        for token in text.split(separator: " ", omittingEmptySubsequences: true) {
          guard
            let range = text.range(
              of: String(token), options: [], range: cursor..<text.endIndex),
            let box = try? candidate.boundingBox(for: range)
          else { continue }
          cursor = range.upperBound
          // Vision's origin is bottom-left; the parser expects top-left.
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
      DispatchQueue.main.async { result(words) }
    }
  }
}
