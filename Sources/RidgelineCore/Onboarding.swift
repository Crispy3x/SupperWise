import Foundation

public enum ServiceKind: String, Codable, CaseIterable, Sendable {
    case snowPlowing, salting, shoveling, mowing, landscaping, other
}

public enum ClientType: String, Codable, CaseIterable, Sendable {
    case residential, commercial, hoaOrPropertyManager
}

public enum SnowBillingChoice: String, Codable, CaseIterable, Sendable {
    case perPush, seasonal, perInch, hybrid
}

/// What an invoice does when a stop is completed.
public enum InvoiceAutomation: String, Codable, CaseIterable, Sendable {
    /// Nothing happens automatically.
    case off
    /// A draft invoice is created for you to look at and send.
    case draft
    /// The invoice is created and emailed to clients who agreed to messages. Others stay as drafts.
    case send
}

/// The owner's answers from the welcome questions, kept as the app's defaults.
public struct BusinessProfile: Equatable, Codable, Sendable {
    public var services: Set<ServiceKind> = [.snowPlowing]
    public var clientTypes: Set<ClientType> = [.residential]
    public var defaultSnowBilling: SnowBillingChoice = .perPush
    public var defaultTriggerInches: Double = 2
    public var crewCount: Int = 1
    /// Days a client has to pay.
    public var netDays: Int = 14
    /// Shown on invoice emails, for example "Check or e-transfer to Ridge Plow".
    public var paymentInstructions: String = ""
    /// A payment link from the owner's own account (optional). Stored only if it passes `PayLink.clean`.
    public var payLink: String?
    /// The plan the owner picked at sign-up. It sets how many employees they can add. Nil until they choose.
    public var chosenPlan: PlanTier?
    /// "dark", "light" or "system". Nil means dark, the app's default look.
    public var appearance: String?
    public var stormMessagesOn: Bool = true
    public var invoiceAutomation: InvoiceAutomation = .draft
    public var accentColor: String = "blue"
    /// Whether the client page shows invoice amounts (otherwise only paid or due).
    public var portalShowsAmounts: Bool = true
    public var onboardingCompletedAt: Date?
    public var skippedSteps: [String] = []

    public init() {}
}

public enum OnboardingStepID: String, CaseIterable, Codable, Sendable {
    case business, services, clients, snowBilling, homeBase, team, plan, importClients, payment, messages, branding
}

public struct OnboardingStep: Equatable, Sendable {
    public let id: OnboardingStepID
    public let title: String
    public let question: String
    /// Why we ask, shown under the question so it never feels like paperwork.
    public let why: String
    public let required: Bool
}

public enum Onboarding {
    /// The eleven welcome steps, in order. Only the business name is required; everything else has a sensible default
    /// and can be skipped or changed later in Settings.
    public static let steps: [OnboardingStep] = [
        OnboardingStep(id: .business, title: "Your business", question: "What is your business called?",
                       why: "Clients see this on messages and invoices.", required: true),
        OnboardingStep(id: .services, title: "Your services", question: "What do you do?",
                       why: "We keep this on your profile and will use it to tailor the app.", required: false),
        OnboardingStep(id: .clients, title: "Your clients", question: "Who do you work for?",
                       why: "We keep this on your profile and will use it to tailor the app.", required: false),
        OnboardingStep(id: .snowBilling, title: "Snow pricing", question: "How do you usually bill snow, and at what depth do you start?",
                       why: "New clients start with this depth and billing style (per push or per season). You can change any client later.", required: false),
        OnboardingStep(id: .homeBase, title: "Home base", question: "Where do your trucks start?",
                       why: "Routes start here, and the weather forecast is for this spot.", required: false),
        OnboardingStep(id: .team, title: "Your crews", question: "How many crews or trucks do you run?",
                       why: "We set up your crews. Price is per crew.", required: false),
        OnboardingStep(id: .plan, title: "Your plan", question: "Which plan fits your business?",
                       why: "Free for 14 days with everything unlocked. You pay for the plan. Your employees never pay.", required: false),
        OnboardingStep(id: .importClients, title: "Your clients list", question: "Do you have clients to bring in?",
                       why: "Skip this and add them as you go.", required: false),
        OnboardingStep(id: .payment, title: "Getting paid", question: "How long do clients have to pay, and how should they pay you?",
                       why: "This goes on every invoice.", required: false),
        OnboardingStep(id: .messages, title: "Messages", question: "Should we send clients a message at the start of each storm, and what should happen to invoices when a stop is done?",
                       why: "Fewer 'did you come?' texts. You choose what is automatic.", required: false),
        OnboardingStep(id: .branding, title: "Your look", question: "Pick a color for your client pages.",
                       why: "Last step. Then you are ready to go.", required: false),
    ]
}

public struct OnboardingAnswers: Equatable, Sendable {
    public var businessName = ""
    public var services: Set<ServiceKind> = [.snowPlowing]
    public var clientTypes: Set<ClientType> = [.residential]
    public var snowBilling: SnowBillingChoice = .perPush
    public var triggerInches: Double = 2
    public var homeBase: Coordinate?
    public var crewCount = 1
    public var plan: PlanTier = .pro
    public var netDays = 14
    public var paymentInstructions = ""
    public var payLink = ""
    public var stormMessagesOn = true
    public var invoiceAutomation: InvoiceAutomation = .draft
    public var accentColor = "blue"
    public var skippedSteps: [OnboardingStepID] = []

    public init() {}

    /// Problems that stop the owner from finishing. Only the business name is required.
    public var problems: [String] {
        businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ["Enter your business name."] : []
    }
}

extension AppData {
    public static let accentColors = ["blue", "green", "orange", "red", "purple", "teal", "gray"]

    /// Applies the welcome answers. Safe to run again: it updates the profile and only adds crews that are missing.
    public mutating func finishOnboarding(_ a: OnboardingAnswers, now: Date) throws {
        guard a.problems.isEmpty else { throw OperationError.emptyName }
        companyName = a.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        var p = profile
        p.services = a.services.isEmpty ? [.snowPlowing] : a.services
        p.clientTypes = a.clientTypes.isEmpty ? [.residential] : a.clientTypes
        p.defaultSnowBilling = a.snowBilling
        p.defaultTriggerInches = min(max(a.triggerInches, 0.5), 24)
        p.crewCount = min(max(a.crewCount, 1), 50)
        p.chosenPlan = a.plan
        p.netDays = min(max(a.netDays, 0), 120)
        p.paymentInstructions = String(a.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        p.payLink = PayLink.clean(a.payLink)
        p.stormMessagesOn = a.stormMessagesOn
        p.invoiceAutomation = a.invoiceAutomation
        p.accentColor = Self.accentColors.contains(a.accentColor) ? a.accentColor : "blue"
        p.skippedSteps = a.skippedSteps.map(\.rawValue)
        p.onboardingCompletedAt = now
        profile = p
        if let home = a.homeBase { depot = home }
        while crews.count < p.crewCount { crews.append(Crew(name: "Crew \(crews.count + 1)")) }
    }
}
