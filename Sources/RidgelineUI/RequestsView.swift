#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// What clients asked for on their pages. Nothing changes your route until you accept.
struct RequestsView: View {
    @Environment(AppModel.self) private var model
    @State private var note: String?
    @State private var working = false
    @State private var decliningID: UUID?
    @State private var declineText = ""

    private var pending: [ServiceRequest] {
        model.data.serviceRequests.filter { $0.status == .pending }.sorted { $0.createdAt < $1.createdAt }
    }
    private var answered: [ServiceRequest] {
        model.data.serviceRequests.filter { $0.status != .pending }.sorted { ($0.decidedAt ?? $0.createdAt) > ($1.decidedAt ?? $1.createdAt) }
    }

    private func address(_ r: ServiceRequest) -> String {
        model.data.sites.first { $0.id == r.siteID }?.address ?? "Unknown site"
    }

    var body: some View {
        ScreenStack {
            List {
                Section {
                    Button(working ? "Checking..." : "Check for new requests") {
                        Task {
                            working = true
                            note = await model.refreshRequests()
                            working = false
                        }
                    }
                    .disabled(working)
                    if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Waiting for you") {
                    if pending.isEmpty { Text("Nothing waiting.").foregroundStyle(.secondary) }
                    ForEach(pending) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(address(r)).font(.headline)
                                Spacer()
                                if r.kind == .urgent { StatusPill(text: "Urgent", color: .orange) }
                            }
                            Text(r.kind.title + (r.urgentReason.map { ": " + $0.title } ?? "")).font(.subheadline)
                            if !r.note.isEmpty { Text("\"\(r.note)\"").font(.footnote).foregroundStyle(.secondary) }
                            Text(r.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if r.kind == .thanks {
                                Button("Mark read") { accept(r) }.buttonStyle(.borderedProminent).font(.footnote)
                            } else {
                                HStack {
                                    Button("Accept") { accept(r) }.buttonStyle(.borderedProminent)
                                    Button("Decline") { declineText = ""; decliningID = r.id }.buttonStyle(.bordered)
                                }
                                .font(.footnote)
                            }
                            if r.kind == .urgent {
                                Text("Accepting moves this site to the top of today's list.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                if !answered.isEmpty {
                    Section("Answered") {
                        ForEach(answered.prefix(20)) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(address(r))
                                    Spacer()
                                    StatusPill(text: r.status == .accepted ? "Accepted" : "Declined", color: r.status == .accepted ? .green : .gray)
                                }
                                Text(r.kind.title).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Requests")
            .alert("Decline this request?", isPresented: Binding(get: { decliningID != nil }, set: { _ in })) {
                TextField("Message to the client (optional)", text: $declineText)
                Button("Decline", role: .destructive) {
                    if let id = decliningID {
                        let text = declineText.isEmpty ? "We can't take this one right now." : declineText
                        decliningID = nil
                        Task { note = await model.decideRequest(id, accept: false, message: text) }
                    }
                }
                Button("Cancel", role: .cancel) { decliningID = nil }
            }
        }
    }

    private func accept(_ r: ServiceRequest) {
        let text = r.kind == .thanks ? "" : r.kind == .urgent ? "You are near the top of our list." : (r.kind == .skip ? "We will skip your property this storm." : "We will come as soon as we can.")
        Task { note = await model.decideRequest(r.id, accept: true, message: text) }
    }
}
#endif
