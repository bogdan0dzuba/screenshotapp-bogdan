import CoreGraphics
import ScreenshotCore
import Vision

enum OCRService {
    static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(
                text: candidate.string,
                minX: observation.boundingBox.minX,
                midY: observation.boundingBox.midY
            )
        }
        return OCRTextFormatter.join(lines: lines)
    }
}
