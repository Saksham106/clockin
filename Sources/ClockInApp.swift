import SwiftUI
import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct ClockInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Segment.self, TagItem.self)
        } catch {
            preconditionFailure("Failed to create SwiftData container: \(error)")
        }
    }()
    private let modelContainer: ModelContainer
    @StateObject private var manager: TimerManager

    init() {
        modelContainer = Self.sharedModelContainer
        _manager = StateObject(wrappedValue: TimerManager(modelContext: Self.sharedModelContainer.mainContext))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(manager)
        } label: {
            Text(manager.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)

        Window("Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(manager)
        }
        .modelContainer(modelContainer)
    }
}
