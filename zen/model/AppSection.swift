import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case settings = "Settings"
    case profile = "Profile"
    
    var id : Self { self }
    
    var icons: String? {
        switch self {
        case .home:
            return "house.fill"
        case .settings:
            return "gear"
        case .profile:
            return "person.crop.circle.fill"
        }
    }
}
