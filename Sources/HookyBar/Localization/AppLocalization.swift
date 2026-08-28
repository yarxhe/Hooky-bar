import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case russian
    case english

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .system: L10n.tr("language.system")
        case .russian: "Русский"
        case .english: "English"
        }
    }
}

/// Единый источник языка для SwiftUI, AppKit и будущих SDK-модулей.
final class AppLocalization: ObservableObject {
    static let defaultsKey = "appearance.language"

    @Published private(set) var language: AppLanguage

    private let defaults: UserDefaults
    private var localeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Self.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard self?.language == .system else { return }
            self?.objectWillChange.send()
        }
    }

    deinit {
        if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) }
    }

    var locale: Locale { Locale(identifier: L10n.resolvedLanguageCode) }

    func select(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.defaultsKey)
        self.language = language
    }
}

enum L10n {
    static var selectedLanguage: AppLanguage {
        UserDefaults.standard.string(forKey: AppLocalization.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    static var resolvedLanguageCode: String {
        switch selectedLanguage {
        case .russian: return "ru"
        case .english: return "en"
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("ru") ? "ru" : "en"
        }
    }

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let code = resolvedLanguageCode
        let resourceBundle: Bundle
        if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            resourceBundle = bundle
        } else {
            resourceBundle = Bundle.module
        }
        let format = resourceBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: code), arguments: arguments)
    }
}
