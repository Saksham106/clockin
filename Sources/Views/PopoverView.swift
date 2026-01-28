import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject private var manager: TimerManager
    @Environment(\.openWindow) private var openWindow

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(manager.currentTag.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(manager.formattedElapsed(for: manager.currentSegment, now: manager.nowTick))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(manager.tags) { tag in
                    Button(action: { manager.switchTag(to: tag) }) {
                        Text(tag.name)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tagColor(tag).opacity(manager.currentTag.id == tag.id ? 0.35 : 0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tagColor(tag).opacity(manager.currentTag.id == tag.id ? 0.8 : 0.2), lineWidth: 1)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                let totals = manager.totalsForToday()
                    .filter { $0.value > 0 }
                    .sorted { $0.value > $1.value }

                if totals.isEmpty {
                    Text("No tracked time")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(totals, id: \.key) { entry in
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
                        .font(.caption)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Open Dashboard") {
                    openWindow(id: "dashboard")
                    DispatchQueue.main.async {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        if let dashboardWindow = NSApp.windows.first(where: { $0.title == "Dashboard" }) {
                            dashboardWindow.makeKeyAndOrderFront(nil)
                            dashboardWindow.orderFrontRegardless()
                        }
                    }
                }
                .fixedSize()

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .fixedSize()
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.handleAppBecameActive()
        }
        .onAppear {
            manager.setPopoverVisible(true)
        }
        .onDisappear {
            manager.setPopoverVisible(false)
        }
    }
}
