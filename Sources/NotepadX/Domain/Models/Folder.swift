import Foundation

struct Folder: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var parentID: UUID?
    var name: String
    var colorHex: String?
    var iconSystemName: String
    var sortIndex: Int
    var isExpanded: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        name: String,
        colorHex: String? = nil,
        iconSystemName: String = "folder",
        sortIndex: Int = 0,
        isExpanded: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.colorHex = colorHex
        self.iconSystemName = iconSystemName
        self.sortIndex = sortIndex
        self.isExpanded = isExpanded
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
