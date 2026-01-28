import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var manager: TimerManager
    @State private var selectedDay: Date = Date()
    @State private var showTimeline: Bool = false
    @State private var editingSegment: Segment?
    @State private var editMode: EditSegmentSheet.InitialMode = .edit
    @State private var hoveredSegmentId: UUID?
    @State private var tagChangeSegment: Segment?
    @State private var showTagChangeDialog: Bool = false
    @State private var deleteTargetSegment: Segment?
    @State private var showDeleteConfirm: Bool = false
    @State private var isTimelineEditing: Bool = false
    @State private var showManageTags: Bool = false
    @AppStorage("ClockIn.TimelineSortAscending") private var timelineSortAscending: Bool = true
    private let calendar = Calendar.current
    private let timeColumnWidth: CGFloat = 56
    private let railColumnWidth: CGFloat = 28


    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Spacer()

                    HStack(spacing: 12) {
                        Button(action: { shiftSelectedDay(by: -1) }) {
                            ZStack {
                                Circle().fill(.white.opacity(0.08))
                                Image(systemName: "chevron.left")
                            }
                            .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)

                        Button("Today") {
                            setSelectedDay(calendar.startOfDay(for: Date()))
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelectedToday ? .accentColor : .secondary)

                        Button(action: { shiftSelectedDay(by: 1) }) {
                            ZStack {
                                Circle().fill(.white.opacity(0.08))
                                Image(systemName: "chevron.right")
                            }
                            .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)

                        Button("Manage Tags") {
                            showManageTags = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                todaySummarySection
                todayTimelineSection
                last7DaysSection
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 640)
        .sheet(item: $editingSegment) { segment in
            EditSegmentSheet(segment: segment, day: selectedDay, initialMode: editMode)
                .environmentObject(manager)
        }
        .confirmationDialog("Change Tag", isPresented: $showTagChangeDialog, titleVisibility: .visible) {
            if let segment = tagChangeSegment {
                ForEach(manager.allTags) { tag in
                    Button(tag.name) {
                        do {
                            try manager.updateSegment(id: segment.id, tag: tag, start: segment.start, end: segment.end, note: segment.note)
                        } catch {
                            // No-op
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete Segment?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let segment = deleteTargetSegment {
                    manager.deleteSegment(id: segment.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showManageTags) {
            ManageTagsView()
                .environmentObject(manager)
        }
        .onAppear {
            setSelectedDay(calendar.startOfDay(for: manager.nowTick))
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if let dashboardWindow = NSApp.windows.first(where: { $0.title == "Dashboard" }) {
                    dashboardWindow.makeKeyAndOrderFront(nil)
                    dashboardWindow.orderFrontRegardless()
                }
            }
            manager.setDashboardVisible(true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
            manager.setDashboardVisible(false)
        }
    }

    private var todaySummarySection: some View {
        let totals = manager.totalsByTag(for: selectedDay)
        let totalTracked = manager.totalTracked(for: selectedDay)
        let visibleTotals = totals.filter { $0.value > 0 }
        let activeTotals = visibleTotals.filter { $0.key.name != TagDefaults.idleName }.sorted { $0.value > $1.value }
        let idleTotal = visibleTotals.first(where: { $0.key.name == TagDefaults.idleName })

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Day Overview")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("· \(shortDateString(for: selectedDay))")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            HStack {
                Text("Total Tracked")
                Spacer()
                Text(formattedDuration(totalTracked))
                    .fontWeight(.semibold)
            }
            Divider()
            if visibleTotals.isEmpty {
                Text("No tracked time")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(activeTotals, id: \.key) { entry in
                    let tag = entry.key
                    let total = entry.value
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tagColor(tag).opacity(0.8))
                            .frame(width: 8, height: 8)
                        Text(tag.name)
                        Spacer()
                        Text(formattedDuration(total))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }

                if let idleTotal {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tagColor(TagDefaults.idleName).opacity(0.8))
                            .frame(width: 8, height: 8)
                        Text(TagDefaults.idleName)
                        Spacer()
                        Text(formattedDuration(idleTotal.value))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var todayTimelineSection: some View {
        let rawSegments = manager.segments(for: selectedDay)
        let cleanedSegments = manager.cleanSegments(rawSegments)
        let displaySegments = cleanedSegments.sorted { $0.start < $1.start }
        let longestNonIdle = longestNonIdleSegmentDuration(segments: cleanedSegments)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text("Timeline")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(showTimeline ? "▾" : "▸")
                        .foregroundStyle(.secondary)
                }

                Text(longestNonIdle > 0
                     ? "Longest segment (non-idle): \(formattedDuration(longestNonIdle))"
                     : "Longest segment (non-idle): —")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    if isTimelineEditing {
                        Button(action: { timelineSortAscending.toggle() }) {
                            Image(systemName: timelineSortAscending ? "arrow.up" : "arrow.down")
                        }
                        .buttonStyle(.plain)
                        .help("Sort timeline")

                        Button("Merge Adjacent") {
                            manager.mergeAdjacent(for: selectedDay)
                        }
                    }
                }
                .frame(minWidth: 150, alignment: .trailing)
                .opacity(isTimelineEditing ? 1 : 0)
                .allowsHitTesting(isTimelineEditing)

                Button(action: { isTimelineEditing.toggle() }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showTimeline.toggle()
            }
            if showTimeline {
                if displaySegments.isEmpty {
                    Text("No segments yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(timelineItems(for: displaySegments, ascending: timelineSortAscending)) { item in
                            switch item {
                            case .gap(let id, let duration):
                                timelineGapRow(id: id, duration: duration)
                            case .segment(let segment):
                                timelineRow(for: segment)
                            }
                        }
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 2)
                            .offset(x: timeColumnWidth + (railColumnWidth - 2) / 2)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func timelineRow(for segment: Segment) -> some View {
        let tag = manager.tagForSegment(segment)
        let duration = manager.duration(of: segment, referenceNow: manager.nowTick)
        let durationText = duration < 60 && segment.end == nil ? "<1m" : formattedDuration(duration)
        let isRunning = segment.end == nil
        let runningSince = isRunning ? "Running since \(formattedTime(segment.start))" : nil

        return HStack(spacing: 12) {
            Text(formattedTime(segment.start))
                .font(.system(.subheadline, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth, alignment: .trailing)

            TimelineRailTick(
                tag: tag,
                duration: duration,
                isRunning: isRunning,
                columnWidth: railColumnWidth
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.subheadline)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(tagColor(tag).opacity(0.18), in: Capsule())
                    .foregroundStyle(tagColor(tag))

                if let runningSince {
                    Text(runningSince)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if hoveredSegmentId == segment.id {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(durationText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(isRunning ? .white.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredSegmentId = isHovering ? segment.id : nil
        }
        .onTapGesture {
            editMode = .edit
            editingSegment = segment
        }
        .contextMenu {
            Button("Split…") {
                editMode = .split
                editingSegment = segment
            }
            Button("Change Tag…") {
                tagChangeSegment = segment
                showTagChangeDialog = true
            }
            Button("Delete", role: .destructive) {
                deleteTargetSegment = segment
                showDeleteConfirm = true
            }
        }
    }

    private func longestNonIdleSegmentDuration(segments: [Segment]) -> TimeInterval {
        segments
            .filter { manager.tagForSegment($0).name != TagDefaults.idleName }
            .map { manager.duration(of: $0, referenceNow: manager.nowTick) }
            .max() ?? 0
    }

    private enum TimelineItem: Identifiable {
        case segment(Segment)
        case gap(id: String, duration: TimeInterval)

        var id: String {
            switch self {
            case .segment(let segment):
                return "segment-\(segment.id.uuidString)"
            case .gap(let id, _):
                return "gap-\(id)"
            }
        }
    }

    private func timelineItems(for segments: [Segment], ascending: Bool) -> [TimelineItem] {
        guard !segments.isEmpty else { return [] }
        let sorted = segments.sorted { ascending ? $0.start < $1.start : $0.start > $1.start }
        var items: [TimelineItem] = []
        var previousEnd: Date? = nil

        for segment in sorted {
            if ascending, let previousEnd {
                let gap = segment.start.timeIntervalSince(previousEnd)
                if gap >= 30 * 60 {
                    let id = "\(segment.id.uuidString)-\(segment.start.timeIntervalSince1970)"
                    items.append(.gap(id: id, duration: gap))
                }
            }

            items.append(.segment(segment))
            previousEnd = segment.end ?? manager.nowTick
        }

        return items
    }

    private func timelineGapRow(id: String, duration: TimeInterval) -> some View {
        HStack {
            Spacer()
            Text("— \(formattedDuration(duration)) gap —")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
        .id(id)
    }

    private var isSelectedToday: Bool {
        calendar.isDate(selectedDay, inSameDayAs: Date())
    }

    private func setSelectedDay(_ date: Date) {
        selectedDay = calendar.startOfDay(for: date)
    }

    private func shiftSelectedDay(by days: Int) {
        let base = calendar.startOfDay(for: selectedDay)
        let target = calendar.date(byAdding: .day, value: days, to: base) ?? base
        setSelectedDay(target)
    }

    private func shortDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private var last7DaysSection: some View {
        let activeTotal = manager.activeTimeForWindow(anchoredOn: selectedDay)
        let idleTotal = manager.idleTimeForWindow(anchoredOn: selectedDay)
        let trackedDaysCount = manager.trackedDaysCount(anchoredOn: selectedDay)
        let activeAverage = trackedDaysCount > 0 ? activeTotal / Double(trackedDaysCount) : 0
        let activeTotalsByTag = manager.activeTotalsByTagForWindow(anchoredOn: selectedDay)
        let averageByTag = activeTotalsByTag
            .mapValues { $0 / Double(max(trackedDaysCount, 1)) }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        let idleAverage = trackedDaysCount > 0 ? idleTotal / Double(trackedDaysCount) : 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days — Active Overview")
                .font(.title3)
                .fontWeight(.semibold)

            if activeTotal <= 0 {
                Text("No active time in the last 7 days")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Avg Active (tracked days • \(trackedDaysCount)/7)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(trackedDaysCount > 0 ? formattedDuration(activeAverage) : "—")
                            .fontWeight(.semibold)
                    }
                }

                if activeTotal > 0 {
                    let segments = activeBreakdownSegments(activeTotalsByTag: activeTotalsByTag, activeTotal: activeTotal)
                    if !segments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active breakdown (excludes Idle/Off)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            StackedBarView(segments: segments, barHeight: 12)
                        }
                        .padding(.top, 6)
                    }
                }

                if trackedDaysCount > 0, (!averageByTag.isEmpty || idleAverage > 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Avg per tag (tracked days)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(Array(averageByTag), id: \.key) { entry in
                            let tag = entry.key
                            let average = entry.value
                            if average > 0 {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(tagColor(tag).opacity(0.8))
                                        .frame(width: 8, height: 8)
                                    Text(tag.name)
                                    Spacer()
                                    Text(formattedDuration(average))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }

                        if idleAverage > 0 {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(tagColor(TagDefaults.idleName).opacity(0.8))
                                    .frame(width: 8, height: 8)
                                Text(TagDefaults.idleName)
                                Spacer()
                                Text(formattedDuration(idleAverage))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 140)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func activeBreakdownSegments(activeTotalsByTag: [TagItem: TimeInterval], activeTotal: TimeInterval) -> [StackedBarView.Segment] {
        guard activeTotal > 0 else { return [] }
        let sorted = activeTotalsByTag
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }

        return sorted.map { tag, duration in
            let share = duration / activeTotal
            return StackedBarView.Segment(label: tag.name, color: tagColor(tag), fraction: share, duration: duration)
        }
    }
}

struct TimelineRailTick: View {
    let tag: TagItem
    let duration: TimeInterval
    let isRunning: Bool
    let columnWidth: CGFloat

    @State private var pulse = false

    private var tickHeight: CGFloat {
        let minTick: CGFloat = 6
        let maxTick: CGFloat = 40
        let minutes = max(0, duration / 60)
        let t = min(minutes / 120.0, 1.0)
        return minTick + (maxTick - minTick) * CGFloat(t)
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(tagColor(tag))
                .frame(width: 8, height: tickHeight)

            if isRunning {
                Circle()
                    .fill(tagColor(tag))
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.4 : 1)
                    .opacity(pulse ? 0.3 : 0.9)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
            }
        }
        .frame(width: columnWidth)
        .accessibilityHidden(true)
    }
}

struct StackedBarView: View {
    struct Segment: Identifiable {
        let id = UUID()
        let label: String
        let color: Color
        let fraction: Double
        let duration: TimeInterval
    }

    let segments: [Segment]
    let barHeight: CGFloat
    @State private var hoveredSegmentId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: proxy.size.width * CGFloat(max(0, min(1, segment.fraction))))
                            .overlay(Color.clear.contentShape(Rectangle()))
                            .opacity(hoveredSegmentId == nil || hoveredSegmentId == segment.id ? 1 : 0.6)
                            .onHover { isHovering in
                                hoveredSegmentId = isHovering ? segment.id : nil
                            }
                    }
                }
                .frame(height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: barHeight)

            let totalDuration = segments.reduce(0) { $0 + $1.duration }
            if let hoveredSegment = segments.first(where: { $0.id == hoveredSegmentId }) {
                Text("\(hoveredSegment.label) — \(formattedDuration(hoveredSegment.duration)) (\(formatPercent(hoveredSegment.fraction)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if totalDuration > 0 {
                Text("Total — \(formattedDuration(totalDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
