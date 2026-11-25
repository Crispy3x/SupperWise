#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// The top of Home: a greeting and the four numbers an owner checks first thing. Employees see their own day, without money.
struct HomeSummaryCard: View {
    @Environment(AppModel.self) private var model
    let openScreen: (ShellScreen) -> Void
    let openRoute: () -> Void

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        guard let first = model.data.currentMember?.name.split(separator: " ").first else { return part }
        return "\(part), \(first)"
    }

    private var jobsToday: [Job] { model.data.jobs(on: Date()).filter { !$0.isTask && $0.status != .cancelled } }

    private var nextJob: Job? { jobsToday.filter { $0.status.isOpen }.min { $0.start < $1.start } }

    private var owed: (total: Money, overdue: Int) {
        let now = Date()
        var total = Money.zero, overdue = 0
        for inv in model.data.invoices {
            let status = inv.status(now: now)
            guard status == .sent || status == .partiallyPaid || status == .overdue else { continue }
            total = total + inv.balance
            if status == .overdue { overdue += 1 }
        }
        return (total, overdue)
    }

    private var weatherLine: String? {
        guard let f = model.forecast else { return nil }
        var parts: [String] = []
        if f.snowfallInches >= 0.1 { parts.append(String(format: "%.1f in of snow expected", f.snowfallInches)) } else { parts.append("No snow expected") }
        if let low = f.minTemperatureF { parts.append("low \(Int(low.rounded()))°F") }
        if let wind = f.maxWindMph, wind >= 15 { parts.append("wind \(Int(wind.rounded())) mph") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let jobs = jobsToday
        let done = jobs.filter { $0.status == .done }.count
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.largeTitle.bold()).lineLimit(1).minimumScaleFactor(0.6)
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.title3).foregroundStyle(.secondary)
            }
            if let weatherLine {
                Label(weatherLine, systemImage: "cloud.snow.fill").font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                StatTile(title: "Jobs today", value: jobs.isEmpty ? "0" : "\(done)/\(jobs.count)",
                         detail: jobs.isEmpty ? "Nothing scheduled" : (done == jobs.count ? "All done" : "\(jobs.count - done) to go"),
                         icon: "briefcase.fill", tint: .blue, action: openRoute)
                if let next = nextJob {
                    StatTile(title: "Next stop", value: next.start.formatted(date: .omitted, time: .shortened),
                             detail: [model.data.customerName(forJob: next), next.title].first { !$0.isEmpty } ?? "",
                             icon: "location.fill", tint: .teal, action: openRoute)
                } else {
                    StatTile(title: "Next stop", value: "None", detail: jobs.isEmpty ? "Add a job" : "Route finished",
                             icon: "location.fill", tint: .teal, action: openRoute)
                }
            }
            if model.data.can(.viewRevenue) {
                let money = owed
                HStack(spacing: 12) {
                    StatTile(title: "Owed to you", value: money.total.formatted,
                             detail: money.total.cents == 0 ? "All paid up" : "Unpaid invoices",
                             icon: "dollarsign.circle.fill", tint: .green) { openScreen(.revenue) }
                    StatTile(title: "Overdue", value: "\(money.overdue)",
                             detail: money.overdue == 0 ? "Nothing late" : (money.overdue == 1 ? "invoice is late" : "invoices are late"),
                             icon: "exclamationmark.circle.fill", tint: money.overdue == 0 ? .gray : .orange) { openScreen(.revenue) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small tappable card with one number.
struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                    Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Look.card, in: RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous).stroke(Look.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}
#endif
