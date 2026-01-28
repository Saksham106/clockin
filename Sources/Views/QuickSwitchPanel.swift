import SwiftUI
import AppKit

final class QuickSwitchPanelController {
    static let shared = QuickSwitchPanelController()

    private var panel: NSPanel?

    func show(manager: TimerManager) {
        if panel == nil {
            panel = makePanel(manager: manager)
        } else if let hosting = panel?.contentViewController as? NSHostingController<QuickSwitchView> {
            hosting.rootView = QuickSwitchView(manager: manager)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(manager: TimerManager) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.title = "Switch Tag"
        panel.center()
        panel.contentViewController = NSHostingController(rootView: QuickSwitchView(manager: manager))
        return panel
    }
}

struct QuickSwitchView: View {
    @ObservedObject var manager: TimerManager

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switch Tag")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(manager.tags) { tag in
                        Button(tag.name) {
                        manager.switchTag(to: tag)
                        QuickSwitchPanelController.shared.close()
                        NSApp.setActivationPolicy(.accessory)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    QuickSwitchPanelController.shared.close()
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
        .padding(12)
    }
}
