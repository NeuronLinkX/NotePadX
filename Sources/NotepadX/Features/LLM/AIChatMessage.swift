import Foundation

struct AIChatMessage: Sendable, Equatable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    var role: Role
    var content: String
}
