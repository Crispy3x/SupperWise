#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Add a client in three steps: contact details, the service address, then pricing and whether they agreed to emails.
struct AddCustomerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Called with the new client's id, for example by the New Job sheet.
    var onCreated: ((UUID) -> Void)?

    @State private var step = 0
    @State private var first = ""
    @State private var last = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var agreed = false
    @State private var address = ""
    @State private var priority = 3.0
    @State private var trigger = 2.0
    @State private var seasonal = false
    @State private var rate = 60.0
    @State private var season = 900.0
    @State private var coordinate: Coordinate?
    @State private var locationNote = ""
    @State private var searching = false

    private var fullName: String { [first, last].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ") }
    private var canAdvance: Bool {
        switch step {
        case 0: return !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1: return !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    var body: some View {
        WizardScaffold(title: "Add New Client", steps: ["Contact", "Service address", "Pricing"], step: $step, canAdvance: canAdvance, onClose: { dismiss() }, onFinish: save) {
            switch step {
            case 0:
                SectionLabel(text: "Contact basics")
                PillField(label: "First Name", placeholder: "Jane", text: $first)
                PillField(label: "Last Name", optional: true, placeholder: "Doe", text: $last)
                PillField(label: "Phone Number", placeholder: "(555) 555-1234", text: $phone, kind: .phone)
                PillField(label: "Email", placeholder: "jane@company.com", text: $email, kind: .email)
            case 1:
                SectionLabel(text: "Where we plow")
                PillField(label: "Service address", required: true, placeholder: "14 Elm Ave, Minneapolis", text: $address)
                #if canImport(CoreLocation)
                Button { find() } label: {
                    Label(searching ? "Looking up..." : "Find map location", systemImage: "mappin.and.ellipse").font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 16).background(Look.pill, in: Capsule())
                }
                .buttonStyle(.plain).disabled(searching || address.isEmpty)
                if !locationNote.isEmpty { Text(locationNote).font(.callout).foregroundStyle(.secondary) }
                #endif
                SectionLabel(text: "Service")
                PillStepper(label: "Priority (1 is first)", value: $priority, range: 1...5, step: 1)
                PillStepper(label: "Plow at", value: $trigger, range: 0.5...12, step: 0.5, format: { String(format: "%.1f in", $0) })
            default:
                SectionLabel(text: "How you bill")
                PillChoice(options: [(false, "Per push", nil), (true, "Season", nil)], selection: $seasonal)
                if seasonal { PillStepper(label: "Season price", value: $season, range: 50...50_000, step: 50, format: { "$\(Int($0))" }) }
                else { PillStepper(label: "Price per push", value: $rate, range: 10...1000, step: 5, format: { "$\(Int($0))" }) }
                SectionLabel(text: "Messages")
                Button { if ContactValidation.isValidEmail(email) { agreed.toggle() } } label: {
                    HStack(spacing: 14) {
                        Image(systemName: agreed && ContactValidation.isValidEmail(email) ? "checkmark.circle.fill" : "circle").font(.title2)
                            .foregroundStyle(agreed && ContactValidation.isValidEmail(email) ? Theme.accent(model.data.profile.accentColor) : Color.secondary)
                        Text("This client agreed to storm updates, invoices and their page link by email").font(.title3).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Look.field, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Look.fieldStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Text(ContactValidation.isValidEmail(email) ? "Only tick this if they said yes. They can always ask you to stop." : "Add a valid email on step 1 to turn this on. Nobody is emailed without it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { trigger = model.data.profile.defaultTriggerInches; seasonal = model.data.profile.defaultSnowBilling == .seasonal }
        .onChange(of: address) { coordinate = nil; locationNote = "" }          // a map location belongs to the address it was found for
    }

    #if canImport(CoreLocation)
    private func find() {
        searching = true
        let looked = address
        Task {
            let found = await AddressGeocoder.coordinate(for: looked)
            searching = false
            guard looked == address else { return }
            coordinate = found
            locationNote = found == nil ? "Address not found. The site will be left out of route ordering." : "Map location found."
        }
    }
    #endif

    private func save() {
        let id = model.addCustomerWithSite(name: fullName, phone: phone, email: email, emailConsent: agreed, address: address, priority: Int(priority),
                                           triggerInches: trigger, perPushRate: Money(dollars: Int(rate)), seasonPrice: seasonal ? Money(dollars: Int(season)) : nil, coordinate: coordinate)
        onCreated?(id)
        dismiss()
    }
}
#endif
