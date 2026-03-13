import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool

    init(id: UUID = UUID(), role: MessageRole, content: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}
