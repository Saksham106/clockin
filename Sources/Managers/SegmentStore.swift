import Foundation
import SwiftData

@MainActor
final class SegmentStore: ObservableObject {
    @Published private(set) var segments: [Segment] = []
    @Published private(set) var tags: [TagItem] = []

    private let modelContext: ModelContext
    private let calendar = Calendar.current
    private let defaultsKey = "ClockIn.Segments"
    private let migrationFlagKey = "ClockIn.DidMigrateToSwiftData"
    private let tagMigrationFlagKey = "ClockIn.DidMigrateTagIds"
    private let normalizationDayKey = "ClockIn.LastNormalizationDay"
    private var saveWorkItem: DispatchWorkItem?

    struct SegmentEditError: LocalizedError {
        enum Kind {
            case invalidRange
            case overlap
            case invalidSplit
        }

        let kind: Kind

        var errorDescription: String? {
            switch kind {
            case .invalidRange:
                return "Start must be before end."
            case .overlap:
                return "Segment overlaps another segment."
            case .invalidSplit:
                return "Split time must be inside the segment."
            }
        }
    }

    private struct LegacySegment: Codable {
        let id: UUID
        let tag: String
        let start: Date
        let end: Date?
        let note: String?
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshTags()
        ensureDefaultTags()
        refreshTags()
        refreshSegments()
        migrateLegacyIfNeeded()
        migrateSegmentsToTagIdsIfNeeded()
        ensureSingleRunningSegmentOnLaunch()
        normalizeSegmentsAcrossMidnight()
    }

    var currentSegment: Segment? {
        segments.last(where: { $0.end == nil })
    }

    var currentTagItem: TagItem {
        if let current = currentSegment, let tag = tag(for: current.tagId) {
            return tag
        }
        return idleTag
    }

    var idleTag: TagItem {
        if let tag = tags.first(where: { $0.isSystem || $0.name == TagDefaults.idleName }) {
            return tag
        }
        let created = TagItem(name: TagDefaults.idleName, order: (tags.map { $0.order }.max() ?? -1) + 1, isHidden: false, isSystem: true)
        modelContext.insert(created)
        tags.append(created)
        tags.sort { $0.order < $1.order }
        saveContext(immediate: true)
        return created
    }

    var visibleTags: [TagItem] {
        tags.filter { !$0.isHidden }.sorted { $0.order < $1.order }
    }

    func tagForSegment(_ segment: Segment) -> TagItem {
        tag(for: segment.tagId) ?? idleTag
    }

    func moveTags(from source: IndexSet, to destination: Int) {
        var ordered = tags.sorted { $0.order < $1.order }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, tag) in ordered.enumerated() {
            tag.order = index
        }
        tags = ordered
        saveContext()
    }

    func saveTagChanges() {
        saveContext(immediate: true)
        refreshTags()
    }

    func switchTag(to tag: TagItem, now: Date) -> (removedSegmentId: UUID, restoredSegmentId: UUID, restoredPreviousEnd: Date?)? {
        guard tag.id != currentTagItem.id else { return nil }
        guard let activeIndex = segments.lastIndex(where: { $0.end == nil }) else {
            startNewSegment(tag: tag, start: now)
            return nil
        }

        let previousId = segments[activeIndex].id
        let previousEnd = segments[activeIndex].end
        segments[activeIndex].end = now

        let newSegment = Segment(tagId: tag.id, tag: tag.name, start: now)
        modelContext.insert(newSegment)
        segments.append(newSegment)
        saveContext()
        return (newSegment.id, previousId, previousEnd)
    }

    func undoLastSwitch(removedSegmentId: UUID, restoredSegmentId: UUID, restoredPreviousEnd: Date?) {
        if let removed = segments.first(where: { $0.id == removedSegmentId }) {
            modelContext.delete(removed)
        }
        segments.removeAll(where: { $0.id == removedSegmentId })

        if let index = segments.firstIndex(where: { $0.id == restoredSegmentId }) {
            segments[index].end = restoredPreviousEnd
        }
        saveContext()
    }

    func endDayAndReset(now: Date) {
        checkDayRollover(shouldContinueTag: true, now: now)
        if let index = segments.lastIndex(where: { $0.end == nil }) {
            segments[index].end = now
        }
        startNewSegment(tag: idleTag, start: now, save: false)
        saveContext()
    }

    func segments(for date: Date) -> [Segment] {
        segments
            .filter { calendar.isDate($0.start, inSameDayAs: date) }
            .sorted { $0.start < $1.start }
    }

    func totalsByTag(for date: Date, referenceNow: Date) -> [TagItem: TimeInterval] {
        var totals: [TagItem: TimeInterval] = Dictionary(uniqueKeysWithValues: tags.map { ($0, 0) })
        let cleaned = cleanSegments(segments(for: date), referenceNow: referenceNow)
        for segment in cleaned {
            let tag = tag(for: segment.tagId) ?? idleTag
            let duration = max(0, duration(of: segment, referenceNow: referenceNow))
            totals[tag, default: 0] += duration
        }
        return totals
    }

    func totalTracked(for date: Date, referenceNow: Date) -> TimeInterval {
        totalsByTag(for: date, referenceNow: referenceNow).values.reduce(0, +)
    }

    func duration(of segment: Segment, referenceNow: Date) -> TimeInterval {
        let end = segment.end ?? referenceNow
        return max(0, end.timeIntervalSince(segment.start))
    }

    func cleanSegments(_ segments: [Segment], referenceNow: Date) -> [Segment] {
        let sorted = segments
            .sorted { $0.start < $1.start }
            .map { cloneSegment($0) }
        var result: [Segment] = []

        for segment in sorted {
            let segDuration = duration(of: segment, referenceNow: referenceNow)
            if let last = result.last {
                let gap = segment.start.timeIntervalSince(last.end ?? segment.start)
                if sameTag(last, segment) && gap <= 60 {
                    if let lastEnd = last.end, let segmentEnd = segment.end {
                        last.end = max(lastEnd, segmentEnd)
                    } else {
                        last.end = nil
                    }
                    result[result.count - 1] = last
                    continue
                }
            }

            if segDuration < 60, segment.end != nil {
                if let last = result.last, sameTag(last, segment) {
                    if let lastEnd = last.end, let segmentEnd = segment.end {
                        last.end = max(lastEnd, segmentEnd)
                    } else {
                        last.end = nil
                    }
                    result[result.count - 1] = last
                }
                continue
            }

            result.append(segment)
        }

        return result
    }

    func updateSegment(id: UUID, tag: TagItem, start: Date, end: Date?, note: String?, referenceNow: Date) throws {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        if let end, start >= end {
            throw SegmentEditError(kind: .invalidRange)
        }

        let candidate = Segment(id: id, tagId: tag.id, tag: tag.name, start: start, end: end, note: note)
        if hasOverlap(candidate, excluding: id, referenceNow: referenceNow) {
            throw SegmentEditError(kind: .overlap)
        }

        if end == nil {
            for i in segments.indices where segments[i].end == nil && segments[i].id != id {
                segments[i].end = start
            }
        }

        let segment = segments[index]
        segment.tagId = tag.id
        segment.tag = tag.name
        segment.start = start
        segment.end = end
        segment.note = note

        segments.sort { $0.start < $1.start }
        saveContext()
    }

    func validationErrorForEdit(id: UUID, tag: TagItem, start: Date, end: Date?, referenceNow: Date) -> String? {
        if let end, start >= end {
            return SegmentEditError(kind: .invalidRange).errorDescription
        }
        let candidate = Segment(id: id, tagId: tag.id, tag: tag.name, start: start, end: end, note: nil)
        if hasOverlap(candidate, excluding: id, referenceNow: referenceNow) {
            return SegmentEditError(kind: .overlap).errorDescription
        }
        return nil
    }

    func deleteSegment(id: UUID, now: Date) {
        let wasActive = segments.first(where: { $0.id == id })?.end == nil
        if let existing = segments.first(where: { $0.id == id }) {
            modelContext.delete(existing)
        }
        segments.removeAll(where: { $0.id == id })
        if wasActive {
            startNewSegment(tag: idleTag, start: now)
        }
        saveContext()
    }

    func splitSegment(id: UUID, at splitTime: Date, beforeTag: TagItem, afterTag: TagItem, referenceNow: Date) throws {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        let segment = segments[index]
        let end = segment.end ?? referenceNow
        let normalizedSplit = normalizedToMinute(splitTime)
        let normalizedStart = normalizedToMinute(segment.start)
        let normalizedEnd = normalizedToMinute(end)
        guard normalizedSplit > normalizedStart, normalizedSplit < normalizedEnd else {
            throw SegmentEditError(kind: .invalidSplit)
        }

        let first = Segment(tagId: beforeTag.id, tag: beforeTag.name, start: segment.start, end: splitTime, note: segment.note)
        let secondEnd = segment.end
        let second = Segment(tagId: afterTag.id, tag: afterTag.name, start: splitTime, end: secondEnd, note: segment.note)
        modelContext.insert(first)
        modelContext.insert(second)
        modelContext.delete(segment)

        segments.remove(at: index)
        segments.append(contentsOf: [first, second])
        segments.sort { $0.start < $1.start }
        saveContext()
    }

    func mergeAdjacent(for day: Date, referenceNow: Date) {
        let daySegments = segments(for: day)
        let cleaned = cleanSegments(daySegments, referenceNow: referenceNow)
        let idsToRemove = Set(daySegments.map { $0.id })
        for segment in segments where idsToRemove.contains(segment.id) {
            modelContext.delete(segment)
        }
        segments.removeAll(where: { idsToRemove.contains($0.id) })
        for segment in cleaned {
            let tagName = tag(for: segment.tagId)?.name ?? segment.tag
            let merged = Segment(tagId: segment.tagId, tag: tagName, start: segment.start, end: segment.end, note: segment.note)
            modelContext.insert(merged)
            segments.append(merged)
        }
        segments.sort { $0.start < $1.start }
        saveContext()
    }

    func checkDayRollover(shouldContinueTag: Bool, now: Date) {
        guard let activeIndex = segments.lastIndex(where: { $0.end == nil }) else { return }
        let startOfToday = calendar.startOfDay(for: now)
        let activeStart = segments[activeIndex].start
        guard activeStart < startOfToday else { return }

        let tagToContinue = tag(for: segments[activeIndex].tagId) ?? idleTag

        if shouldContinueTag {
            let startOfActiveDay = calendar.startOfDay(for: activeStart)
            var boundary = calendar.date(byAdding: .day, value: 1, to: startOfActiveDay) ?? startOfToday
            segments[activeIndex].end = min(boundary, startOfToday)

            while boundary < startOfToday {
                let nextBoundary = calendar.date(byAdding: .day, value: 1, to: boundary) ?? startOfToday
                let segment = Segment(tagId: tagToContinue.id, tag: tagToContinue.name, start: boundary, end: min(nextBoundary, startOfToday))
                modelContext.insert(segment)
                segments.append(segment)
                boundary = nextBoundary
            }
            startNewSegment(tag: tagToContinue, start: startOfToday, save: false)
        } else {
            segments[activeIndex].end = startOfToday
            startNewSegment(tag: idleTag, start: startOfToday, save: false)
        }
        saveContext()
    }

    func normalizeSegmentsAcrossMidnight() {
        let today = calendar.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: normalizationDayKey) as? Date,
           calendar.isDate(last, inSameDayAs: today) {
            return
        }

        var normalized: [Segment] = []
        var segmentsToDelete: [Segment] = []
        var didChange = false

        for segment in segments {
            guard let end = segment.end else {
                normalized.append(segment)
                continue
            }
            if calendar.isDate(segment.start, inSameDayAs: end) {
                normalized.append(segment)
                continue
            }

            didChange = true
            segmentsToDelete.append(segment)

            let tagName = tag(for: segment.tagId)?.name ?? segment.tag
            var currentStart = segment.start
            var boundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: currentStart)) ?? end
            while boundary < end {
                let newSegment = Segment(tagId: segment.tagId, tag: tagName, start: currentStart, end: boundary, note: segment.note)
                modelContext.insert(newSegment)
                normalized.append(newSegment)
                currentStart = boundary
                boundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: currentStart)) ?? end
            }
            let finalSegment = Segment(tagId: segment.tagId, tag: tagName, start: currentStart, end: end, note: segment.note)
            modelContext.insert(finalSegment)
            normalized.append(finalSegment)
        }

        if didChange {
            for segment in segmentsToDelete {
                modelContext.delete(segment)
            }
            segments = normalized.sorted { $0.start < $1.start }
            saveContext(immediate: true)
        }
        UserDefaults.standard.set(today, forKey: normalizationDayKey)
    }

    func ensureSingleRunningSegmentOnLaunch() {
        let activeSegments = segments.filter { $0.end == nil }.sorted { $0.start < $1.start }
        let now = Date()
        guard let newestActive = activeSegments.last else {
            startNewSegment(tag: idleTag, start: now, save: false)
            return
        }

        if activeSegments.count > 1 {
            for active in activeSegments.dropLast() {
                if let index = segments.firstIndex(where: { $0.id == active.id }) {
                    segments[index].end = newestActive.start
                }
            }
        }

        if let lastIndex = segments.firstIndex(where: { $0.id == newestActive.id }) {
            let startOfToday = calendar.startOfDay(for: now)
            if segments[lastIndex].start < startOfToday {
                segments[lastIndex].end = startOfToday
                startNewSegment(tag: idleTag, start: startOfToday, save: false)
            }
        }
        saveContext(immediate: true)
    }

    private func startNewSegment(tag: TagItem, start: Date, save: Bool = true) {
        let segment = Segment(tagId: tag.id, tag: tag.name, start: start)
        modelContext.insert(segment)
        segments.append(segment)
        if save {
            saveContext()
        }
    }

    private func refreshSegments() {
        let descriptor = FetchDescriptor<Segment>(sortBy: [SortDescriptor(\.start)])
        segments = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func refreshTags() {
        let descriptor = FetchDescriptor<TagItem>(sortBy: [SortDescriptor(\.order), SortDescriptor(\.name)])
        tags = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func ensureDefaultTags() {
        guard tags.isEmpty else {
            _ = idleTag
            return
        }

        for (index, def) in TagDefaults.definitions.enumerated() {
            let tag = TagItem(name: def.name, order: index, isHidden: false, isSystem: def.isSystem)
            modelContext.insert(tag)
            tags.append(tag)
        }
        saveContext(immediate: true)
    }

    private func migrateLegacyIfNeeded() {
        if UserDefaults.standard.bool(forKey: migrationFlagKey) { return }

        if !segments.isEmpty {
            UserDefaults.standard.set(true, forKey: migrationFlagKey)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }

        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            UserDefaults.standard.set(true, forKey: migrationFlagKey)
            return
        }

        do {
            let decoded = try JSONDecoder().decode([LegacySegment].self, from: data)
            for legacy in decoded {
                let tag = tagForName(legacy.tag)
                let segment = Segment(id: legacy.id, tagId: tag.id, tag: tag.name, start: legacy.start, end: legacy.end, note: legacy.note)
                modelContext.insert(segment)
                segments.append(segment)
            }
            segments.sort { $0.start < $1.start }
            saveContext(immediate: true)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } catch {
            UserDefaults.standard.set(true, forKey: migrationFlagKey)
            return
        }

        UserDefaults.standard.set(true, forKey: migrationFlagKey)
    }

    private func migrateSegmentsToTagIdsIfNeeded() {
        if UserDefaults.standard.bool(forKey: tagMigrationFlagKey) { return }

        var didChange = false
        for segment in segments where segment.tagId == nil {
            let tag = tagForName(segment.tag)
            segment.tagId = tag.id
            segment.tag = tag.name
            didChange = true
        }

        if didChange {
            saveContext(immediate: true)
        }
        UserDefaults.standard.set(true, forKey: tagMigrationFlagKey)
    }

    private func saveContext(immediate: Bool = false) {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try self.modelContext.save()
            } catch {
                // No-op for MVP
            }
        }
        saveWorkItem = work
        if immediate {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    private func hasOverlap(_ candidate: Segment, excluding id: UUID, referenceNow: Date) -> Bool {
        let candidateEnd = candidate.end ?? referenceNow
        return segments.contains { segment in
            guard segment.id != id else { return false }
            let end = segment.end ?? referenceNow
            let normalizedCandidateStart = normalizedToMinute(candidate.start)
            let normalizedCandidateEnd = normalizedToMinute(candidateEnd)
            let normalizedStart = normalizedToMinute(segment.start)
            let normalizedEnd = normalizedToMinute(end)
            return normalizedCandidateStart < normalizedEnd && normalizedCandidateEnd > normalizedStart
        }
    }

    private func normalizedToMinute(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }

    private func cloneSegment(_ segment: Segment) -> Segment {
        Segment(id: segment.id, tagId: segment.tagId, tag: segment.tag, start: segment.start, end: segment.end, note: segment.note)
    }

    private func tagForName(_ name: String) -> TagItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? "Untitled" : trimmed
        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) {
            return existing
        }
        let order = (tags.map { $0.order }.max() ?? -1) + 1
        let isSystem = resolvedName == TagDefaults.idleName
        let tag = TagItem(name: resolvedName, order: order, isHidden: false, isSystem: isSystem)
        modelContext.insert(tag)
        tags.append(tag)
        tags.sort { $0.order < $1.order }
        return tag
    }

    private func tag(for id: UUID?) -> TagItem? {
        guard let id else { return nil }
        return tags.first(where: { $0.id == id })
    }

    private func sameTag(_ lhs: Segment, _ rhs: Segment) -> Bool {
        if let lhsId = lhs.tagId, let rhsId = rhs.tagId {
            return lhsId == rhsId
        }
        return lhs.tag == rhs.tag
    }
}
