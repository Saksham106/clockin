import SwiftUI

struct EditSegmentSheet: View {
    @EnvironmentObject private var manager: TimerManager
    @Environment(\.dismiss) private var dismiss

    enum InitialMode {
        case edit
        case split
    }

    let segment: Segment
    let day: Date
    let initialMode: InitialMode

    @State private var selectedTag: TagItem = TagItem(name: TagDefaults.idleName, order: 0, isHidden: false, isSystem: true)
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var isRunning: Bool = false
    @State private var noteText: String = ""
    @State private var splitEnabled: Bool = false
    @State private var splitTime: Date = Date()
    @State private var splitBeforeTag: TagItem = TagItem(name: TagDefaults.idleName, order: 0, isHidden: false, isSystem: true)
    @State private var splitAfterTag: TagItem = TagItem(name: TagDefaults.idleName, order: 0, isHidden: false, isSystem: true)
    @State private var splitErrorMessage: String?
    @State private var showDeleteConfirm: Bool = false
    @State private var showSplitTagPickers: Bool = false
    @State private var highlightSplit: Bool = false

    private let calendar = Calendar.current

    var body: some View {
        let startDate = combine(day: day, time: startTime)
        let endDate = isRunning ? nil : combine(day: day, time: endTime)
        let validationError = manager.validationErrorForEdit(id: segment.id, tag: selectedTag, start: startDate, end: endDate)
        let durationEnd = isRunning ? manager.nowTick : (endDate ?? manager.nowTick)
        let durationText = formattedDuration(max(0, durationEnd.timeIntervalSince(startDate)))

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(tagColor(selectedTag))
                    .frame(width: 10, height: 10)
                Text(selectedTag.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                if isRunning {
                    Text("• Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Duration · \(durationText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Tag", selection: $selectedTag) {
                ForEach(manager.allTags) { tag in
                    Text(tag.name).tag(tag)
                }
            }
            .pickerStyle(.menu)

            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
            Toggle("Running", isOn: $isRunning)

            DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                .disabled(isRunning)

            if isRunning {
                Text("Ends at now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Split segment", isOn: $splitEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: splitEnabled) { _, enabled in
                        if enabled {
                            showSplitTagPickers = true
                        }
                    }
                Text("Splitting creates two segments at the chosen time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(splitEnabled ? 1 : 0.6)

                if splitEnabled {
                    HStack(spacing: 12) {
                        Text("Split at")
                        DatePicker("", selection: $splitTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }

                    if showSplitTagPickers || splitBeforeTag != splitAfterTag {
                        HStack(spacing: 12) {
                            Picker("Before", selection: $splitBeforeTag) {
                                ForEach(manager.allTags) { tag in
                                    Text(tag.name).tag(tag)
                                }
                            }
                            .pickerStyle(.menu)

                            Text("→")
                                .foregroundStyle(.secondary)

                            Picker("After", selection: $splitAfterTag) {
                                ForEach(manager.allTags) { tag in
                                    Text(tag.name).tag(tag)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text("Before \(splitBeforeTag.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("→")
                                .foregroundStyle(.secondary)
                            Text("After \(splitAfterTag.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let splitErrorMessage {
                        Text(splitErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(12)
            .background(highlightSplit ? .white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Note (optional)", text: $noteText)

            HStack {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
                .keyboardShortcut(.delete, modifiers: [.command])

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    do {
                        try manager.updateSegment(id: segment.id, tag: selectedTag, start: startDate, end: endDate, note: noteText.isEmpty ? nil : noteText)
                        if splitEnabled {
                            let splitDate = combine(day: day, time: splitTime)
                            try manager.splitSegment(id: segment.id, at: splitDate, beforeTag: splitBeforeTag, afterTag: splitAfterTag)
                        }
                        dismiss()
                    } catch {
                        splitErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to save segment."
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .onAppear {
            selectedTag = manager.tagForSegment(segment)
            startTime = segment.start
            let end = segment.end ?? manager.nowTick
            endTime = end
            isRunning = segment.end == nil
            noteText = segment.note ?? ""
            splitEnabled = false
            splitTime = defaultSplitTime(for: segment, end: end)
            splitBeforeTag = selectedTag
            splitAfterTag = selectedTag
            showSplitTagPickers = false
            highlightSplit = initialMode == .split
        }
        .confirmationDialog("Delete Segment?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                manager.deleteSegment(id: segment.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func defaultSplitTime(for segment: Segment, end: Date) -> Date {
        if segment.end == nil {
            let elapsed = max(0, manager.nowTick.timeIntervalSince(segment.start))
            let midpoint = segment.start.addingTimeInterval(elapsed / 2)
            let latest = manager.nowTick.addingTimeInterval(-5 * 60)
            let minSplit = segment.start.addingTimeInterval(60)
            return max(minSplit, min(midpoint, latest))
        }
        let mid = segment.start.addingTimeInterval(end.timeIntervalSince(segment.start) / 2)
        return mid
    }

    private func combine(day: Date, time: Date) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        return calendar.date(from: merged) ?? time
    }
}
