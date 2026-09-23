import Foundation

extension Notification.Name {
    static let iLaunchLanguageChanged = Notification.Name("iLaunchLanguageChanged")
    static let iLaunchIconChanged = Notification.Name("iLaunchIconChanged")
}

enum AppLanguage {
    case system, chinese, english, japanese, korean, russian

    static func from(_ lang: UserPreferences.Language) -> AppLanguage {
        switch lang {
        case .system: return .system
        case .chinese: return .chinese
        case .english: return .english
        case .japanese: return .japanese
        case .korean: return .korean
        case .russian: return .russian
        }
    }
}

@MainActor
struct Localizer {
    static var current: AppLanguage = .system

    static func setLanguage(_ lang: UserPreferences.Language) {
        let newLang = AppLanguage.from(lang)
        // Sparkle's own update-check alerts resolve their language via
        // Bundle's automatic locale resolution, which does not honor a
        // UserDefaults "AppleLanguages" override for anything other than
        // Bundle.main (confirmed empirically — see
        // BundleLocalizationOverride.swift). Force it via the swizzle
        // instead; safe to call every time, it only sets up once.
        Bundle.activateLanguageOverride()
        guard newLang != current else { return }
        current = newLang
        Bundle.overrideLanguage = newLang
        NotificationCenter.default.post(name: .iLaunchLanguageChanged, object: nil)
    }

    static func t(_ key: String) -> String {
        let lang = current
        if lang == .system {
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            switch code {
            case "zh": return zhStrings[key] ?? key
            case "ja": return jaStrings[key] ?? key
            case "ko": return koStrings[key] ?? key
            case "ru": return ruStrings[key] ?? enStrings[key] ?? key
            default: return enStrings[key] ?? key
            }
        }
        switch lang {
        case .chinese: return zhStrings[key] ?? key
        case .english: return enStrings[key] ?? key
        case .japanese: return jaStrings[key] ?? key
        case .korean: return koStrings[key] ?? key
        case .russian: return ruStrings[key] ?? enStrings[key] ?? key
        case .system: return key
        }
    }

    // MARK: - English

    static let enStrings: [String: String] = [
        // Settings sections
        "settings.launch": "Launch",
        "settings.appearance": "Appearance",
        "settings.apps": "Apps",
        "settings.background": "Background",
        "settings.hiddenApps": "Hidden Apps",
        "settings.animations": "Animations",
        "settings.language": "Interface Language",
        "settings.languagePicker": "Language Settings",

        // Launch settings
        "settings.hotKey": "Global shortcut",
        "settings.hotKeyPressKeys": "Press keys…",
        "settings.hotKeyNeedsModifier": "Hold at least one modifier key (⌘⌥⌃⇧)",
        "settings.hotKeyEscReserved": "Esc is reserved to close the overlay",
        "settings.hotKeyConflict": "That combo is already used by another app — try a different one",
        "settings.launchAtLogin": "Launch at login",
        "settings.showMenuBarIcon": "Show menu bar icon",
        "settings.showDockIcon": "Show Dock icon",
        "settings.hideDockOnLaunch": "Fill the whole screen (covers the Dock)",

        // Appearance settings
        "settings.backgroundBlur": "Background blur",
        "settings.reduceMotion": "Reduce motion",
        "settings.appIcon": "App icon",

        // Background settings
        "settings.showDesktop": "Show desktop background",
        "settings.uploadBackground": "Upload background image",
        "settings.backgroundMode": "Background mode",
        "settings.autoCarousel": "Auto carousel backgrounds",
        "settings.carouselHint": "Background images rotate on each page flip",
        "settings.firstImageHint": "Using the first uploaded image as background",
        "settings.resetBackground": "Reset background",
        "settings.noHiddenApps": "No hidden apps",

        // Animation settings
        "settings.animateIcons": "Icon animations",
        "settings.animatePageFlip": "Page flip animation",
        "settings.animateFolder": "Folder animation",
        "settings.animateDrag": "Drag animation",
        "settings.animateSearch": "Search transition",

        // Apps settings
        "settings.showSystemApps": "Show system applications",

        // Settings navigation
        "settings.general": "General",
        "settings.interface": "Interface",
        "settings.appManagement": "App Management",
        "settings.about": "About",
        "settings.logs": "Logs",
        "settings.systemApps": "System Applications",
        "settings.showHiddenInSearch": "Show hidden apps in search",
        "settings.title": "iLaunch Settings",

        // About
        "about.version": "Version",
        "about.website": "Website",
        "about.wechatOA": "WeChat OA",
        "about.copied": "Copied",
        "about.diagnostics": "Diagnostics",
        "about.diagnosticsToggle": "Enable diagnostic logging",
        "about.diagnosticsHint": "Helps troubleshoot issues. Saved locally only, never uploaded.",
        "about.openLogFolder": "Show Log Folder",

        // Context menu
        "menu.trash": "Move to Trash",
        "menu.hide": "Hide",
        "menu.unhide": "Show",
        "menu.enlargeFolder": "Enlarge folder",
        "menu.shrinkFolder": "Shrink folder",
        "menu.tidyGrid": "Tidy up",
        "menu.resetBackground": "Reset background",
        "menu.editModeHint": "Tap to exit edit mode",

        // Settings actions
        "settings.upload": "Upload",
        "settings.chooseImage": "Choose image",

        // Menu bar
        "menubar.open": "Open iLaunch",
        "menubar.settings": "Settings…",
        "menubar.logs": "Open Log File",
        "menubar.checkForUpdates": "Check for Updates…",
        "menubar.quit": "Quit",

        // Search
        "search.placeholder": "Search",

        // Accessibility
        "accessibility.prompt": "iLaunch needs Accessibility permission to use global shortcuts. Please enable it in System Settings > Privacy & Security > Accessibility.",

        // Layout settings
        "settings.layout": "Layout",
        "settings.gridRows": "Rows per page",
        "settings.gridRowsAuto": "Auto",
        "settings.gridColumns": "Columns per page",
        "settings.iconSize": "Icon size",
        "settings.iconSizeSmall": "Small",
        "settings.iconSizeMedium": "Medium",
        "settings.iconSizeLarge": "Large",
        "settings.showAppNames": "Show app names",
    ]

    // MARK: - Chinese (Simplified)

    static let zhStrings: [String: String] = [
        // Settings sections
        "settings.launch": "启动",
        "settings.appearance": "外观",
        "settings.apps": "应用",
        "settings.background": "背景",
        "settings.hiddenApps": "隐藏应用",
        "settings.animations": "动画",
        "settings.language": "界面语言",
        "settings.languagePicker": "语言设置",

        // Launch settings
        "settings.hotKey": "全局快捷键",
        "settings.hotKeyPressKeys": "按下快捷键…",
        "settings.hotKeyNeedsModifier": "请至少按住一个修饰键（⌘⌥⌃⇧）",
        "settings.hotKeyEscReserved": "Esc 已保留用于关闭悬浮窗，不能作为快捷键",
        "settings.hotKeyConflict": "该组合已被其他应用占用，请换一个",
        "settings.launchAtLogin": "开机自启",
        "settings.showMenuBarIcon": "显示菜单栏图标",
        "settings.showDockIcon": "显示 Dock 图标",
        "settings.hideDockOnLaunch": "启动时占满全屏（覆盖 Dock 栏）",

        // Appearance settings
        "settings.backgroundBlur": "背景模糊",
        "settings.reduceMotion": "减弱动态效果",
        "settings.appIcon": "应用图标",

        // Background settings
        "settings.showDesktop": "显示桌面背景",
        "settings.uploadBackground": "上传背景图",
        "settings.backgroundMode": "背景模式",
        "settings.autoCarousel": "自动轮播背景图",
        "settings.carouselHint": "每次翻页自动切换背景图",
        "settings.firstImageHint": "默认以第一张图片为背景",
        "settings.resetBackground": "重置背景图",
        "settings.noHiddenApps": "暂无隐藏应用",

        // Animation settings
        "settings.animateIcons": "图标动画",
        "settings.animatePageFlip": "翻页动画",
        "settings.animateFolder": "文件夹动画",
        "settings.animateDrag": "拖拽动画",
        "settings.animateSearch": "搜索过渡动画",

        // Apps settings
        "settings.showSystemApps": "显示系统应用",

        // Settings navigation
        "settings.general": "通用",
        "settings.interface": "界面",
        "settings.appManagement": "应用管理",
        "settings.about": "关于",
        "settings.logs": "日志管理",
        "settings.systemApps": "系统应用",
        "settings.showHiddenInSearch": "在搜索中显示隐藏应用",
        "settings.title": "iLaunch 设置",

        // About
        "about.version": "版本",
        "about.website": "官网",
        "about.wechatOA": "公众号",
        "about.copied": "已复制",
        "about.diagnostics": "诊断",
        "about.diagnosticsToggle": "记录诊断日志",
        "about.diagnosticsHint": "用于排查问题，仅保存在本地，不会上传。",
        "about.openLogFolder": "显示日志文件夹",

        // Context menu
        "menu.trash": "移到废纸篓",
        "menu.hide": "隐藏",
        "menu.unhide": "显示",
        "menu.enlargeFolder": "放大文件夹",
        "menu.shrinkFolder": "缩小文件夹",
        "menu.tidyGrid": "整理桌面",
        "menu.resetBackground": "重置背景图",
        "menu.editModeHint": "点击退出编辑模式",

        // Settings actions
        "settings.upload": "上传",
        "settings.chooseImage": "选择背景图",

        // Menu bar
        "menubar.open": "打开 iLaunch",
        "menubar.settings": "设置…",
        "menubar.logs": "打开日志文件",
        "menubar.checkForUpdates": "检查更新…",
        "menubar.quit": "退出",

        // Search
        "search.placeholder": "搜索",

        // Accessibility
        "accessibility.prompt": "iLaunch 需要辅助功能权限才能使用全局快捷键。请在系统设置 > 隐私与安全性 > 辅助功能中启用。",

        // Layout settings
        "settings.layout": "布局",
        "settings.gridRows": "每页行数",
        "settings.gridRowsAuto": "自动",
        "settings.gridColumns": "每页列数",
        "settings.iconSize": "图标大小",
        "settings.iconSizeSmall": "小",
        "settings.iconSizeMedium": "中",
        "settings.iconSizeLarge": "大",
        "settings.showAppNames": "显示应用名称",
    ]

    // MARK: - Japanese

    static let jaStrings: [String: String] = [
        // Settings sections
        "settings.launch": "起動",
        "settings.appearance": "外観",
        "settings.apps": "アプリ",
        "settings.background": "背景",
        "settings.hiddenApps": "非表示のアプリ",
        "settings.animations": "アニメーション",
        "settings.language": "表示言語",
        "settings.languagePicker": "言語設定",

        // Launch settings
        "settings.hotKey": "グローバルショートカット",
        "settings.hotKeyPressKeys": "キーを押してください…",
        "settings.hotKeyNeedsModifier": "修飾キー（⌘⌥⌃⇧）を1つ以上押してください",
        "settings.hotKeyEscReserved": "Escはオーバーレイを閉じるために予約されています",
        "settings.hotKeyConflict": "この組み合わせは他のアプリで使用されています。別のキーを選んでください",
        "settings.launchAtLogin": "ログイン時に起動",
        "settings.showMenuBarIcon": "メニューバーアイコンを表示",
        "settings.showDockIcon": "Dockアイコンを表示",
        "settings.hideDockOnLaunch": "全画面表示にする（Dockを覆う）",

        // Appearance settings
        "settings.backgroundBlur": "背景のぼかし",
        "settings.reduceMotion": "視差効果を減らす",
        "settings.appIcon": "アプリアイコン",

        // Background settings
        "settings.showDesktop": "デスクトップ背景を表示",
        "settings.uploadBackground": "背景画像をアップロード",
        "settings.backgroundMode": "背景モード",
        "settings.autoCarousel": "背景の自動カルーセル",
        "settings.carouselHint": "ページをめくるたびに背景画像が切り替わります",
        "settings.firstImageHint": "最初のアップロード画像を背景として使用",
        "settings.resetBackground": "背景をリセット",
        "settings.noHiddenApps": "非表示のアプリはありません",

        // Animation settings
        "settings.animateIcons": "アイコンアニメーション",
        "settings.animatePageFlip": "ページめくりアニメーション",
        "settings.animateFolder": "フォルダアニメーション",
        "settings.animateDrag": "ドラッグアニメーション",
        "settings.animateSearch": "検索トランジション",

        // Apps settings
        "settings.showSystemApps": "システムアプリケーションを表示",

        // Settings navigation
        "settings.general": "一般",
        "settings.interface": "インターフェース",
        "settings.appManagement": "アプリ管理",
        "settings.about": "について",
        "settings.logs": "ログ",
        "settings.systemApps": "システムアプリケーション",
        "settings.showHiddenInSearch": "検索で非表示アプリを表示",
        "settings.title": "iLaunch 設定",

        // About
        "about.version": "バージョン",
        "about.website": "ウェブサイト",
        "about.wechatOA": "WeChat公式アカウント",
        "about.copied": "コピーしました",
        "about.diagnostics": "診断",
        "about.diagnosticsToggle": "診断ログを記録",
        "about.diagnosticsHint": "問題の調査に使用します。ローカルにのみ保存され、アップロードされません。",
        "about.openLogFolder": "ログフォルダを表示",

        // Context menu
        "menu.trash": "ゴミ箱に移動",
        "menu.hide": "非表示",
        "menu.unhide": "表示",
        "menu.enlargeFolder": "フォルダを拡大",
        "menu.shrinkFolder": "フォルダを縮小",
        "menu.tidyGrid": "整理",
        "menu.resetBackground": "背景をリセット",
        "menu.editModeHint": "タップして編集モードを終了",

        // Settings actions
        "settings.upload": "アップロード",
        "settings.chooseImage": "画像を選択",

        // Menu bar
        "menubar.open": "iLaunchを開く",
        "menubar.settings": "設定…",
        "menubar.logs": "ログファイルを開く",
        "menubar.checkForUpdates": "アップデートを確認…",
        "menubar.quit": "終了",

        // Search
        "search.placeholder": "検索",

        // Accessibility
        "accessibility.prompt": "iLaunchはグローバルショートカットを使用するためにアクセシビリティ権限が必要です。システム設定 > プライバシーとセキュリティ > アクセシビリティで有効にしてください。",

        // Layout settings
        "settings.layout": "レイアウト",
        "settings.gridRows": "ページあたりの行数",
        "settings.gridRowsAuto": "自動",
        "settings.gridColumns": "ページあたりの列数",
        "settings.iconSize": "アイコンサイズ",
        "settings.iconSizeSmall": "小",
        "settings.iconSizeMedium": "中",
        "settings.iconSizeLarge": "大",
        "settings.showAppNames": "アプリ名を表示",
    ]

    // MARK: - Korean

    static let koStrings: [String: String] = [
        // Settings sections
        "settings.launch": "실행",
        "settings.appearance": "외관",
        "settings.apps": "앱",
        "settings.background": "배경",
        "settings.hiddenApps": "숨긴 앱",
        "settings.animations": "애니메이션",
        "settings.language": "인터페이스 언어",
        "settings.languagePicker": "언어 설정",

        // Launch settings
        "settings.hotKey": "글로벌 단축키",
        "settings.hotKeyPressKeys": "키를 누르세요…",
        "settings.hotKeyNeedsModifier": "수정 키(⌘⌥⌃⇧)를 하나 이상 눌러야 합니다",
        "settings.hotKeyEscReserved": "Esc는 오버레이를 닫는 데 예약되어 있습니다",
        "settings.hotKeyConflict": "이 조합은 다른 앱에서 이미 사용 중입니다. 다른 조합을 선택하세요",
        "settings.launchAtLogin": "로그인 시 실행",
        "settings.showMenuBarIcon": "메뉴 막대 아이콘 표시",
        "settings.showDockIcon": "Dock 아이콘 표시",
        "settings.hideDockOnLaunch": "전체 화면으로 표시 (Dock을 덮음)",

        // Appearance settings
        "settings.backgroundBlur": "배경 흐림",
        "settings.reduceMotion": "동작 줄이기",
        "settings.appIcon": "앱 아이콘",

        // Background settings
        "settings.showDesktop": "데스크탑 배경 표시",
        "settings.uploadBackground": "배경 이미지 업로드",
        "settings.backgroundMode": "배경 모드",
        "settings.autoCarousel": "배경 자동 캐러셀",
        "settings.carouselHint": "페이지를 넘길 때마다 배경 이미지가 전환됩니다",
        "settings.firstImageHint": "첫 번째 업로드 이미지를 배경으로 사용",
        "settings.resetBackground": "배경 재설정",
        "settings.noHiddenApps": "숨긴 앱이 없습니다",

        // Animation settings
        "settings.animateIcons": "아이콘 애니메이션",
        "settings.animatePageFlip": "페이지 넘김 애니메이션",
        "settings.animateFolder": "폴더 애니메이션",
        "settings.animateDrag": "드래그 애니메이션",
        "settings.animateSearch": "검색 전환",

        // Apps settings
        "settings.showSystemApps": "시스템 응용 프로그램 표시",

        // Settings navigation
        "settings.general": "일반",
        "settings.interface": "인터페이스",
        "settings.appManagement": "앱 관리",
        "settings.about": "정보",
        "settings.logs": "로그",
        "settings.systemApps": "시스템 응용 프로그램",
        "settings.showHiddenInSearch": "검색에서 숨긴 앱 표시",
        "settings.title": "iLaunch 설정",

        // About
        "about.version": "버전",
        "about.website": "웹사이트",
        "about.wechatOA": "WeChat 공식 계정",
        "about.copied": "복사됨",
        "about.diagnostics": "진단",
        "about.diagnosticsToggle": "진단 로그 기록",
        "about.diagnosticsHint": "문제 해결에 사용됩니다. 로컬에만 저장되며 업로드되지 않습니다.",
        "about.openLogFolder": "로그 폴더 표시",

        // Context menu
        "menu.trash": "휴지통으로 이동",
        "menu.hide": "숨기기",
        "menu.unhide": "표시",
        "menu.enlargeFolder": "폴더 확대",
        "menu.shrinkFolder": "폴더 축소",
        "menu.tidyGrid": "정리",
        "menu.resetBackground": "배경 재설정",
        "menu.editModeHint": "탭하여 편집 모드 종료",

        // Settings actions
        "settings.upload": "업로드",
        "settings.chooseImage": "이미지 선택",

        // Menu bar
        "menubar.open": "iLaunch 열기",
        "menubar.settings": "설정…",
        "menubar.logs": "로그 파일 열기",
        "menubar.checkForUpdates": "업데이트 확인…",
        "menubar.quit": "종료",

        // Search
        "search.placeholder": "검색",

        // Accessibility
        "accessibility.prompt": "iLaunch는 글로벌 단축키를 사용하려면 손쉬운 사용 권한이 필요합니다. 시스템 설정 > 개인 정보 보호 및 보안 > 손쉬운 사용에서 활성화해 주세요.",

        // Layout settings
        "settings.layout": "레이아웃",
        "settings.gridRows": "페이지당 행 수",
        "settings.gridRowsAuto": "자동",
        "settings.gridColumns": "페이지당 열 수",
        "settings.iconSize": "아이콘 크기",
        "settings.iconSizeSmall": "작게",
        "settings.iconSizeMedium": "중간",
        "settings.iconSizeLarge": "크게",
        "settings.showAppNames": "앱 이름 표시",
    ]

    // MARK: - Russian

    static let ruStrings: [String: String] = [
        // Settings sections
        "settings.launch": "Запуск",
        "settings.appearance": "Внешний вид",
        "settings.apps": "Приложения",
        "settings.background": "Фон",
        "settings.hiddenApps": "Скрытые приложения",
        "settings.animations": "Анимации",
        "settings.language": "Язык интерфейса",
        "settings.languagePicker": "Настройки языка",

        // Launch settings
        "settings.hotKey": "Глобальное сочетание клавиш",
        "settings.hotKeyPressKeys": "Нажмите клавиши…",
        "settings.hotKeyNeedsModifier": "Удерживайте хотя бы одну клавишу-модификатор (⌘⌥⌃⇧)",
        "settings.hotKeyEscReserved": "Esc зарезервирован для закрытия окна",
        "settings.hotKeyConflict": "Эта комбинация уже используется другим приложением — выберите другую",
        "settings.launchAtLogin": "Запускать при входе",
        "settings.showMenuBarIcon": "Показывать значок в строке меню",
        "settings.showDockIcon": "Показывать значок в Dock",
        "settings.hideDockOnLaunch": "На весь экран (закрывает Dock)",

        // Appearance settings
        "settings.backgroundBlur": "Размытие фона",
        "settings.reduceMotion": "Уменьшить движение",
        "settings.appIcon": "Значок приложения",

        // Background settings
        "settings.showDesktop": "Показывать фон рабочего стола",
        "settings.uploadBackground": "Загрузить фоновое изображение",
        "settings.backgroundMode": "Режим фона",
        "settings.autoCarousel": "Автоматическая карусель фона",
        "settings.carouselHint": "Фоновые изображения меняются при каждом перелистывании",
        "settings.firstImageHint": "Первое загруженное изображение используется как фон",
        "settings.resetBackground": "Сбросить фон",
        "settings.noHiddenApps": "Нет скрытых приложений",

        // Animation settings
        "settings.animateIcons": "Анимация значков",
        "settings.animatePageFlip": "Анимация перелистывания",
        "settings.animateFolder": "Анимация папок",
        "settings.animateDrag": "Анимация перетаскивания",
        "settings.animateSearch": "Анимация поиска",

        // Apps settings
        "settings.showSystemApps": "Показывать системные приложения",

        // Settings navigation
        "settings.general": "Основные",
        "settings.interface": "Интерфейс",
        "settings.appManagement": "Управление приложениями",
        "settings.about": "О программе",
        "settings.systemApps": "Системные приложения",
        "settings.showHiddenInSearch": "Показывать скрытые в поиске",
        "settings.title": "Настройки iLaunch",

        // About
        "about.version": "Версия",
        "about.website": "Веб-сайт",
        "about.wechatOA": "WeChat OA",
        "about.copied": "Скопировано",
        "about.diagnostics": "Диагностика",
        "about.diagnosticsToggle": "Вести диагностический журнал",
        "about.diagnosticsHint": "Помогает в устранении неполадок. Хранится только локально, не отправляется.",
        "about.openLogFolder": "Показать папку журнала",

        // Context menu
        "menu.trash": "Переместить в корзину",
        "menu.hide": "Скрыть",
        "menu.unhide": "Показать",
        "menu.enlargeFolder": "Увеличить папку",
        "menu.shrinkFolder": "Уменьшить папку",
        "menu.tidyGrid": "Упорядочить",
        "menu.resetBackground": "Сбросить фон",
        "menu.editModeHint": "Нажмите для выхода из режима редактирования",

        // Settings actions
        "settings.upload": "Загрузить",
        "settings.chooseImage": "Выбрать изображение",

        // Menu bar
        "menubar.open": "Открыть iLaunch",
        "menubar.settings": "Настройки…",
        "menubar.logs": "Открыть файл журнала",
        "menubar.checkForUpdates": "Проверить обновления…",
        "menubar.quit": "Выйти",

        // Search
        "search.placeholder": "Поиск",

        // Accessibility
        "accessibility.prompt": "iLaunch требует разрешения на универсальный доступ для использования глобальных сочетаний клавиш. Включите его в Системные настройки > Конфиденциальность и безопасность > Универсальный доступ.",

        // Layout settings
        "settings.layout": "Раскладка",
        "settings.gridRows": "Строк на странице",
        "settings.gridRowsAuto": "Авто",
        "settings.gridColumns": "Столбцов на странице",
        "settings.iconSize": "Размер значков",
        "settings.iconSizeSmall": "Маленький",
        "settings.iconSizeMedium": "Средний",
        "settings.iconSizeLarge": "Большой",
        "settings.showAppNames": "Показывать названия приложений",
    ]
}
