import SwiftUI

struct DefaultTagDefinition: Identifiable {
    let id = UUID()
    let name: String
    let isSystem: Bool
}

enum TagDefaults {
    static let idleName = "Idle / Off"
    static let definitions: [DefaultTagDefinition] = [
        DefaultTagDefinition(name: "School", isSystem: false),
        DefaultTagDefinition(name: "Work", isSystem: false),
        DefaultTagDefinition(name: "Training", isSystem: false),
        DefaultTagDefinition(name: "Food", isSystem: false),
        DefaultTagDefinition(name: "Personal Care", isSystem: false),
        DefaultTagDefinition(name: "Recovery / Mind", isSystem: false),
        DefaultTagDefinition(name: "Social / Admin", isSystem: false),
        DefaultTagDefinition(name: idleName, isSystem: true)
    ]
}

func tagColor(_ tag: TagItem) -> Color {
    tagColor(tag.name)
}

func tagColor(_ tagName: String) -> Color {
    switch tagName {
    case "School":
        return .blue
    case "Work":
        return .teal
    case "Training":
        return .green
    case "Food":
        return .orange
    case "Personal Care":
        return .pink
    case "Recovery / Mind":
        return .purple
    case "Social / Admin":
        return .indigo
    case TagDefaults.idleName:
        return .gray
    default:
        return .accentColor
    }
}

func formattedDuration(_ duration: TimeInterval) -> String {
    if duration < 60 {
        return "<1m"
    }
    let totalMinutes = Int(duration / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

func formatPercent(_ value: Double) -> String {
    let clamped = max(0, min(1, value))
    let percent = Int((clamped * 100).rounded())
    return "\(percent)%"
}

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

func formattedTime(_ date: Date) -> String {
    timeFormatter.string(from: date)
}

func formattedTimeRange(start: Date, end: Date) -> String {
    "\(formattedTime(start))–\(formattedTime(end))"
}
