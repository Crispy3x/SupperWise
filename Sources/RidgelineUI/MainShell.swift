#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

enum ShellTab: String, CaseIterable, Identifiable {
    case home, calendar, jobs, clients, requests
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .calendar: return "Calendar"
        case .jobs: return "Jobs"
        case .clients: return "Clients"
        case .requests: return "Requests"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .calendar: return "calendar"
        case .jobs: return "briefcase"
        case .clients: return "person.2"
        case .requests: return "tray"
        }
    }
    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .jobs: return "briefcase.fill"
        case .clients: return "person.2.fill"
        case .requests: return "tray.fill"
        }
    }
}

/// Screens opened from the menu. They show on their own with a Home button to come back.
enum ShellScreen: String, Identifiable {
    case quotes, team, revenue, storm, visits, timeClock, proof, settings, profile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quotes: return "Quotes"
        case .team: return "Team"
        case .revenue: return "Revenue"
        case .storm: return "Storm planner"
        case .visits: return "Log visits"
        case .timeClock: return "Time clock"
        case .proof: return "Proof of service"
        case .settings: return "Settings"
        case .profile: return "Profile"
        }
    }
    var icon: String {
        switch self {
        case .quotes: return "doc.text"
        case .team: return "person.2.badge.gearshape"
        case .revenue: return "dollarsign.circle"
        case .storm: return "cloud.snow"
        case .visits: return "checkmark.circle"
        case .timeClock: return "clock"
        case .proof: return "checkmark.seal"
        case .settings: return "gearshape"
        case .profile: return "person.crop.circle"
        }
    }
}

/// Where a menu entry leads.
private enum MenuTarget: Hashable {
    case tab(ShellTab)
    case screen(ShellScreen)
}

private struct MenuEntry: Identifiable {
    let target: MenuTarget
    let title: String
    let icon: String
    var id: String { title }
}

/// The signed-in app: a top bar with Menu and Notifications, the five main screens on a floating tab bar,
/// a side menu for everything else, and the Smart route button.
struct MainShell: View {
    @Environment(AppModel.self) private var model
    @State private var tab: ShellTab = .home
    @State private var screen: ShellScreen?
    @State private var menuOpen = false
    @State private var showNotifications = false
    @State private var showSmartRoute = false
    @State private var showAssistant = false
    @State private var showTutorial = false
    @State private var tutorialChecked = false

    private var role: SessionRole { model.data.isOwnerSession ? .owner : .employee }

    private var tabs: [ShellTab] {
        ShellTab.allCases.filter { t in
            switch t {
            case .home, .calendar, .jobs: return true
            case .clients: return model.data.can(.viewClients)
            case .requests: return model.data.can(.viewRequests)
            }
        }
    }

    private var menuEntries: [MenuEntry] {
        var out: [MenuEntry] = []
        for t in tabs where t != .clients && t != .requests { out.append(MenuEntry(target: .tab(t), title: t.title, icon: t.icon)) }
        if tabs.contains(.requests) { out.append(MenuEntry(target: .tab(.requests), title: "Requests", icon: "tray")) }
        if model.data.can(.viewQuotes) { out.append(MenuEntry(target: .screen(.quotes), title: "Quotes", icon: "doc.text")) }
        if tabs.contains(.clients) { out.append(MenuEntry(target: .tab(.clients), title: "Clients", icon: "person.2")) }
        if model.data.can(.viewTeam) { out.append(MenuEntry(target: .screen(.team), title: "Team", icon: "person.2.badge.gearshape")) }
        if model.data.can(.viewRevenue) { out.append(MenuEntry(target: .screen(.revenue), title: "Revenue", icon: "dollarsign.circle")) }
        if model.data.can(.editJobs) { out.append(MenuEntry(target: .screen(.storm), title: "Storm planner", icon: "cloud.snow")) }
        if model.data.can(.logVisits) { out.append(MenuEntry(target: .screen(.visits), title: "Log visits", icon: "checkmark.circle")) }
        if model.data.can(.useTimeClock) { out.append(MenuEntry(target: .screen(.timeClock), title: "Time clock", icon: "clock")) }
        if model.data.can(.logVisits) { out.append(MenuEntry(target: .screen(.proof), title: "Proof of service", icon: "checkmark.seal")) }
        if model.data.can(.manageSettings) { out.append(MenuEntry(target: .screen(.settings), title: "Settings", icon: "gearshape")) }
        return out
    }

    private var notificationCount: Int { Notifications.items(for: model.data, now: Date()).count }

    var body: some View {
        ZStack {
            Look.page.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusBanners()
                if let screen {
                    SecondaryScreen(screen: screen) { self.screen = nil }
                } else {
                    topBar
                    content
                }
            }
            if screen == nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        SparkleButton { showAssistant = true }
                    }
                    .padding(.trailing, 20)
                    FloatingTabBar(tabs: tabs, selection: $tab)
                        .padding(.horizontal, 14).padding(.bottom, 10).padding(.top, 8)
                }
            }
            if menuOpen {
                SideMenu(entries: menuEntries, tab: tab, screen: screen, onSelect: select, onProfile: { menuOpen = false; screen = .profile },
                         onSignOut: { menuOpen = false; model.signOutOfApp() }, onClose: { menuOpen = false })
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            }
            if showTutorial {
                TutorialView(role: role) { finishTutorial() }.zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: menuOpen)
        .animation(.easeInOut(duration: 0.2), value: showTutorial)
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet { kind in
                showNotifications = false
                openFromNotification(kind)
            }
        }
        .sheet(isPresented: $showSmartRoute) { SmartRouteSheet() }
        .sheet(isPresented: $showAssistant) { AssistantView() }
        .onAppear {
            guard !tutorialChecked else { return }
            tutorialChecked = true
            if !model.hasSeenTutorial(role) { showTutorial = true }
        }
    }

    // MARK: pieces

    private var topBar: some View {
        HStack {
            PillButton(title: "Menu", icon: "line.3.horizontal") { menuOpen = true }
            Spacer()
            PillButton(title: "Notifications", icon: "bell", badge: notificationCount) { showNotifications = true }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Look.card.opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(Look.stroke).frame(height: 1) }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home:
            HomeView(startTour: { showTutorial = true }, openScreen: { screen = $0 }, openSmartRoute: { showSmartRoute = true })
        case .calendar: CalendarTabView()
        case .jobs: JobsTabView()
        case .clients: ClientsTabView()
        case .requests: RequestsView().padding(.bottom, 0)
        }
    }

    // MARK: actions

    private func select(_ target: MenuTarget) {
        menuOpen = false
        switch target {
        case .tab(let t): screen = nil; tab = t
        case .screen(let s): screen = s
        }
    }

    private func finishTutorial() {
        showTutorial = false
        model.markTutorialSeen(role)
    }

    private func openFromNotification(_ kind: AppNotification.Kind) {
        switch kind {
        case .request: screen = nil; if tabs.contains(.requests) { tab = .requests }
        case .invoice: if model.data.can(.viewRevenue) { screen = .revenue }
        case .job: screen = nil; tab = .home
        case .trial: if model.data.can(.viewRevenue) { screen = .revenue }
        case .team: if model.data.can(.viewTeam) { screen = .team }
        }
    }
}

// MARK: - Banners shown above everything

struct StatusBanners: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.previewingEmployee, let member = model.data.currentMember {
                HStack {
                    Text("Previewing as \(member.name)").font(.footnote.bold())
                    Spacer()
                    Button("Exit preview") { model.exitPreview() }.font(.footnote).buttonStyle(.bordered)
                }
                .padding(8).background(.orange.opacity(0.25))
            }
            if let notice = model.loadNotice {
                VStack(spacing: 4) {
                    Text(notice).font(.footnote)
                    if !model.savingIsBlocked {
                        Button("Dismiss") { model.dismissLoadNotice() }.font(.footnote).buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity).padding(6).background(.red.opacity(0.2))
            }
            if let problem = model.saveError {
                Text(problem).font(.footnote).frame(maxWidth: .infinity).padding(6).background(.red.opacity(0.2))
            }
            if let note = model.notice {
                HStack {
                    Text(note).font(.footnote)
                    Spacer()
                    Button("OK") { model.notice = nil }.font(.footnote).buttonStyle(.bordered)
                }
                .padding(8).background(.green.opacity(0.15))
            }
            SubscriptionBanner()
        }
    }
}

// MARK: - Floating tab bar and Smart route button

struct FloatingTabBar: View {
    let tabs: [ShellTab]
    @Binding var selection: ShellTab
    @Environment(AppModel.self) private var model

    var body: some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        HStack(spacing: 4) {
            ForEach(tabs) { t in
                Button { selection = t } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selection == t ? t.selectedIcon : t.icon).font(.system(size: 20, weight: .medium))
                        if selection == t || tabs.count <= 4 {
                            Text(t.title).font(.system(size: 15, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .foregroundStyle(selection == t ? tint : Color.secondary)
                    .padding(.horizontal, selection == t ? 14 : 8).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(selection == t ? tint.opacity(0.18) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(selection == t ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Look.card.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(Look.stroke, lineWidth: 1))
    }
}

/// The round purple button that opens the assistant.
struct SparkleButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Look.sparkle, in: Circle())
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .accessibilityLabel("Assistant")
    }
}

// MARK: - Side menu

private struct SideMenu: View {
    @Environment(AppModel.self) private var model
    let entries: [MenuEntry]
    let tab: ShellTab
    let screen: ShellScreen?
    let onSelect: (MenuTarget) -> Void
    let onProfile: () -> Void
    let onSignOut: () -> Void
    let onClose: () -> Void

    private var workspace: String {
        guard model.data.isOwnerSession else { return "TEAM MEMBER" }
        switch model.subscriptionState {
        case .active(let tier): return tier == .max ? "MAX WORKSPACE" : "PRO WORKSPACE"
        case .trial: return "FREE TRIAL"
        case .expired: return "TRIAL ENDED"
        }
    }

    private var title: String {
        if let m = model.data.currentMember { return m.name }
        let n = model.data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Ridgeline Ops" : n
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Button(action: onProfile) {
                        HStack(spacing: 14) {
                            IconTile(icon: "snowflake", tint: Theme.accent(model.data.profile.accentColor), size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.title3.bold()).foregroundStyle(.primary).lineLimit(1)
                                Text(workspace).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Close menu")
                }
                .padding(.bottom, 18)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(entries) { entry in
                            let selected = isSelected(entry.target)
                            Button { onSelect(entry.target) } label: {
                                HStack(spacing: 14) {
                                    IconTile(icon: entry.icon, tint: selected ? .white : Theme.accent(model.data.profile.accentColor), size: 46)
                                        .background(selected ? Theme.accent(model.data.profile.accentColor) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    Text(entry.title).font(.title3.weight(.medium))
                                        .foregroundStyle(selected ? Theme.accent(model.data.profile.accentColor) : .primary)
                                    Spacer()
                                }
                                .padding(8)
                                .background(selected ? Look.card : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button(action: onSignOut) {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).padding(.top, 12).padding(.leading, 8)
            }
            .padding(20)
            .frame(width: 330)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Look.page.ignoresSafeArea())
            .overlay(alignment: .trailing) { Rectangle().fill(Look.stroke).frame(width: 1).ignoresSafeArea() }
        }
    }

    private func isSelected(_ target: MenuTarget) -> Bool {
        switch target {
        case .tab(let t): return screen == nil && tab == t
        case .screen(let s): return screen == s
        }
    }
}

// MARK: - A menu screen with its own title bar and a way back

private struct SecondaryScreen: View {
    let screen: ShellScreen
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            destination
                .environment(\.embeddedInStack, true)
                .navigationTitle(screen.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) { Label("Home", systemImage: "chevron.left") }
                    }
                }
        }
    }

    @ViewBuilder private var destination: some View {
        switch screen {
        case .quotes: QuotesView()
        case .team: TeamView()
        case .revenue: RevenueView()
        case .storm: StormView()
        case .visits: TodayView()
        case .timeClock: TimeClockView()
        case .proof: ProofView()
        case .settings: SettingsView()
        case .profile: ProfileView()
        }
    }
}

// MARK: - Notifications

struct NotificationsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onSelect: (AppNotification.Kind) -> Void

    var body: some View {
        let items = Notifications.items(for: model.data, now: Date())
        NavigationStack {
            List {
                if items.isEmpty {
                    Label("You are all caught up.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Button { onSelect(item.kind) } label: {
                        HStack(spacing: 12) {
                            IconTile(icon: icon(item.kind), tint: tint(item.kind), size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.headline).foregroundStyle(.primary)
                                Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func icon(_ k: AppNotification.Kind) -> String {
        switch k {
        case .request: return "tray.full.fill"
        case .invoice: return "doc.text.fill"
        case .job: return "briefcase.fill"
        case .trial: return "gift.fill"
        case .team: return "person.2.fill"
        }
    }
    private func tint(_ k: AppNotification.Kind) -> Color {
        switch k {
        case .request: return .orange
        case .invoice: return .red
        case .job: return .blue
        case .trial: return .purple
        case .team: return .teal
        }
    }
}
#endif
