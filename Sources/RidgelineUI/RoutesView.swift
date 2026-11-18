#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Crews and repeating routes, with changes that move many routes at once.
struct RoutesView: View {
    @Environment(AppModel.self) private var model
    @State private var newCrew = ""
    @State private var newRoute = ""
    @State private var selected: Set<UUID> = []
    @State private var targetCrew: UUID?
    @State private var targetWeekday = 2
    @State private var message: String?

    private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private func crewName(_ id: UUID?) -> String { model.data.crews.first { $0.id == id }?.name ?? "No crew" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Crews") {
                    ForEach(model.data.crews) { Text($0.name) }
                    HStack {
                        TextField("New crew name", text: $newCrew)
                        Button("Add crew") { message = model.edit { try $0.addCrew(name: newCrew) }; if message == nil { newCrew = "" } }
                            .disabled(newCrew.isEmpty)
                    }
                }
                Section("Routes") {
                    if model.data.routes.isEmpty { Text("No routes yet.").foregroundStyle(.secondary) }
                    ForEach(model.data.routes) { route in
                        HStack(alignment: .top) {
                            Button {
                                if selected.contains(route.id) { selected.remove(route.id) } else { selected.insert(route.id) }
                            } label: {
                                Image(systemName: selected.contains(route.id) ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.name).font(.headline)
                                Text("\(crewName(route.crewID)), \(route.weekday.map { weekdays[$0 - 1] } ?? "any day"), \(route.stopSiteIDs.count) stops")
                                    .font(.footnote).foregroundStyle(.secondary)
                                let free = model.data.sites.filter { !route.stopSiteIDs.contains($0.id) }
                                if !free.isEmpty {
                                    Menu("Add a site") {
                                        ForEach(free) { site in
                                            Button(site.address) {
                                                model.edit { $0.routes = RouteBook.moveSites($0.routes, siteIDs: [site.id], toRoute: route.id) }
                                            }
                                        }
                                    }
                                    .font(.footnote)
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("New route name", text: $newRoute)
                        Button("Add route") { message = model.edit { try $0.addRoute(name: newRoute) }; if message == nil { newRoute = "" } }
                            .disabled(newRoute.isEmpty)
                    }
                }
                Section("Move \(selected.count) selected") {
                    Picker("To crew", selection: $targetCrew) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(model.data.crews) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Move to this crew") {
                        if let crew = targetCrew {
                            model.edit { $0.routes = RouteBook.move($0.routes, ids: selected, toCrew: crew) }
                        }
                    }
                    .disabled(selected.isEmpty || targetCrew == nil)
                    Picker("To day", selection: $targetWeekday) {
                        ForEach(1...7, id: \.self) { Text(weekdays[$0 - 1]).tag($0) }
                    }
                    Button("Move to this day") {
                        model.edit { $0.routes = RouteBook.move($0.routes, ids: selected, toWeekday: targetWeekday) }
                    }
                    .disabled(selected.isEmpty)
                }
                if let message { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Routes")
        }
    }
}
#endif
