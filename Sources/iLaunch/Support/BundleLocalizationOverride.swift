import Foundation
import ObjectiveC

/// Maps the app's language choice to the `.lproj` folder name a third-party
/// framework bundle (Sparkle) ships under, so its own alerts can be forced
/// into the right language. Pure and testable, kept separate from the
/// `Bundle` swizzle below.
///
/// `Bundle`'s own automatic locale resolution — used internally by any
/// `NSLocalizedString`-style lookup, including Sparkle's own update-check
/// alerts — does not honor the standard `AppleLanguages` UserDefaults
/// override for a bundle other than `Bundle.main` (verified empirically
/// against the real, signed, dyld-loaded `Sparkle.framework`: every
/// documented variant of the AppleLanguages trick — app-domain, Sparkle's
/// own bundle-ID domain, NSGlobalDomain, pre-set before launch — left
/// `Bundle.preferredLocalizations` stuck on "en" regardless of the real
/// system language). So "System" must independently determine the real
/// system language itself rather than relying on that broken resolution.
enum SparkleLocalizationFolder {
    static func folderName(for language: AppLanguage, systemLanguageCode: String) -> String? {
        switch language {
        case .chinese: return "zh_CN"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .russian: return "ru"
        case .english: return nil
        case .system:
            switch systemLanguageCode {
            case "zh": return "zh_CN"
            case "ja": return "ja"
            case "ko": return "ko"
            case "ru": return "ru"
            default: return nil
            }
        }
    }
}

extension Bundle {
    /// Method-swizzles `localizedString(forKey:value:table:)` process-wide
    /// so any bundle's lookup — ours or a third-party framework's — is
    /// forced through the `.lproj` folder matching the app's language
    /// choice, when one exists on that bundle. This is the standard,
    /// documented workaround for making a bundled framework like Sparkle
    /// follow an in-app language switch, since the simpler AppleLanguages
    /// override does not work here (see `SparkleLocalizationFolder` above).
    /// Safe process-wide: this app's own UI goes through the custom
    /// `Localizer.t(_:)` dictionary, not `NSLocalizedString`, so only
    /// third-party bundles are actually affected.
    private static let activateOnce: Void = {
        let originalSelector = #selector(Bundle.localizedString(forKey:value:table:))
        let swizzledSelector = #selector(Bundle.iLaunch_localizedString(forKey:value:table:))
        guard let originalMethod = class_getInstanceMethod(Bundle.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(Bundle.self, swizzledSelector) else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    static func activateLanguageOverride() {
        _ = activateOnce
    }

    @objc private func iLaunch_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let folder = Bundle.desiredLocalizationFolderName,
           let path = self.path(forResource: folder, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            // Falls through to the original (swapped-in) implementation on
            // languageBundle, since a leaf .lproj bundle has no nested
            // .lproj of its own to match — no infinite recursion.
            return languageBundle.iLaunch_localizedString(forKey: key, value: value, table: tableName)
        }
        // Calling the same selector here invokes the ORIGINAL
        // implementation, since method_exchangeImplementations swapped it
        // in under this selector's name.
        return self.iLaunch_localizedString(forKey: key, value: value, table: tableName)
    }

    private static var desiredLocalizationFolderName: String? {
        let systemCode = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        // Sparkle's alert string lookups happen on the main thread (AppKit
        // UI), same as this app's own Localizer usage — safe to assume.
        let currentLanguage = MainActor.assumeIsolated { Localizer.current }
        return SparkleLocalizationFolder.folderName(for: currentLanguage, systemLanguageCode: systemCode)
    }
}
