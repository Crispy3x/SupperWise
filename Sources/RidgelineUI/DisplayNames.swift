#if canImport(SwiftUI)
import RidgelineCore

// Plain-language names for the choices the owner sees.

extension ServiceKind {
    var title: String {
        switch self {
        case .snowPlowing: return "Snow plowing"
        case .salting: return "Salting and de-icing"
        case .shoveling: return "Shoveling and sidewalks"
        case .mowing: return "Lawn mowing"
        case .landscaping: return "Landscaping"
        case .other: return "Something else"
        }
    }
}

extension ClientType {
    var title: String {
        switch self {
        case .residential: return "Homes"
        case .commercial: return "Businesses"
        case .hoaOrPropertyManager: return "HOAs and property managers"
        }
    }
}

extension SnowBillingChoice {
    var title: String {
        switch self {
        case .perPush: return "Per push"
        case .seasonal: return "Season"
        case .perInch: return "By depth"
        case .hybrid: return "Mixed"
        }
    }
}

extension InvoiceAutomation {
    var title: String {
        switch self {
        case .off: return "Nothing"
        case .draft: return "Draft"
        case .send: return "Send"
        }
    }

    var explanation: String {
        switch self {
        case .off: return "Nothing happens when a stop is done. You create invoices yourself."
        case .draft: return "A draft invoice is made for you to look at and send. Nothing goes out without you."
        case .send: return "The invoice is emailed to clients who agreed to messages. Everyone else gets a draft."
        }
    }
}

extension RequestKind {
    var title: String {
        switch self {
        case .service: return "Asked for service"
        case .urgent: return "Urgent request"
        case .skip: return "Asked to skip this storm"
        case .thanks: return "Kind message for the driver"
        }
    }
}

extension UrgentReason {
    var title: String {
        switch self {
        case .leavingSoon: return "Needs to leave soon"
        case .medical: return "Medical or care visit"
        case .visitorOrDelivery: return "Visitor or delivery coming"
        case .other: return "Other reason"
        }
    }
}
#endif
