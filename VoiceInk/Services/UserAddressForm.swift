import Foundation

/// Grammatical gender the UI uses when it addresses the user ("zaoszczędziłeś /
/// zaoszczędziłaś / zaoszczędziłoś"). String Catalogs can vary only by plural and
/// device, and Apple's automatic grammar agreement does not cover Polish, so the
/// masculine form stays in Localizable and the other forms live in override
/// tables (AddressFeminine, AddressNeuter) holding only the gendered keys.
enum UserAddressForm: String, CaseIterable, Hashable, Identifiable {
    static let userDefaultsKey = "UserAddressForm"

    case masculine
    case feminine
    case neuter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .masculine:
            return String(localized: "Masculine")
        case .feminine:
            return String(localized: "Feminine")
        case .neuter:
            return String(localized: "Neuter")
        }
    }

    static var current: UserAddressForm {
        let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey) ?? Self.masculine.rawValue
        return UserAddressForm(rawValue: rawValue) ?? .masculine
    }

    /// Only Polish among the bundled languages inflects second-person forms by gender.
    static var appliesToCurrentLanguage: Bool {
        Bundle.main.preferredLocalizations.first == "pl"
    }

    static func localized(_ key: String, form: UserAddressForm = .current) -> String {
        if appliesToCurrentLanguage, let table = form.overrideTable {
            let value = Bundle.main.localizedString(forKey: key, value: missingSentinel, table: table)
            if value != missingSentinel {
                return value
            }
        }
        return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    static func localizedFormat(_ key: String, _ args: CVarArg..., form: UserAddressForm = .current) -> String {
        String(format: localized(key, form: form), locale: Locale.current, arguments: args)
    }

    private static let missingSentinel = "\u{0}UserAddressForm.missing"

    private var overrideTable: String? {
        switch self {
        case .masculine:
            return nil
        case .feminine:
            return "AddressFeminine"
        case .neuter:
            return "AddressNeuter"
        }
    }
}
