import Foundation

/// Languages used for clipboard image OCR recognition.
enum OCRLanguage: String, CaseIterable, Identifiable, Codable {
    /// English only (fastest).
    case english
    /// Simplified Chinese + English.
    case chineseEnglish
    /// Let the system auto-detect using all supported Vision languages.
    case auto

    var id: String { rawValue }

    static var `default`: OCRLanguage { .chineseEnglish }

    /// BCP-47 language tags passed to `VNRecognizeTextRequest.recognitionLanguages`.
    var recognitionLanguages: [String] {
        switch self {
        case .english: return ["en-US"]
        case .chineseEnglish: return ["zh-Hans", "zh-Hans-CN", "en-US"]
        case .auto: return []
        }
    }

    func displayName() -> String {
        switch self {
        case .english: return L10n.t(.screenshotOCRLanguageEnglish)
        case .chineseEnglish: return L10n.t(.screenshotOCRLanguageChineseEnglish)
        case .auto: return L10n.t(.screenshotOCRLanguageAuto)
        }
    }
}

typealias ScreenshotOCRLanguage = OCRLanguage
