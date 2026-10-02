import AppKit
import FreeShotCore
import Vision

/// Text recognition with Vision. `recognize` also copies the text and shows a toast,
/// so a caller only needs to pass the cropped image.
final class OCRController: OCRModule {
    func recognize(_ image: CGImage) async -> String {
        let text = await Self.recognizeText(in: image)
        await MainActor.run {
            if !text.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
            Toast.show(OCRTextAssembler.toastMessage(for: text),
                       symbol: text.isEmpty ? "text.magnifyingglass" : "doc.on.clipboard.fill")
        }
        return text
    }

    /// Recognition only: no clipboard, no toast. Accurate level, language correction on.
    static func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    let lines = (request.results ?? []).compactMap { obs -> OCRLine? in
                        guard let top = obs.topCandidates(1).first else { return nil }
                        return OCRLine(text: top.string, box: obs.boundingBox)
                    }
                    cont.resume(returning: OCRTextAssembler.assemble(lines))
                } catch {
                    FileHandle.standardError.write("FreeShot OCR: \(error)\n".data(using: .utf8)!)
                    cont.resume(returning: "")
                }
            }
        }
    }
}
