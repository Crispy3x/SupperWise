#if canImport(SwiftUI)
import SwiftUI
import Observation
import RidgelineCore
#if canImport(CoreLocation)
import CoreLocation
#endif

extension AppModel {
    /// A route stop's map label with "Here" or "Next" in front while auto check-in is on.
    func autoCheckInLabel(_ base: String, for id: UUID) -> String {
        #if canImport(CoreLocation)
        let c = AutoCheckInController.shared
        guard c.isOn else { return base }
        if c.currentStopID == id { return "Here: " + base }
        if c.nextStopID == id { return "Next: " + base }
        #endif
        return base
    }
}

#if canImport(CoreLocation)
/// A visit waiting to be logged after an automatic arrival.
struct AutoVisitDraft: Identifiable, Equatable {
    /// The job id.
    let id: UUID
    let siteID: UUID
    let address: String
    let arrivedAt: Date
}

/// Automatic check-in: while it is on and the app is open, it watches the phone's position, saves the arrival and
/// departure time on each of today's jobs, and moves the route on to the next stop. When In Use permission only,
/// no background location. The decisions are made by `ArrivalTracker` (RidgelineCore/AutoCheckIn.swift).
@MainActor @Observable
final class AutoCheckInController: NSObject, CLLocationManagerDelegate {
    static let shared = AutoCheckInController()

    private(set) var isOn = false
    private(set) var note = ""
    /// "Arrived at 14 Elm Ave"
    private(set) var banner: String?
    /// "Next: 22 Oak St, 6 min"
    private(set) var nextLine: String?
    private(set) var stops: [CheckInStop] = []
    private(set) var finishedIDs: Set<UUID> = []
    private(set) var currentStopID: UUID?
    private(set) var nextStopID: UUID?
    /// The visit started by the last arrival, until it is logged.
    var draft: AutoVisitDraft?
    /// A job the crew left while "mark done when the crew leaves" is off: waiting for a yes or a not yet.
    var askDone: CheckInStop?
    /// The day of the visit `askDone` is about. Not always today: a visit started before midnight belongs to the day before.
    private(set) var askDoneDay = Date()

    @ObservationIgnored private var tracker: ArrivalTracker?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private weak var model: AppModel?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Fixes keep coming while parked, so the 45 second wait at a site can finish.
        manager.distanceFilter = kCLDistanceFilterNone
        #if os(iOS)
        manager.activityType = .automotiveNavigation
        #endif
    }

    func turnOn(model: AppModel) {
        guard !isOn else { return }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            note = "Location is off for this app. Turn it on in Settings, then try again."
            return
        }
        self.model = model
        let route = model.data.autoCheckInStops(on: Date(), plan: model.plannedRoute)
        guard !route.isEmpty else {
            note = "No stops for you today with a map location."
            return
        }
        let saved = model.data.savedCheckIns(for: route, on: Date())
        tracker = ArrivalTracker(stops: route, arrivedIDs: saved.arrived, finishedIDs: saved.finished)
        isOn = true
        banner = nil
        note = "Waiting for your position..."
        publish()
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func turnOff(note: String = "") {
        manager.stopUpdatingLocation()
        isOn = false
        tracker = nil
        banner = nil
        nextLine = nil
        stops = []
        finishedIDs = []
        currentStopID = nil
        nextStopID = nil
        self.note = note
    }

    /// Picks up a re-planned route or changed jobs, keeping arrivals already made.
    func refreshStops() {
        guard isOn, let model, var t = tracker else { return }
        t.updateStops(model.data.autoCheckInStops(on: Date(), plan: model.plannedRoute))
        tracker = t
        publish()
    }

    /// Clears the draft once its visit is in the log.
    func clearDraftIfLogged(in data: AppData) {
        guard let d = draft else { return }
        if data.visitLog.records(forSite: d.siteID).contains(where: { $0.arrival == d.arrivedAt }) { draft = nil }
    }

    private func publish() {
        guard let t = tracker else { return }
        stops = t.stops
        finishedIDs = t.finishedIDs
        currentStopID = t.currentStopID
        nextStopID = t.nextStop?.id
        if let next = t.nextStop {
            let line = CheckInText.next(next.name, seconds: t.secondsToNextStop())
            if line != nextLine { nextLine = line }
        } else {
            nextLine = t.isRouteDone ? CheckInText.routeDone : nil
        }
    }

    private func handle(_ location: CLLocation) {
        guard isOn, var t = tracker, let model else { return }
        let fix = LocationFix(coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                              accuracyMeters: location.horizontalAccuracy, timestamp: location.timestamp)
        let events = t.ingest(fix)
        tracker = t
        let goodFix = location.horizontalAccuracy >= 0 && location.horizontalAccuracy < t.rules.maxAccuracyMeters
        let status = goodFix ? "Watching for arrivals." : "Waiting for a clearer GPS signal."
        if note != status { note = status }
        for event in events { apply(event, model: model) }
        publish()
        if tracker?.isRouteDone == true && events.contains(where: { if case .departed = $0 { return true } else { return false } }) {
            turnOff(note: CheckInText.routeDone)
        }
    }

    private func apply(_ event: CheckInEvent, model: AppModel) {
        switch event {
        case .arrived(let id, let at):
            guard let stop = tracker?.stop(id) else { return }
            if let problem = model.edit({ _ = try $0.recordArrival(jobID: id, at: at) }) {
                note = problem
                return
            }
            let line = CheckInText.arrived(stop.name)
            banner = line
            model.notice = line
            if let siteID = stop.siteID {
                draft = AutoVisitDraft(id: id, siteID: siteID, address: stop.name, arrivedAt: at)
            }
        case .departed(let id, let at):
            guard let stop = tracker?.stop(id) else { return }
            let markDone = model.data.autoCheckInMarksDone
            var visitDay = at
            if let problem = model.edit({ visitDay = try $0.recordDeparture(jobID: id, at: at, markDone: markDone) }) {
                note = problem
                return
            }
            let stillOpen = model.data.jobs.first(where: { $0.id == id })?.occurrenceStatus(on: visitDay).isOpen ?? false
            if !markDone && stillOpen {
                askDone = stop
                askDoneDay = visitDay
            }
            banner = CheckInText.left(stop.name)
            refreshStops()
            publish()
            var line = CheckInText.left(stop.name) + (markDone ? ", marked done." : ".")
            if let next = nextLine { line += " " + next }
            if askDone != nil { line += " Open Home to mark it done." }
            model.notice = line
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { self.handle(location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in if self.isOn { self.note = "Could not find your position. Still trying." } }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if self.isOn && (status == .denied || status == .restricted) {
                self.turnOff(note: "Location was turned off, so auto check-in stopped.")
            }
        }
    }
}

/// The "Auto check-in" switch with today's stops, the latest arrival and the next stop. Shown on Home and on the
/// Smart route sheet.
struct AutoCheckInCard: View {
    @Environment(AppModel.self) private var model
    @State private var visit: AutoVisitDraft?

    @MainActor private var checkIn: AutoCheckInController { AutoCheckInController.shared }
    private var todayStops: [CheckInStop] { model.data.autoCheckInStops(on: Date(), plan: model.plannedRoute) }

    private var footer: String {
        var text = "Works while the app is open. A stop counts as arrived after 45 seconds within about 200 feet, and as left past about 400 feet."
        if !model.data.isOwnerSession {
            text += model.data.autoCheckInMarksDone ? " Jobs are marked done when you leave." : " You are asked before a job is marked done."
        }
        return text
    }

    var body: some View {
        let shown = checkIn.isOn ? checkIn.stops : todayStops
        if model.data.can(.logVisits) && (checkIn.isOn || !shown.isEmpty || checkIn.draft != nil || checkIn.askDone != nil) {
            VStack(spacing: 16) {
                if let left = checkIn.askDone { askDoneCard(left) }
                if let draft = checkIn.draft {
                    PrimaryActionButton(title: "Log visit at \(draft.address)", icon: "square.and.pencil") { visit = draft }
                }
                CardGroup(footer: footer) {
                    Toggle(isOn: Binding(get: { checkIn.isOn }, set: { on in
                        if on { checkIn.turnOn(model: model) } else { checkIn.turnOff() }
                    })) {
                        Label("Auto check-in", systemImage: "location.circle.fill").font(.headline)
                    }
                    if checkIn.isOn {
                        if let banner = checkIn.banner { statusRow(icon: "mappin.circle.fill", tint: .green, text: banner) }
                        if let next = checkIn.nextLine { statusRow(icon: "arrow.turn.up.right", tint: .blue, text: next) }
                    }
                    if !checkIn.note.isEmpty {
                        Text(checkIn.note).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !shown.isEmpty {
                        RowDivider()
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, stop in
                            stopRow(number: i + 1, stop: stop)
                        }
                    }
                    if model.data.isOwnerSession {
                        RowDivider()
                        Toggle("Mark the job done when the crew leaves", isOn: Binding(get: { model.data.autoCheckInMarksDone }, set: { on in
                            _ = model.edit { try $0.setAutoCheckInMarksDone(on) }
                        }))
                    }
                }
            }
            .onChange(of: model.plannedRoute) { checkIn.refreshStops() }
            .onChange(of: model.data.jobs) { checkIn.refreshStops() }
            .sheet(item: $visit, onDismiss: { checkIn.clearDraftIfLogged(in: model.data) }) { draft in
                if let site = model.data.sites.first(where: { $0.id == draft.siteID }) {
                    VisitSheet(site: site, stormID: model.visitStormName, arrivedAt: draft.arrivedAt)   // TodayView.swift
                }
            }
        }
    }

    private func statusRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 12) {
            IconTile(icon: icon, tint: tint, size: 36)
            Text(text).font(.headline)
            Spacer(minLength: 0)
        }
    }

    private func stopRow(number: Int, stop: CheckInStop) -> some View {
        let here = checkIn.isOn && checkIn.currentStopID == stop.id
        let next = checkIn.isOn && checkIn.nextStopID == stop.id
        let left = checkIn.finishedIDs.contains(stop.id)
        return HStack(spacing: 10) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(stop.name).fontWeight(here || next ? .semibold : .regular).foregroundStyle(left ? Color.secondary : Color.primary)
            Spacer()
            if here {
                StatusPill(text: "Here", color: .orange)
            } else if next {
                StatusPill(text: "Next", color: .blue)
            } else if left {
                StatusPill(text: "Left", color: .green)
            }
        }
    }

    private func askDoneCard(_ stop: CheckInStop) -> some View {
        CardGroup(title: "You left \(stop.name)") {
            Text("Mark this job done?").font(.headline)
            PrimaryActionButton(title: "Mark done", icon: "checkmark") {
                // The visit's own day, so a repeating job left after midnight (or answered later) marks the right visit.
                if let problem = model.setOccurrenceStatus(.done, id: stop.id, on: checkIn.askDoneDay) { model.notice = problem }
                checkIn.askDone = nil
            }
            SecondaryActionButton(title: "Not yet") { checkIn.askDone = nil }
        }
    }
}
#endif
#endif
