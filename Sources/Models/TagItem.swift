import Foundation
import SwiftData

@Model
final class TagItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    var isHidden: Bool
    var isSystem: Bool

    init(id: UUID = UUID(), name: String, order: Int, isHidden: Bool = false, isSystem: Bool = false) {
        self.id = id
        self.name = name
        self.order = order
        self.isHidden = isHidden
        self.isSystem = isSystem
    }
}

extension TagItem: Hashable {
    static func == (lhs: TagItem, rhs: TagItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
