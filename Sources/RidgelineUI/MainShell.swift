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
    case quotes, team, revenue, storm, visits, timeClock, proof, settings, profile, subscription, fieldWork, business
    var id: String { rawValue }
    /// Pages keep the Menu bar and the tab bar. The others open on their own with a round back button.
    var isPage: Bool {
        switch self {
        case .quotes, .team, .revenue, .storm, .visits, .timeClock, .proof, .fieldWork, .business: return true
        case .settings, .profile, .subscription: return false
        }
    }
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
        case .subscription: return "Subscription"
        case .fieldWork: return "Field work"
        case .business: return "Business"
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
        case .subscription: return "creditcard"
        case .fieldWork: return "snowflake"
        case .business: return "briefcase"
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
    @State private var tutorialRequired = false

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

    /// A short menu: the tab bar already has Home, Calendar, Jobs, Clients and Requests, so the menu only groups the rest.
    private var menuEntries: [MenuEntry] {
        var out: [MenuEntry] = []
        let d = model.data
        if d.can(.logVisits) || d.can(.useTimeClock) || d.can(.editJobs) {
            out.append(MenuEntry(target: .screen(.fieldWork), title: "Field work", icon: "snowflake"))
        }
        if d.can(.viewQuotes) || d.can(.viewRevenue) || d.can(.viewTeam) {
            out.append(MenuEntry(target: .screen(.business), title: "Business", icon: "briefcase"))
        }
        if d.can(.manageSettings) || d.isOwnerSession { out.append(MenuEntry(target: .screen(.settings), title: "Settings", icon: "gearshape")) }
        return out
    }

    private var notificationCount: Int { Notifications.items(for: model.data, now: Date()).count }

    var body: some View {
        ZStack {
            Look.page.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusBanners()
                if let screen, !screen.isPage {
                    SecondaryScreen(screen: screen) { self.screen = nil }
                } else {
                    topBar
                    if let screen { PageScreen(screen: screen) } else { content }
                }
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    SparkleButton { showAssistant = true }
                }
                .padding(.trailing, 20)
                if screen == nil || screen?.isPage == true {
                    FloatingTabBar(tabs: tabs, selection: screen == nil ? tab : nil) { picked in screen = nil; tab = picked }
                        .padding(.horizontal, 14).padding(.bottom, 10).padding(.top, 8)
                } else {
                    Color.clear.frame(height: 20)
                }
            }
            if menuOpen {
                SideMenu(entries: menuEntries, tab: tab, screen: screen, onSelect: select, onProfile: { menuOpen = false; screen = .profile },
                         onSignOut: { menuOpen = false; model.signOutOfApp() }, onClose: { menuOpen = false })
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            }
            if showTutorial {
                TutorialView(role: role, required: tutorialRequired) { finishTutorial() }.zIndex(3)
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
            if !model.hasSeenTutorial(role) { tutorialRequired = true; showTutorial = true }
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
            HomeView(startTour: { tutorialRequired = false; showTutorial = true }, openScreen: { screen = $0 }, openSmartRoute: { showSmartRoute = true })
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
        tutorialRequired = false
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
    /// The highlighted tab. Nil on a page that is not one of the tabs.
    let selection: ShellTab?
    let onSelect: (ShellTab) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        HStack(spacing: 4) {
            ForEach(tabs) { t in
                Button { onSelect(t) } label: {
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

// MARK: - Screens from the menu

/// A screen that opens on its own: a round back button and a centred title, like Subscription.
private struct SecondaryScreen: View {
    let screen: ShellScreen
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenTopBar(title: screen.title, onBack: onClose)
                destination.pageBackground()
            }
            .environment(\.embeddedInStack, true)
            .hideNavBar()
        }
    }

    @ViewBuilder private var destination: some View {
        switch screen {
        case .settings: SettingsView()
        case .profile: ProfileView()
        case .subscription: SubscriptionView()
        default: EmptyView()
        }
    }
}

/// A page from the menu. It keeps the Menu bar and the tab bar, and starts with the same big title the tabs have.
private struct PageScreen: View {
    let screen: ShellScreen

    var body: some View {
        NavigationStack {
            content
                .environment(\.embeddedInStack, true)
                .hideNavBar()
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .team: TeamView()
        case .revenue: RevenueView()
        case .fieldWork: MenuHub(screen: screen, items: fieldItems)
        case .business: MenuHub(screen: screen, items: businessItems)
        default:
            VStack(spacing: 0) {
                ScreenHeader(icon: screen.icon, title: screen.title, trailing: "")
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                existing.pageBackground().padding(.bottom, Look.tabBarClearance - 40)
            }
        }
    }

    @Environment(AppModel.self) private var model

    private var fieldItems: [HubItem] {
        let d = model.data
        var out: [HubItem] = []
        if d.can(.logVisits) { out.append(HubItem(title: "Log visits", icon: "checkmark.circle", tint: .green, screen: .visits)) }
        if d.can(.logVisits) { out.append(HubItem(title: "Proof of service", icon: "checkmark.seal", tint: .teal, screen: .proof)) }
        if d.can(.useTimeClock) { out.append(HubItem(title: "Time clock", icon: "clock", tint: .orange, screen: .timeClock)) }
        if d.can(.editJobs) { out.append(HubItem(title: "Storm planner", icon: "cloud.snow", tint: .blue, screen: .storm)) }
        return out
    }

    private var businessItems: [HubItem] {
        let d = model.data
        var out: [HubItem] = []
        if d.can(.viewQuotes) { out.append(HubItem(title: "Quotes", icon: "doc.text", tint: .indigo, screen: .quotes)) }
        if d.can(.viewRevenue) { out.append(HubItem(title: "Revenue", icon: "dollarsign.circle", tint: .green, screen: .revenue)) }
        if d.can(.viewTeam) { out.append(HubItem(title: "Team", icon: "person.2.badge.gearshape", tint: .purple, screen: .team)) }
        return out
    }

    @ViewBuilder private var existing: some View {
        switch screen {
        case .quotes: QuotesView()
        case .storm: StormView()
        case .visits: TodayView()
        case .timeClock: TimeClockView()
        case .proof: ProofView()
        default: EmptyView()
        }
    }
}

struct HubItem: Identifiable {
    let title: String
    let icon: String
    let tint: Color
    let screen: ShellScreen
    var id: String { title }
}

/// A menu entry that groups several screens: a big title and one card per screen, each opening on its own with a round back button.
private struct MenuHub: View {
    let screen: ShellScreen
    let items: [HubItem]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ScreenHeader(icon: screen.icon, title: screen.title, trailing: "")
                ForEach(items) { item in
                    NavigationLink { destination(item.screen) } label: {
                        Card(padding: 12) {
                            HStack(spacing: 14) {
                                IconTile(icon: item.icon, tint: item.tint, size: 48)
                                Text(item.title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, Look.tabBarClearance)
        }
        .background(Look.page)
    }

    @ViewBuilder private func destination(_ s: ShellScreen) -> some View {
        Group {
            switch s {
            case .visits: TodayView()
            case .proof: ProofView()
            case .timeClock: TimeClockView()
            case .storm: StormView()
            case .quotes: QuotesView()
            case .revenue: RevenueView()
            case .team: TeamView()
            default: EmptyView()
            }
        }
        .environment(\.embeddedInStack, true)
        .circleBack()
        .pageBackground()
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
