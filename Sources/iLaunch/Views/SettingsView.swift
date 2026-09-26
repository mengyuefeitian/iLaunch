import SwiftUI
import UniformTypeIdentifiers

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, interface, appManagement, logs, about

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .general: return "settings.general"
        case .interface: return "settings.interface"
        case .appManagement: return "settings.appManagement"
        case .logs: return "settings.logs"
        case .about: return "settings.about"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .interface: return "paintbrush"
        case .appManagement: return "square.grid.2x2"
        case .logs: return "doc.text.magnifyingglass"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var preferences = UserPreferences.default
    @State private var selectedCategory: SettingsCategory? = .general
    @State private var languageVersion = 0
    private let preferencesStore = PreferencesStore()
    weak var viewModel: LaunchpadViewModel?
    weak var hotKeyManager: GlobalHotKeyManager?

    var body: some View {
        NavigationSplitView {
            // `List(_:selection:)` + `.tag()` used to drive this sidebar, but
            // its native row-selection tracking could desync from
            // `selectedCategory` — clicking a row sometimes left the sidebar
            // highlighting one category while the detail pane rendered a
            // different one's content, and stuck that way until a further
            // click (observed on multiple builds, independent of any recent
            // Settings changes — reverting those didn't fix it). Selection is
            // driven directly by Button taps here instead, so there is only
            // ever one source of truth for which category is selected.
            //
            // Still wrapping the buttons in `List` (even unselected) left a
            // residual "click 2-3 times to register" lag: on macOS `List` is
            // backed by NSTableView, whose row views intercept the first
            // click for their own hit-testing/tracking machinery before
            // forwarding to a plain-style Button inside — a known AppKit
            // interop quirk independent of the `selection:` binding. Plain
            // `ScrollView` + `VStack` has no such row layer, so every click
            // reaches the Button on the first try.
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(SettingsCategory.allCases) { category in
                        let isSelected = selectedCategory == category
                        Button {
                            selectedCategory = category
                        } label: {
                            Label(Localizer.t(category.localizationKey), systemImage: category.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                }
                .padding(8)
            }
            .background(.regularMaterial)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
        } detail: {
            switch selectedCategory {
            case .general:
                GeneralSettingsView(preferences: $preferences, hotKeyManager: hotKeyManager, onSave: savePreferences)
            case .interface:
                AppearanceSettingsView(preferences: $preferences, onSave: savePreferences)
            case .appManagement:
                AppManagementSettingsView(preferences: $preferences, viewModel: viewModel, onSave: savePreferences)
            case .logs:
                LogManagementSettingsView(preferences: $preferences, onSave: savePreferences)
            case .about:
                AboutView(preferences: preferences)
            case nil:
                Text("")
            }
        }
        .id(languageVersion)
        // The hosting window uses `.fullSizeContentView` so NavigationSplitView's
        // toolbar scroll-edge effect lands correctly under the titlebar (see
        // SettingsWindowController). That makes the hosting view taller than
        // the window's nominal content size by the titlebar/toolbar height,
        // and that extra height isn't a fixed constant — it varies with the
        // OS version, window subtitle, and accessibility text size. Rather
        // than hardcode it, use a flexible frame with contentSize as the
        // minimum so the root always grows to fill whatever the hosting view
        // actually is, with no empty strips top or bottom.
        .frame(
            minWidth: SettingsWindowController.contentSize.width,
            maxWidth: .infinity,
            minHeight: SettingsWindowController.contentSize.height,
            maxHeight: .infinity
        )
        .onAppear {
            preferences = (try? preferencesStore.load()) ?? .default
            Localizer.setLanguage(preferences.language)
        }
        .onChange(of: preferences.language) { _, newLang in
            Localizer.setLanguage(newLang)
            savePreferences()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchLanguageChanged)) { _ in
            languageVersion += 1
        }
    }

    private func savePreferences() {
        DiagLog.configure(enabled: preferences.diagLoggingEnabled)
        do {
            try preferencesStore.save(preferences)
            DiagLog.write("preferences saved OK, showSystemApps=\(preferences.showSystemApplications)")
        } catch {
            DiagLog.write("preferences SAVE FAILED: \(error)")
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Binding var preferences: UserPreferences
    weak var hotKeyManager: GlobalHotKeyManager?
    let onSave: () -> Void

    var body: some View {
        Form {
            Section(Localizer.t("settings.language")) {
                Picker(Localizer.t("settings.languagePicker"), selection: $preferences.language) {
                    ForEach(UserPreferences.Language.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section(Localizer.t("settings.animations")) {
                Toggle(Localizer.t("settings.animateIcons"), isOn: $preferences.animateIcons)
                Toggle(Localizer.t("settings.animatePageFlip"), isOn: $preferences.animatePageFlip)
                Toggle(Localizer.t("settings.animateFolder"), isOn: $preferences.animateFolder)
                Toggle(Localizer.t("settings.animateDrag"), isOn: $preferences.animateDrag)
                Toggle(Localizer.t("settings.animateSearch"), isOn: $preferences.animateSearch)
            }

            Section(Localizer.t("settings.launch")) {
                HotKeyRecorderRow(
                    keyCode: $preferences.hotKeyCode,
                    modifiers: $preferences.hotKeyModifiers,
                    hotKeyManager: hotKeyManager,
                    onCommitted: onSave
                )
                Toggle(Localizer.t("settings.launchAtLogin"), isOn: $preferences.launchAtLogin)
                Toggle(Localizer.t("settings.showMenuBarIcon"), isOn: $preferences.showMenuBarIcon)
                Toggle(Localizer.t("settings.showDockIcon"), isOn: $preferences.showDockIcon)
                Toggle(Localizer.t("settings.coverDock"), isOn: $preferences.coverDock)
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.launchAtLogin) { _, newValue in
            LoginItemService.apply(newValue)
            onSave()
        }
        .onChange(of: preferences.showMenuBarIcon) { _, _ in onSave() }
        .onChange(of: preferences.showDockIcon) { _, _ in onSave() }
        .onChange(of: preferences.coverDock) { _, _ in onSave() }
        .onChange(of: preferences.animateIcons) { _, _ in onSave() }
        .onChange(of: preferences.animatePageFlip) { _, _ in onSave() }
        .onChange(of: preferences.animateFolder) { _, _ in onSave() }
        .onChange(of: preferences.animateDrag) { _, _ in onSave() }
        .onChange(of: preferences.animateSearch) { _, _ in onSave() }
    }
}

// MARK: - Log Management

struct LogManagementSettingsView: View {
    @Binding var preferences: UserPreferences
    let onSave: () -> Void

    var body: some View {
        Form {
            Section(Localizer.t("about.diagnostics")) {
                Toggle(Localizer.t("about.diagnosticsToggle"), isOn: $preferences.diagLoggingEnabled)
                Text(Localizer.t("about.diagnosticsHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(Localizer.t("about.openLogFolder")) {
                    if let url = DiagLog.logFileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.diagLoggingEnabled) { _, newValue in
            DiagLog.configure(enabled: newValue)
            onSave()
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @Binding var preferences: UserPreferences
    let onSave: () -> Void

    var body: some View {
        Form {
            Section(Localizer.t("settings.appearance")) {
                Slider(value: $preferences.backgroundBlur, in: 0...1) {
                    Text(Localizer.t("settings.backgroundBlur"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(Localizer.t("settings.appIcon")).font(.headline)
                    HStack(spacing: 12) {
                        ForEach(UserPreferences.AppIconStyle.allCases, id: \.self) { style in
                            IconThumbnailView(
                                style: style,
                                isSelected: preferences.appIconStyle == style
                            )
                            .onTapGesture {
                                preferences.appIconStyle = style
                                IconSwitcher.apply(style)
                                onSave()
                                NotificationCenter.default.post(
                                    name: .iLaunchIconChanged,
                                    object: style.rawValue
                                )
                            }
                        }
                    }
                }
            }

            Section(Localizer.t("settings.layout")) {
                Picker(Localizer.t("settings.gridRows"), selection: $preferences.gridRows) {
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("6").tag(6)
                }
                .pickerStyle(.segmented)

                Picker(Localizer.t("settings.gridColumns"), selection: $preferences.gridColumns) {
                    Text("6").tag(6)
                    Text("7").tag(7)
                    Text("8").tag(8)
                    Text("9").tag(9)
                    Text("10").tag(10)
                }
                .pickerStyle(.segmented)
            }

            Section(Localizer.t("settings.iconSize")) {
                Picker(Localizer.t("settings.iconSize"), selection: $preferences.iconSizeLevel) {
                    Text(Localizer.t("settings.iconSizeSmall")).tag(UserPreferences.IconSizeLevel.small)
                    Text(Localizer.t("settings.iconSizeMedium")).tag(UserPreferences.IconSizeLevel.medium)
                    Text(Localizer.t("settings.iconSizeLarge")).tag(UserPreferences.IconSizeLevel.large)
                }
                .pickerStyle(.segmented)

                Toggle(Localizer.t("settings.showAppNames"), isOn: $preferences.showAppNames)
            }

            Section(Localizer.t("settings.background")) {
                Picker(Localizer.t("settings.backgroundMode"), selection: $preferences.backgroundMode) {
                    Text(Localizer.t("settings.showDesktop")).tag(UserPreferences.BackgroundMode.desktop)
                    Text(Localizer.t("settings.uploadBackground")).tag(UserPreferences.BackgroundMode.uploaded)
                }
                .pickerStyle(.segmented)

                if preferences.backgroundMode == .uploaded {
                    BackgroundImagePicker(
                        images: $preferences.backgroundImages,
                        onSave: onSave
                    )
                    if preferences.backgroundImages.count >= 2 {
                        Toggle(Localizer.t("settings.autoCarousel"), isOn: $preferences.autoCarousel)
                        Text(preferences.autoCarousel
                             ? Localizer.t("settings.carouselHint")
                             : Localizer.t("settings.firstImageHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.backgroundBlur) { _, _ in onSave() }
        .onChange(of: preferences.backgroundMode) { _, _ in onSave() }
        .onChange(of: preferences.autoCarousel) { _, _ in onSave() }
        .onChange(of: preferences.gridRows) { _, _ in
            onSave()
            NotificationCenter.default.post(name: .iLaunchGridSettingsChanged, object: nil)
        }
        .onChange(of: preferences.gridColumns) { _, _ in
            onSave()
            NotificationCenter.default.post(name: .iLaunchGridSettingsChanged, object: nil)
        }
        .onChange(of: preferences.iconSizeLevel) { _, _ in onSave() }
        .onChange(of: preferences.showAppNames) { _, _ in onSave() }
    }
}

// MARK: - App Management Settings

struct AppManagementSettingsView: View {
    @Binding var preferences: UserPreferences
    weak var viewModel: LaunchpadViewModel?
    let onSave: () -> Void

    var body: some View {
        Form {
            Section(Localizer.t("settings.systemApps")) {
                Toggle(Localizer.t("settings.showSystemApps"), isOn: $preferences.showSystemApplications)
            }

            Section(Localizer.t("settings.hiddenApps")) {
                Toggle(Localizer.t("settings.showHiddenInSearch"), isOn: $preferences.showHiddenInSearch)

                if let vm = viewModel, !vm.hiddenApps.isEmpty {
                    ForEach(vm.hiddenApps) { record in
                        HStack {
                            AppIconSmall(record: record)
                            Text(record.name)
                            Spacer()
                            Button(Localizer.t("menu.unhide")) {
                                viewModel?.unhideApp(id: record.id)
                                onSave()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else {
                    Text(Localizer.t("settings.noHiddenApps"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.showSystemApplications) { _, newValue in
            DiagLog.write("showSystemApplications toggled to \(newValue), viewModel is \(viewModel == nil ? "nil" : "valid")")
            viewModel?.showSystemApplications = newValue
            onSave()
        }
        .onChange(of: preferences.showHiddenInSearch) { _, newValue in
            DiagLog.write("showHiddenInSearch toggled to \(newValue), viewModel is \(viewModel == nil ? "nil" : "valid")")
            viewModel?.showHiddenInSearch = newValue
            onSave()
        }
    }
}

// MARK: - About View

struct AboutView: View {
    let preferences: UserPreferences
    @State private var showCopied = false

    private static let githubURLString = "https://github.com/mengyuefeitian/iLaunch"

    private var appIcon: NSImage? {
        IconThumbnailCache.image(named: preferences.appIconStyle.resourceName)
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Group {
                if let img = appIcon {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 4)

            Text("iLaunch")
                .font(.title2.weight(.semibold))

            Text("\(Localizer.t("about.version")) \(versionString)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                linkRow(label: Localizer.t("about.website"), value: "www.xiaoanhome.xyz") {
                    NSWorkspace.shared.open(URL(string: Self.githubURLString)!)
                }
                linkRow(label: "GitHub", value: Self.githubURLString) {
                    NSWorkspace.shared.open(URL(string: Self.githubURLString)!)
                }
                linkRow(label: "X", value: "@countquery") {
                    NSWorkspace.shared.open(URL(string: "https://x.com/countquery")!)
                }
                linkRow(label: Localizer.t("about.wechatOA"), value: "mowenfeigong") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("mowenfeigong", forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                }
            }
            .padding(.top, 8)

            if showCopied {
                Text(Localizer.t("about.copied"))
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func linkRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Text(value)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Background Image Picker

struct BackgroundImagePicker: View {
    @Binding var images: [String]
    let onSave: () -> Void

    private let maxImages = 10
    /// 5 columns × 2 rows grid
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    uploadImages()
                } label: {
                    Label(Localizer.t("settings.upload"), systemImage: "plus")
                }
                .disabled(images.count >= maxImages)

                if !images.isEmpty {
                    Button(role: .destructive) {
                        images.removeAll()
                        onSave()
                    } label: {
                        Label(Localizer.t("settings.resetBackground"), systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()
                Text("\(images.count)/\(maxImages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !images.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(images.indices, id: \.self) { index in
                        BackgroundThumbnail(
                            path: images[index],
                            onDelete: {
                                images.remove(at: index)
                                onSave()
                            }
                        )
                        .draggable("\(index)")
                        .dropDestination(for: String.self) { items, _ in
                            guard let sourceStr = items.first,
                                  let sourceIndex = Int(sourceStr),
                                  sourceIndex != index else { return false }
                            let moved = images.remove(at: sourceIndex)
                            images.insert(moved, at: index)
                            onSave()
                            return true
                        }
                    }
                }
            }
        }
    }

    private func uploadImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = Localizer.t("settings.chooseImage")

        guard panel.runModal() == .OK else { return }

        let remaining = maxImages - images.count
        let newPaths = panel.urls.prefix(remaining).map { $0.path }
        images.append(contentsOf: newPaths)
        onSave()
    }
}

struct BackgroundThumbnail: View {
    let path: String
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let nsImage = NSImage(contentsOfFile: path) {
                    // The grid cell is a wide rectangle (flexible column width,
                    // fixed 64pt height), not a square — forcing aspectRatio(1)
                    // coerced every photo into a square crop first and then
                    // stretched that square to fit the rectangular cell,
                    // squishing it. Using the image's own native ratio with
                    // .fill covers the actual cell without distortion.
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipped()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }
}

// MARK: - Small App Icon for Hidden Apps List

struct AppIconSmall: View {
    let record: AppRecord

    var body: some View {
        let nsImage = NSWorkspace.shared.icon(forFile: record.path)
        Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 24, height: 24)
    }
}

// MARK: - Icon Thumbnail View

/// `IconThumbnailView` sits in a `ForEach` inside `AppearanceSettingsView`'s
/// `Form`, so its `body` (and thus `nsImage`) re-evaluates on every unrelated
/// preference change in that Form — e.g. dragging the blur slider. Without
/// caching, that redid a `Bundle.main.url` lookup + disk read per style on
/// every frame, which is the settings-page click lag reported after other
/// fixes had already addressed the more severe scrambled/frozen state.
@MainActor
private enum IconThumbnailCache {
    static var images: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        let loaded: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            loaded = img
        } else if let url = Bundle.main.url(forResource: name, withExtension: "icns"),
                  let img = NSImage(contentsOf: url) {
            loaded = img
        } else {
            loaded = NSImage(named: name)
        }
        if let loaded {
            images[name] = loaded
        }
        return loaded
    }
}

struct IconThumbnailView: View {
    let style: UserPreferences.AppIconStyle
    let isSelected: Bool

    private var nsImage: NSImage? {
        IconThumbnailCache.image(named: style.thumbnailName)
    }

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let img = nsImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(Text(style.displayName).font(.caption2))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )
            .shadow(radius: isSelected ? 3 : 1)
            Text(style.displayName)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}
