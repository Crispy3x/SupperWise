import Foundation

/// How a service is charged.
public enum PriceUnit: String, Codable, CaseIterable, Sendable {
    case visit, season, job, hour

    /// Short words for the screen, for example "per visit".
    public var title: String {
        switch self {
        case .visit: return "per visit"
        case .season: return "per season"
        case .job: return "per job"
        case .hour: return "per hour"
        }
    }
}

/// One service on the owner's price list, for example "Driveway push, $45 per visit".
public struct ServicePrice: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var price: Money
    public var unit: PriceUnit

    public init(id: UUID = UUID(), name: String, price: Money, unit: PriceUnit = .visit) {
        self.id = id
        self.name = name
        self.price = price
        self.unit = unit
    }
}

/// Suggested starting prices, picked from the services the owner chose in the welcome questions.
public enum PriceList {
    /// Fixed ids so the suggested list is the same every time it is built (screens can keep a selection).
    static func presetID(_ n: Int) -> UUID {
        let digits = String(n)
        let text = "00000000-0000-4000-8000-" + String(repeating: "0", count: max(12 - digits.count, 0)) + digits
        return UUID(uuidString: text) ?? UUID()
    }

    public static let snowPresets: [ServicePrice] = [
        ServicePrice(id: presetID(1), name: "Driveway push", price: Money(dollars: 45), unit: .visit),
        ServicePrice(id: presetID(2), name: "Sidewalk shovel", price: Money(dollars: 25), unit: .visit),
        ServicePrice(id: presetID(3), name: "Salting", price: Money(dollars: 35), unit: .visit),
        ServicePrice(id: presetID(4), name: "Seasonal driveway", price: Money(dollars: 450), unit: .season),
    ]

    public static let lawnPresets: [ServicePrice] = [
        ServicePrice(id: presetID(11), name: "Lawn mow", price: Money(dollars: 40), unit: .visit),
        ServicePrice(id: presetID(12), name: "Trim and edge", price: Money(dollars: 25), unit: .visit),
        ServicePrice(id: presetID(13), name: "Spring cleanup", price: Money(dollars: 150), unit: .job),
        ServicePrice(id: presetID(14), name: "Fall cleanup", price: Money(dollars: 175), unit: .job),
    ]

    static let snowKinds: Set<ServiceKind> = [.snowPlowing, .salting, .shoveling]
    static let lawnKinds: Set<ServiceKind> = [.mowing, .landscaping]

    /// Snow services give the snow list, lawn services the lawn list, both give both (snow first).
    /// If neither is picked (only "other"), both lists are offered so there is something to start from.
    public static func presets(for services: Set<ServiceKind>) -> [ServicePrice] {
        let snow = !services.isDisjoint(with: snowKinds)
        let lawn = !services.isDisjoint(with: lawnKinds)
        if snow && !lawn { return snowPresets }
        if lawn && !snow { return lawnPresets }
        return snowPresets + lawnPresets
    }

    /// Most services a list may hold, so a stuck button cannot fill the file.
    public static let maxServices = 60
}

/// A service picked on the Quick invoice screen, with how many and the price for this invoice.
public struct QuickInvoicePick: Equatable, Sendable {
    public var service: ServicePrice
    public var quantity: Int

    public init(service: ServicePrice, quantity: Int) {
        self.service = service
        self.quantity = quantity
    }
}

public enum QuickInvoiceError: Error, Equatable {
    case clientNotFound
    case noAddress
    case nothingPicked
    case zeroTotal

    /// A plain sentence for the owner.
    public var message: String {
        switch self {
        case .clientNotFound: return "Pick a client first."
        case .noAddress: return "Enter the service address for this client."
        case .nothingPicked: return "Tap at least one service."
        case .zeroTotal: return "The total is $0. Set a price first."
        }
    }
}

public enum QuickInvoice {
    public static let maxQuantity = 999

    /// One invoice line per picked service (quantity above zero), in the order picked.
    /// "Driveway push" for one, "Driveway push x 3 ($45.00 each)" for more.
    public static func lines(_ picks: [QuickInvoicePick]) -> [InvoiceLineItem] {
        picks.compactMap { pick in
            let qty = min(pick.quantity, maxQuantity)
            guard qty > 0 else { return nil }
            let trimmed = pick.service.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? "Service" : String(trimmed.prefix(80))
            let price = Money(cents: max(pick.service.price.cents, 0))
            let description = qty == 1 ? name : "\(name) x \(qty) (\(price.formatted) each)"
            return InvoiceLineItem(description: description, amount: price * qty)
        }
    }

    public static func total(_ picks: [QuickInvoicePick]) -> Money {
        lines(picks).reduce(.zero) { $0 + $1.amount }
    }
}

extension AppData {
    /// The owner's services and prices. Until they change it, it follows the services picked in the welcome questions.
    public var priceList: [ServicePrice] { servicePrices ?? PriceList.presets(for: profile.services) }

    /// Saves an edited price list. Prices below zero become zero, and the list is capped in length.
    public mutating func setPriceList(_ list: [ServicePrice]) {
        servicePrices = Array(list.prefix(PriceList.maxServices)).map { (s: ServicePrice) -> ServicePrice in
            var copy = s
            copy.price = Money(cents: max(s.price.cents, 0))
            copy.name = String(s.name.prefix(80))
            return copy
        }
    }

    /// Adds a blank service to the end of the list and returns its id.
    @discardableResult
    public mutating func addService(name: String = "New service", price: Money = .zero, unit: PriceUnit = .visit) -> UUID? {
        var list = priceList
        guard list.count < PriceList.maxServices else { return nil }
        let service = ServicePrice(name: name, price: price, unit: unit)
        list.append(service)
        setPriceList(list)
        return service.id
    }

    public mutating func removeService(id: UUID) {
        setPriceList(priceList.filter { $0.id != id })
    }

    /// Goes back to the suggested list for the services on the profile.
    public mutating func resetPriceList() { servicePrices = nil }

    /// True until the first invoice exists: Home shows "Send your first invoice".
    public var needsFirstInvoice: Bool { invoices.isEmpty }

    /// Makes a draft invoice from picked services. Uses the given address (if it belongs to the client), else the
    /// client's first address, else saves `newAddress` as the client's first address. Due date follows the payment terms.
    @discardableResult
    public mutating func createQuickInvoice(customerID: UUID, siteID: UUID? = nil, newAddress: String = "",
                                            picks: [QuickInvoicePick], note: String = "", now: Date) throws -> Invoice {
        guard customers.contains(where: { $0.id == customerID }) else { throw QuickInvoiceError.clientNotFound }
        let lines = QuickInvoice.lines(picks)
        guard !lines.isEmpty else { throw QuickInvoiceError.nothingPicked }
        let total = lines.reduce(Money.zero) { $0 + $1.amount }
        guard total.cents > 0 else { throw QuickInvoiceError.zeroTotal }

        let site: Site
        if let siteID, let chosen = sites.first(where: { $0.id == siteID && $0.customerID == customerID }) {
            site = chosen
        } else if let first = sites.first(where: { $0.customerID == customerID }) {
            site = first
        } else {
            let address = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { throw QuickInvoiceError.noAddress }
            site = Site(customerID: customerID, address: String(address.prefix(200)), triggerInches: profile.defaultTriggerInches)
            sites.append(site)
            ensurePortalLinks(now: now)
        }

        let number = InvoiceNumbering.next(existing: invoices.map(\.number))
        let days = min(max(profile.netDays, 0), 120)
        let invoice = Invoice(number: number, customerID: customerID, siteID: site.id, issueDate: now,
                              dueDate: now.addingTimeInterval(Double(days) * 86_400), lines: lines,
                              notes: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)))
        invoices.append(invoice)
        return invoice
    }
}
