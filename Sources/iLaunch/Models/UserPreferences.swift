import Foundation
import CoreGraphics

struct UserPreferences: Codable, Equatable {
    enum OverlayDisplayMode: String, Codable, Equatable {
        case activeDisplay
        case mouseDisplay
        case allDisplays
    }

    enum AppIconStyle: String, Codable, Equatable, CaseIterable {
        case iconD = "D"
        case icon01 = "icon01"
        case icon02 = "icon02"
        case icon03 = "icon03"

        var displayName: String {
            switch self {
            case .iconD: return "默认 (D)"
            case .icon01: return "图标 1"
            case .icon02: return "图标 2"
            case .icon03: return "图标 3"
            }
        }

        var resourceName: String {
            switch self {
            case .iconD: return "iLaunch-D"
            case .icon01: return "icon01"
            case .icon02: return "icon02"
            case .icon03: return "icon03"
            }
        }

        /// 128×128 PNG thumbnail for the settings icon picker.
        var thumbnailName: String {
            switch self {
            case .iconD: return "thumb_iLaunch-D"
            case .icon01: return "thumb_icon01"
            case .icon02: return "thumb_icon02"
            case .icon03: return "thumb_icon03"
            }
        }
    }

    /// Background display mode for the overlay.
    enum BackgroundMode: String, Codable, Equatable {
        case desktop  // Show desktop background (transparent overlay)
        case uploaded // Use uploaded background images
    }

    /// Icon rendering size within a grid cell. Does not affect cell dimensions.
    enum IconSizeLevel: String, Codable, Equatable, CaseIterable {
        case small
        case medium
        case large

        var multiplier: CGFloat {
            switch self {
            case .small: return 0.715
            case .medium: return 0.88
            case .large: return 1.1
            }
        }
    }

    /// UI language preference.
    enum Language: String, Codable, Equatable, CaseIterable {
        case system  // Follow system language
        case chinese // Force Chinese
        case english // Force English
        case japanese // Force Japanese
        case korean // Force Korean
        case russian // Force Russian

        var displayName: String {
            switch self {
            case .system: return "跟随系统"
            case .chinese: return "简体中文"
            case .english: return "English"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            case .russian: return "Русский"
            }
        }
    }

    var hotKeyCode: UInt32
    var hotKeyModifiers: UInt32
    var launchAtLogin: Bool
    var showMenuBarIcon: Bool
    var showDockIcon: Bool
    var backgroundBlur: Double
    var reduceMotion: Bool
    var showSystemApplications: Bool
    var overlayDisplayMode: OverlayDisplayMode
    var scanDirectories: [String]
    var appIconStyle: AppIconStyle = .icon02

    // New fields for v1.3.0
    var language: Language = .system
    var backgroundMode: BackgroundMode = .desktop
    var backgroundImages: [String] = []  // File paths to uploaded background images
    var autoCarousel: Bool = false
    var animateIcons: Bool = true        // Icon fade-in / scale animation
    var animatePageFlip: Bool = true     // Page transition animation
    var animateFolder: Bool = true       // Folder expand/collapse animation
    var animateDrag: Bool = true         // Drag reposition animation
    var animateSearch: Bool = true       // Search results transition
    var showHiddenInSearch: Bool = true

    var gridRows: Int = 4          // 4/5/6 = fixed
    var gridColumns: Int = 7       // 6, 7, 8, 9, 10
    var iconSizeLevel: IconSizeLevel = .medium
    var showAppNames: Bool = true

    /// Whether DiagLog writes to disk. Default on so bug reports have
    /// evidence out of the box; users can turn it off in Settings > About.
    var diagLoggingEnabled: Bool = true

    /// Whether the launcher overlay's window fills the whole screen (so it
    /// draws over the Dock's screen area) or is sized to the visible frame
    /// (so the Dock stays on screen alongside the grid). Default on.
    var hideDockOnLaunch: Bool = true

    static let `default` = UserPreferences(
        hotKeyCode: 49,        // kVK_Space
        hotKeyModifiers: 2048, // Carbon optionKey
        launchAtLogin: false,
        showMenuBarIcon: true,
        showDockIcon: true,
        backgroundBlur: 0.72,
        reduceMotion: false,
        showSystemApplications: true,
        overlayDisplayMode: .activeDisplay,
        scanDirectories: [
            "/Applications",
            "~/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications"
        ],
        appIconStyle: .icon02
    )

    private enum CodingKeys: String, CodingKey {
        case hotKeyCode, hotKeyModifiers, launchAtLogin, showMenuBarIcon, showDockIcon
        case backgroundBlur, reduceMotion, showSystemApplications
        case overlayDisplayMode, scanDirectories, appIconStyle
        case language, backgroundMode, backgroundImages, autoCarousel
        case animateIcons, animatePageFlip, animateFolder, animateDrag, animateSearch
        case showHiddenInSearch
        case gridRows, gridColumns, iconSizeLevel, showAppNames
        case diagLoggingEnabled
        case hideDockOnLaunch
    }

    init(hotKeyCode: UInt32, hotKeyModifiers: UInt32, launchAtLogin: Bool, showMenuBarIcon: Bool, showDockIcon: Bool, backgroundBlur: Double, reduceMotion: Bool, showSystemApplications: Bool, overlayDisplayMode: OverlayDisplayMode, scanDirectories: [String], appIconStyle: AppIconStyle = .icon02, language: Language = .system, backgroundMode: BackgroundMode = .desktop, backgroundImages: [String] = [], autoCarousel: Bool = false, animateIcons: Bool = true, animatePageFlip: Bool = true, animateFolder: Bool = true, animateDrag: Bool = true, animateSearch: Bool = true, showHiddenInSearch: Bool = true, gridRows: Int = 4, gridColumns: Int = 7, iconSizeLevel: IconSizeLevel = .medium, showAppNames: Bool = true, diagLoggingEnabled: Bool = true, hideDockOnLaunch: Bool = true) {
        self.hotKeyCode = hotKeyCode
        self.hotKeyModifiers = hotKeyModifiers
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.showDockIcon = showDockIcon
        self.backgroundBlur = backgroundBlur
        self.reduceMotion = reduceMotion
        self.showSystemApplications = showSystemApplications
        self.overlayDisplayMode = overlayDisplayMode
        self.scanDirectories = scanDirectories
        self.appIconStyle = appIconStyle
        self.language = language
        self.backgroundMode = backgroundMode
        self.backgroundImages = backgroundImages
        self.autoCarousel = autoCarousel
        self.animateIcons = animateIcons
        self.animatePageFlip = animatePageFlip
        self.animateFolder = animateFolder
        self.animateDrag = animateDrag
        self.animateSearch = animateSearch
        self.showHiddenInSearch = showHiddenInSearch
        self.gridRows = gridRows
        self.gridColumns = gridColumns
        self.iconSizeLevel = iconSizeLevel
        self.showAppNames = showAppNames
        self.diagLoggingEnabled = diagLoggingEnabled
        self.hideDockOnLaunch = hideDockOnLaunch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotKeyCode = (try? c.decodeIfPresent(UInt32.self, forKey: .hotKeyCode)) ?? 49
        hotKeyModifiers = (try? c.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers)) ?? 2048
        launchAtLogin = try c.decode(Bool.self, forKey: .launchAtLogin)
        showMenuBarIcon = try c.decode(Bool.self, forKey: .showMenuBarIcon)
        showDockIcon = try c.decode(Bool.self, forKey: .showDockIcon)
        backgroundBlur = try c.decode(Double.self, forKey: .backgroundBlur)
        reduceMotion = try c.decode(Bool.self, forKey: .reduceMotion)
        showSystemApplications = try c.decode(Bool.self, forKey: .showSystemApplications)
        overlayDisplayMode = try c.decode(OverlayDisplayMode.self, forKey: .overlayDisplayMode)
        scanDirectories = try c.decode([String].self, forKey: .scanDirectories)
        appIconStyle = (try? c.decodeIfPresent(AppIconStyle.self, forKey: .appIconStyle)) ?? .icon02
        language = (try? c.decodeIfPresent(Language.self, forKey: .language)) ?? .system
        backgroundMode = (try? c.decodeIfPresent(BackgroundMode.self, forKey: .backgroundMode)) ?? .desktop
        backgroundImages = (try? c.decodeIfPresent([String].self, forKey: .backgroundImages)) ?? []
        autoCarousel = (try? c.decodeIfPresent(Bool.self, forKey: .autoCarousel)) ?? false
        animateIcons = (try? c.decodeIfPresent(Bool.self, forKey: .animateIcons)) ?? true
        animatePageFlip = (try? c.decodeIfPresent(Bool.self, forKey: .animatePageFlip)) ?? true
        animateFolder = (try? c.decodeIfPresent(Bool.self, forKey: .animateFolder)) ?? true
        animateDrag = (try? c.decodeIfPresent(Bool.self, forKey: .animateDrag)) ?? true
        animateSearch = (try? c.decodeIfPresent(Bool.self, forKey: .animateSearch)) ?? true
        showHiddenInSearch = (try? c.decodeIfPresent(Bool.self, forKey: .showHiddenInSearch)) ?? true
        gridRows = (try? c.decodeIfPresent(Int.self, forKey: .gridRows)) ?? 4
        gridColumns = (try? c.decodeIfPresent(Int.self, forKey: .gridColumns)) ?? 7
        iconSizeLevel = (try? c.decodeIfPresent(IconSizeLevel.self, forKey: .iconSizeLevel)) ?? .medium
        showAppNames = (try? c.decodeIfPresent(Bool.self, forKey: .showAppNames)) ?? true
        diagLoggingEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .diagLoggingEnabled)) ?? true
        hideDockOnLaunch = (try? c.decodeIfPresent(Bool.self, forKey: .hideDockOnLaunch)) ?? true
    }
}
