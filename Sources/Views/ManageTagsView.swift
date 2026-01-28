import SwiftUI

struct ManageTagsView: View {
    @EnvironmentObject private var manager: TimerManager
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedTagId: UUID?
    @State private var hoveredTagId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manage Tags")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(manager.allTags) { tag in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(tagColor(tag).opacity(0.8))
                                .frame(width: 8, height: 8)

                            if tag.isSystem {
                                Text(tag.name)
                                    .fontWeight(.semibold)
                            } else {
                                HStack(spacing: 6) {
                                    Button {
                                        focusedTagId = tag.id
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    TextField("Tag name", text: Binding(
                                        get: { tag.name },
                                        set: { tag.name = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    ))
                                    .textFieldStyle(.plain)
                                    .focused($focusedTagId, equals: tag.id)
                                }
                            }

                            Spacer()

                            Toggle("Show", isOn: Binding(
                                get: { !tag.isHidden },
                                set: { tag.isHidden = !$0 }
                            ))
                            .labelsHidden()
                            .disabled(tag.isSystem)
                            .help(tag.isSystem ? "System tag is always shown." : "Uncheck to hide this tag from quick switching.")

                            VStack(spacing: 4) {
                                Button {
                                    moveTag(tag, direction: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.caption)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(.white.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                                .disabled(tag.isSystem || !canMove(tag, direction: -1))

                                Button {
                                    moveTag(tag, direction: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(.white.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                                .disabled(tag.isSystem || !canMove(tag, direction: 1))
                            }
                            .frame(width: 20)
                        }
                        .padding(10)
                        .background(
                            (focusedTagId == tag.id || hoveredTagId == tag.id) && !tag.isSystem
                                ? .white.opacity(0.08)
                                : .white.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .onHover { isHovering in
                            hoveredTagId = isHovering ? tag.id : nil
                        }
                    }
                }
            }
            .frame(minHeight: 280)

            HStack {
                Text("Idle / Off is fixed and always visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    manager.saveTagChanges()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
        .onDisappear {
            manager.saveTagChanges()
        }
    }

    private func canMove(_ tag: TagItem, direction: Int) -> Bool {
        guard let index = manager.allTags.firstIndex(of: tag) else { return false }
        let nextIndex = index + direction
        return nextIndex >= 0 && nextIndex < manager.allTags.count
    }

    private func moveTag(_ tag: TagItem, direction: Int) {
        guard let index = manager.allTags.firstIndex(of: tag) else { return }
        let destination = index + direction
        guard destination >= 0 && destination < manager.allTags.count else { return }
        manager.moveTags(from: IndexSet(integer: index), to: destination)
    }
}
