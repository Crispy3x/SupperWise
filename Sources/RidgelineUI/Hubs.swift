#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Clients: the people you work for, what they ask for, and what you quote them.
struct ClientsHubView: View {
    @Environment(AppModel.self) private var model

    private var pending: Int { model.data.serviceRequests.filter { $0.status == .pending }.count }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink { RequestsView().environment(\.embeddedInStack, true) } label: {
                    HubRow(icon: "tray.full.fill", title: "Requests", subtitle: "Asked for on client pages", badge: pending, tint: .orange)
                }
                NavigationLink { CustomersView().environment(\.embeddedInStack, true) } label: {
                    HubRow(icon: "person.2.fill", title: "Clients", subtitle: "\(model.data.customers.count) clients, \(model.data.sites.count) sites")
                }
                NavigationLink { QuotesView().environment(\.embeddedInStack, true) } label: {
                    HubRow(icon: "text.badge.plus", title: "Quotes", subtitle: "\(model.data.quotes.count) quotes", tint: .teal)
                }
                NavigationLink { RoutesView().environment(\.embeddedInStack, true) } label: {
                    HubRow(icon: "point.topleft.down.curvedto.point.bottomright.up", title: "Crews and routes", subtitle: "\(model.data.crews.count) crews, \(model.data.routes.count) routes", tint: .indigo)
                }
            }
            .navigationTitle("Clients")
        }
    }
}

/// Money: what you have billed, what each site earns, and your plan.
struct MoneyHubView: View {
    @Environment(AppModel.self) private var model

    private var drafts: Int { model.data.invoices.filter { $0.sentAt == nil && !$0.isVoid }.count }
    private var unpaid: Money {
        model.data.invoices.filter { $0.sentAt != nil && !$0.isVoid }.reduce(.zero) { $0 + $1.balance }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Waiting to be paid").font(.footnote).foregroundStyle(.secondary)
                        Text(unpaid.formatted).font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    NavigationLink { InvoicesView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "doc.text.fill", title: "Invoices", subtitle: drafts > 0 ? "\(drafts) drafts to look at" : "\(model.data.invoices.count) invoices", badge: drafts)
                    }
                    NavigationLink { ReportsView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "chart.bar.fill", title: "Job costs", subtitle: "Which sites make money", tint: .green)
                    }
                    NavigationLink { PricingCalculatorView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "dollarsign.circle.fill", title: "Plans and pricing", subtitle: "Pro and Max", tint: .purple)
                    }
                }
            }
            .navigationTitle("Money")
        }
    }
}

/// More: your profile, settings, the time clock and proof of service.
struct MoreView: View {
    @Environment(AppModel.self) private var model

    private var displayName: String {
        let n = model.data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Your business" : n
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { ProfileView() } label: {
                        HStack(spacing: 14) {
                            AvatarView(name: model.data.account?.displayName.isEmpty == false ? model.data.account!.displayName : displayName, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName).font(.headline)
                                Text(model.data.account == nil ? "Not signed in" : (model.data.account?.email.isEmpty == false ? model.data.account!.email : "Signed in with Apple"))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    NavigationLink { TimeClockView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "clock.fill", title: "Time clock", subtitle: "Crew hours by job", tint: .indigo)
                    }
                    NavigationLink { ProofView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "checkmark.seal.fill", title: "Proof of service", subtitle: "Packets for insurers", tint: .green)
                    }
                    NavigationLink { SettingsView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "gearshape.fill", title: "Settings", subtitle: "Invoices, messages, costs, data", tint: .gray)
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

/// A round badge with initials.
struct AvatarView: View {
    @Environment(AppModel.self) private var model
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return parts.isEmpty ? "R" : String(parts).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.accent(model.data.profile.accentColor), in: Circle())
    }
}
#endif
