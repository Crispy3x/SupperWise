import Foundation

public enum PayRule: Equatable, Codable, Sendable {
    /// Percent of the job price (for example 60).
    case percentOfJob(Int)
    case hourly(Money)
    case perPush(Money)
    case perLot(Money)
}

public struct SubJob: Equatable, Sendable {
    public var jobAmount: Money
    public var hours: Double
    public var pushes: Int
    public var hasBeforePhoto: Bool
    public var hasAfterPhoto: Bool

    public init(jobAmount: Money, hours: Double = 0, pushes: Int = 1, hasBeforePhoto: Bool = false, hasAfterPhoto: Bool = false) {
        self.jobAmount = jobAmount
        self.hours = hours
        self.pushes = pushes
        self.hasBeforePhoto = hasBeforePhoto
        self.hasAfterPhoto = hasAfterPhoto
    }
}

public struct PayResult: Equatable, Sendable {
    public var amount: Money
    /// Non-nil when pay is withheld, with the reason shown to the sub.
    public var heldReason: String?
}

public enum SubPay {
    public static func pay(rule: PayRule, job: SubJob, requirePhotos: Bool) -> PayResult {
        if requirePhotos && !(job.hasBeforePhoto && job.hasAfterPhoto) {
            return PayResult(amount: .zero, heldReason: "Pay is held until before and after photos are uploaded.")
        }
        let amount: Money
        switch rule {
        case .percentOfJob(let pct): amount = job.jobAmount.percent(pct)
        case .hourly(let rate): amount = Money(cents: Int((Double(rate.cents) * job.hours).rounded()))
        case .perPush(let rate): amount = rate * job.pushes
        case .perLot(let rate): amount = rate
        }
        return PayResult(amount: amount, heldReason: nil)
    }
}
