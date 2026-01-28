import Foundation
import SwiftData

@Model
final class Segment: Identifiable {
    @Attribute(.unique) var id: UUID
    var tagId: UUID?
    var tag: String
    var start: Date
    var end: Date?
    var note: String?

    init(id: UUID = UUID(), tagId: UUID? = nil, tag: String, start: Date, end: Date? = nil, note: String? = nil) {
        self.id = id
        self.tagId = tagId
        self.tag = tag
        self.start = start
        self.end = end
        self.note = note
    }
}
