import Foundation
import SwiftUI
import Combine
import AppKit
import SwiftData

@MainActor
final class TimerManager: ObservableObject {
    private let trackedDayThreshold: TimeInterval = 30 * 60

    @Published private(set) var segments: [Segment] = []
    @Published private(set) var nowTick: Date = Date()
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var tags: [TagItem] = []
    @Published private(set) var allTags: [TagItem] = []

    private let calendar = Calendar.current
    private let store: SegmentStore
    private var timerCancellable: AnyCancellable?
    private var storeCancellable: AnyCancellable?
    private var tagsCancellable: AnyCancellable?
    private var lastActiveRefresh: Date?
    private var isHandlingActive = false
    private var popoverVisible = false
    private var dashboardVisible = false
    private let activeTickInterval: TimeInterval = 5
    private let inactiveTickInterval: TimeInterval = 60
    private var totalsCache: [Date: [TagItem: TimeInterval]] = [:]
    private var totalTrackedCache: [Date: TimeInterval] = [:]
    private var undoState: UndoState? {
        didSet { canUndo = undoState != nil }
    }

    struct UndoState {
        let removedSegmentId: UUID
        let restoredSegmentId: UUID
        let restoredPreviousEnd: Date?
    }

    init(modelContext: ModelContext) {
        store = SegmentStore(modelContext: modelContext)
        segments = store.segments
        tags = store.visibleTags
        allTags = store.tags
        storeCancellable = store.$segments
            .receive(on: RunLoop.main)
            .sink { [weak self] updated in
                self?.segments = updated
                self?.invalidateCaches()
            }
        tagsCancellable = store.$tags
            .receive(on: RunLoop.main)
            .sink { [weak self] updated in
                self?.allTags = updated
                self?.tags = updated.filter { !$0.isHidden }.sorted { $0.order < $1.order }
                self?.invalidateCaches()
            }
        startTicking()
    }

    var currentSegment: Segment? {
        store.currentSegment
    }

    var currentTag: TagItem {
        store.currentTagItem
    }


    var menuBarTitle: String {
        "\(currentTag.name) · \(formattedElapsed(for: currentSegment, now: nowTick))"
    }

    func handleAppBecameActive() {
        let now = Date()
        if let lastActiveRefresh, now.timeIntervalSince(lastActiveRefresh) < 120 {
            return
        }
        guard !isHandlingActive else { return }
        isHandlingActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            let startOfToday = self.calendar.startOfDay(for: now)
            let needsRollover = self.segments.contains { $0.end == nil && $0.start < startOfToday }
            let needsNormalization = self.segments.contains {
                guard let end = $0.end else { return false }
                return !self.calendar.isDate($0.start, inSameDayAs: end)
            }
            if needsRollover {
                self.store.checkDayRollover(shouldContinueTag: true, now: now)
            }
            if needsNormalization {
                self.store.normalizeSegmentsAcrossMidnight()
            }
            self.lastActiveRefresh = now
            self.isHandlingActive = false
        }
    }

    func switchTag(to tag: TagItem) {
        store.checkDayRollover(shouldContinueTag: true, now: Date())
        let now = Date()
        if let undoInfo = store.switchTag(to: tag, now: now) {
            undoState = UndoState(
                removedSegmentId: undoInfo.removedSegmentId,
                restoredSegmentId: undoInfo.restoredSegmentId,
                restoredPreviousEnd: undoInfo.restoredPreviousEnd
            )
        } else {
            undoState = nil
        }
    }

    func undoLastSwitch() {
        guard let undoState else { return }
        store.undoLastSwitch(
            removedSegmentId: undoState.removedSegmentId,
            restoredSegmentId: undoState.restoredSegmentId,
            restoredPreviousEnd: undoState.restoredPreviousEnd
        )
        self.undoState = nil
    }

    func endDayAndReset() {
        store.endDayAndReset(now: Date())
        undoState = nil
    }

    func totalsForToday() -> [TagItem: TimeInterval] {
        totalsByTag(for: nowTick)
    }

    func segments(for date: Date) -> [Segment] {
        store.segments(for: date)
    }

    func totalsByTag(for date: Date) -> [TagItem: TimeInterval] {
        let day = calendar.startOfDay(for: date)
        if let cached = totalsCache[day] {
            return cached
        }
        let totals = store.totalsByTag(for: day, referenceNow: nowTick)
        totalsCache[day] = totals
        return totals
    }

    func totalTracked(for date: Date) -> TimeInterval {
        let day = calendar.startOfDay(for: date)
        if let cached = totalTrackedCache[day] {
            return cached
        }
        let total = store.totalTracked(for: day, referenceNow: nowTick)
        totalTrackedCache[day] = total
        return total
    }

    func focusedTimeForDay(_ day: Date) -> TimeInterval {
        let totals = totalsByTag(for: day)
        return sumTotals(totals, for: ["Work", "School", "Training"])
    }

    func maintenanceTimeForDay(_ day: Date) -> TimeInterval {
        let totals = totalsByTag(for: day)
        return sumTotals(totals, for: ["Food", "Personal Care", "Recovery / Mind", "Social / Admin"])
    }

    func idleTimeForDay(_ day: Date) -> TimeInterval {
        let totals = totalsByTag(for: day)
        return totals.first(where: { $0.key.name == TagDefaults.idleName })?.value ?? 0
    }

    func activeTimeForDay(_ day: Date) -> TimeInterval {
        focusedTimeForDay(day) + maintenanceTimeForDay(day)
    }

    func activeTime(for day: Date) -> TimeInterval {
        activeTimeForDay(day)
    }

    func activeTimeForWindow(anchoredOn day: Date) -> TimeInterval {
        windowDays(anchoredOn: day).reduce(0) { $0 + activeTimeForDay($1) }
    }

    func focusedTimeForWindow(anchoredOn day: Date) -> TimeInterval {
        windowDays(anchoredOn: day).reduce(0) { $0 + focusedTimeForDay($1) }
    }

    func maintenanceTimeForWindow(anchoredOn day: Date) -> TimeInterval {
        windowDays(anchoredOn: day).reduce(0) { $0 + maintenanceTimeForDay($1) }
    }

    func idleTimeForWindow(anchoredOn day: Date) -> TimeInterval {
        windowDays(anchoredOn: day).reduce(0) { $0 + idleTimeForDay($1) }
    }

    func totalsByTagForWindow(anchoredOn day: Date) -> [TagItem: TimeInterval] {
        var totals: [TagItem: TimeInterval] = Dictionary(uniqueKeysWithValues: allTags.map { ($0, 0) })
        for windowDay in windowDays(anchoredOn: day) {
            let dayTotals = totalsByTag(for: windowDay)
            for (tag, value) in dayTotals {
                totals[tag, default: 0] += value
            }
        }
        return totals
    }

    func activeTotalsByTagForWindow(anchoredOn day: Date) -> [TagItem: TimeInterval] {
        let totals = totalsByTagForWindow(anchoredOn: day)
        return totals.filter { $0.key.name != TagDefaults.idleName && $0.value > 0 }
    }

    func trackedDaysCount(anchoredOn day: Date) -> Int {
        windowDays(anchoredOn: day).filter { activeTimeForDay($0) >= trackedDayThreshold }.count
    }

    func dominantActiveTag(for day: Date) -> TagItem? {
        let totals = totalsByTag(for: day)
        let activeTotals = totals.filter { $0.key.name != TagDefaults.idleName && $0.value > 0 }
        return activeTotals.max(by: { $0.value < $1.value })?.key
    }

    func lastNDays(n: Int) -> [Date] {
        let startOfToday = calendar.startOfDay(for: nowTick)
        return (0..<max(1, n)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: startOfToday)
        }
    }

    private func windowDays(anchoredOn day: Date) -> [Date] {
        let start = calendar.startOfDay(for: day)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: start)
        }
    }

    func duration(of segment: Segment, referenceNow: Date = Date()) -> TimeInterval {
        store.duration(of: segment, referenceNow: referenceNow)
    }

    func cleanSegments(_ segments: [Segment]) -> [Segment] {
        store.cleanSegments(segments, referenceNow: nowTick)
    }

    func tagForSegment(_ segment: Segment) -> TagItem {
        store.tagForSegment(segment)
    }

    func formattedElapsed(for segment: Segment?, now: Date) -> String {
        guard let segment else { return "0m" }
        let end = segment.end ?? now
        let duration = max(0, end.timeIntervalSince(segment.start))
        return formattedDuration(duration)
    }

    func updateSegment(id: UUID, tag: TagItem, start: Date, end: Date?, note: String?) throws {
        try store.updateSegment(id: id, tag: tag, start: start, end: end, note: note, referenceNow: nowTick)
    }

    func validationErrorForEdit(id: UUID, tag: TagItem, start: Date, end: Date?) -> String? {
        store.validationErrorForEdit(id: id, tag: tag, start: start, end: end, referenceNow: nowTick)
    }

    func deleteSegment(id: UUID) {
        store.deleteSegment(id: id, now: Date())
    }

    func splitSegment(id: UUID, at splitTime: Date, beforeTag: TagItem, afterTag: TagItem) throws {
        try store.splitSegment(id: id, at: splitTime, beforeTag: beforeTag, afterTag: afterTag, referenceNow: nowTick)
    }

    func mergeAdjacent(for day: Date) {
        store.mergeAdjacent(for: day, referenceNow: nowTick)
    }

    func moveTags(from source: IndexSet, to destination: Int) {
        store.moveTags(from: source, to: destination)
    }

    func saveTagChanges() {
        store.saveTagChanges()
    }

    private func startTicking() {
        restartTicking(interval: inactiveTickInterval)
    }

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        updateTickingForVisibility()
    }

    func setDashboardVisible(_ visible: Bool) {
        dashboardVisible = visible
        updateTickingForVisibility()
    }

    private func updateTickingForVisibility() {
        let interval = (popoverVisible || dashboardVisible) ? activeTickInterval : inactiveTickInterval
        restartTicking(interval: interval)
        nowTick = Date()
        invalidateCache(for: Date())
    }

    private func restartTicking(interval: TimeInterval) {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: interval, tolerance: interval * 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                self.nowTick = now
                if self.currentSegment != nil {
                    self.invalidateCache(for: now)
                }
            }
    }

    private func sumTotals(_ totals: [TagItem: TimeInterval], for names: [String]) -> TimeInterval {
        totals.reduce(0) { partial, entry in
            names.contains(entry.key.name) ? partial + entry.value : partial
        }
    }

    private func invalidateCaches() {
        totalsCache.removeAll()
        totalTrackedCache.removeAll()
    }

    private func invalidateCache(for day: Date) {
        let start = calendar.startOfDay(for: day)
        totalsCache[start] = nil
        totalTrackedCache[start] = nil
    }
}
