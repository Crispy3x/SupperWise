#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Keeps the phone's waiting reminders in step with the data. Whenever the data changes (after a short pause, so a burst
/// of edits plans once), on launch and when the app comes back to the front, it removes this app's waiting reminders and
/// adds the ones `LocalReminderPlanner` says are due. Nothing leaves the device.
@MainActor
final class LocalReminderScheduler {
    static let shared = LocalReminderScheduler()

    private var work: Task<Void, Never>?
    private var lastForecast: WeatherWindowSummary?
    private var forecastLoadedAt: Date?

    /// Remembers when a new forecast showed up, since the forecast itself carries no time.
    func noteForecast(_ forecast: WeatherWindowSummary?) {
        guard forecast != lastForecast else { return }
        lastForecast = forecast
        forecastLoadedAt = forecast == nil ? nil : Date()
    }

    private var outlook: SnowOutlook? {
        guard let f = lastForecast, let at = forecastLoadedAt else { return nil }
        return SnowOutlook(snowInches: f.snowfallInches, loadedAt: at)
    }

    /// Plans again after `delay`. A newer call cancels a waiting one.
    func refresh(_ data: AppData, after delay: Duration = .seconds(2)) {
        work?.cancel()
        let outlook = self.outlook
        work = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self.apply(data, outlook: outlook)
        }
    }

    private func apply(_ data: AppData, outlook: SnowOutlook?) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let planned = LocalReminderPlanner.plan(data: data, now: Date(), forecast: outlook)
        // The forecast lives in memory only. After a relaunch there is none, so keep a snow heads-up already waiting.
        let stormID = LocalReminderPlanner.idPrefix + "storm"
        let keepStorm = outlook == nil && data.profile.remindersOn && data.session != nil && data.isOwnerSession
        let waiting = await center.pendingNotificationRequests()
        let old = waiting.map(\.identifier).filter { $0.hasPrefix(LocalReminderPlanner.idPrefix) && !(keepStorm && $0 == stormID) }
        if !old.isEmpty { center.removePendingNotificationRequests(withIdentifiers: old) }
        guard !planned.isEmpty, !Task.isCancelled else { return }

        // Reminders are on, so ask the phone once. The phone only ever shows this question one time.
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional, !Task.isCancelled else { return }

        let calendar = Calendar.current
        for r in planned {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.threadIdentifier = r.kind.rawValue
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
        #endif
    }

    /// Asks for permission if it was never asked. Returns false when notifications are blocked for the app.
    func requestPermission() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional:
            return true
        default:
            return false
        }
        #else
        return false
        #endif
    }

    /// True when the user said no to notifications for this app.
    func isBlocked() async -> Bool {
        #if canImport(UserNotifications)
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        #else
        return false
        #endif
    }
}

/// Hooks the scheduler to the app: on launch, on every data change, when a forecast loads and when the app comes back.
struct LocalRemindersModifier: ViewModifier {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { LocalReminderScheduler.shared.refresh(model.data, after: .zero) }
            .onChange(of: model.data) { LocalReminderScheduler.shared.refresh(model.data) }
            .onChange(of: model.forecast) {
                LocalReminderScheduler.shared.noteForecast(model.forecast)
                LocalReminderScheduler.shared.refresh(model.data)
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { LocalReminderScheduler.shared.refresh(model.data, after: .zero) }
            }
    }
}

extension View {
    /// Keeps phone reminders up to date. Put this once on the root view.
    func localReminders(_ model: AppModel) -> some View { modifier(LocalRemindersModifier(model: model)) }
}

/// The Reminders card near the top of Settings.
struct RemindersSettingsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var blocked = false

    private var explanation: String {
        if model.data.isOwnerSession {
            return "Tomorrow's first job at 7 PM the night before, invoices the morning they go overdue, a heads-up when the forecast reaches your lowest trigger, and a note 2 days before your free trial ends."
        }
        return "Your boss turns these on. You get your first job for tomorrow at 7 PM the night before."
    }

    var body: some View {
        CardGroup(title: "Reminders") {
            if model.data.isOwnerSession {
                Toggle("Send reminders to this phone",
                       isOn: Binding(get: { model.data.profile.remindersOn }, set: { turn($0) }))
            } else {
                FactRow(label: "Reminders", value: model.data.profile.remindersOn ? "On" : "Off")
            }
            Text(explanation).font(.footnote).foregroundStyle(.secondary)
            if blocked && model.data.profile.remindersOn {
                Text("Notifications are off for this app. Turn them on in your phone's Settings app.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        .task { blocked = await LocalReminderScheduler.shared.isBlocked() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { blocked = await LocalReminderScheduler.shared.isBlocked() } }
        }
    }

    private func turn(_ on: Bool) {
        model.data.profile.remindersEnabled = on
        model.save()
        guard on else { blocked = false; return }
        Task {
            blocked = !(await LocalReminderScheduler.shared.requestPermission())
            LocalReminderScheduler.shared.refresh(model.data, after: .zero)
        }
    }
}
#endif
