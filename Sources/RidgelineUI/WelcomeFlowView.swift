#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// The first-run welcome: an intro with optional sign-in, then a few short questions that set the app up for a business owner.
/// Only the business name is required. Every other step can be skipped and changed later in Settings.
struct WelcomeFlowView: View {
    @Environment(AppModel.self) private var model
    @State private var step = -1                       // -1 is the intro, 0 to 9 are the questions
    @State private var answers = OnboardingAnswers()
    @State private var problem: String?
    @State private var homeNote = ""
    @State private var findingLocation = false
    #if canImport(CoreLocation)
    @State private var locator = LocationFetcher()
    #endif

    private let steps = Onboarding.steps

    var body: some View {
        VStack(spacing: 0) {
            if step >= 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(step + 1), total: Double(steps.count))
                    Text("Step \(step + 1) of \(steps.count)").font(.footnote).foregroundStyle(.secondary)
                }
                .padding([.horizontal, .top])
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if step < 0 { intro } else { question(steps[step]) }
                    if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
                }
                .padding()
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            footer
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
        .background(Look.page.ignoresSafeArea())
    }

    // MARK: pieces

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            IconTile(icon: "snowflake", size: 72)
            Text("Let's set up your business").font(.largeTitle.bold())
            Text("A few quick questions and the app is ready: your services, prices and first clients. Only the first one is required. You can change everything later.")
                .font(.title3).foregroundStyle(.secondary)
            Card { SignInSection() }
        }
    }

    private func question(_ s: OnboardingStep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(s.title).font(.footnote.bold()).foregroundStyle(.tint).textCase(.uppercase)
            Text(s.question).font(.title2.bold())
            Text(s.why).font(.footnote).foregroundStyle(.secondary)
            controls(for: s.id).padding(.top, 4)
        }
    }

    @ViewBuilder
    private func controls(for id: OnboardingStepID) -> some View {
        switch id {
        case .business:
            TextField("Business name", text: $answers.businessName)
                .textFieldStyle(.roundedBorder).font(.title3)
        case .services:
            ForEach(ServiceKind.allCases, id: \.self) { kind in
                Toggle(kind.title, isOn: membership(kind, in: \.services))
            }
        case .clients:
            ForEach(ClientType.allCases, id: \.self) { kind in
                Toggle(kind.title, isOn: membership(kind, in: \.clientTypes))
            }
        case .snowBilling:
            Picker("How you bill", selection: $answers.snowBilling) {
                ForEach([SnowBillingChoice.perPush, .seasonal], id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Depth-based and mixed contracts are set up from a quote.").font(.footnote).foregroundStyle(.secondary)
            Stepper("Start plowing at \(answers.triggerInches, specifier: "%.1f") inches", value: $answers.triggerInches, in: 0.5...12, step: 0.5)
        case .homeBase:
            #if canImport(CoreLocation)
            Button(findingLocation ? "Finding..." : "Use my current location") {
                findingLocation = true
                Task {
                    if let here = await locator.currentLocation() {
                        answers.homeBase = here
                        homeNote = ""
                    } else {
                        homeNote = "Could not get your location. You can set it later in Settings."
                    }
                    findingLocation = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(findingLocation)
            #endif
            if answers.homeBase != nil { Label("Location saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            if !homeNote.isEmpty { Text(homeNote).font(.footnote).foregroundStyle(.secondary) }
        case .team:
            Stepper("\(answers.crewCount) crew\(answers.crewCount == 1 ? "" : "s") or truck\(answers.crewCount == 1 ? "" : "s")", value: $answers.crewCount, in: 1...50)
            Text("Pricing is per crew. Office staff are always free.").font(.footnote).foregroundStyle(.secondary)
        case .plan:
            PlanChoiceCards(selection: $answers.plan, crews: answers.crewCount)
        case .importClients:
            Label("Add clients one at a time, or import a spreadsheet saved as CSV, from the Clients tab.", systemImage: "person.badge.plus")
            Text("Nobody is imported as having agreed to messages.").font(.footnote).foregroundStyle(.secondary)
        case .payment:
            Stepper("Clients have \(answers.netDays) days to pay", value: $answers.netDays, in: 0...60)
            TextField("How should clients pay you? This goes on invoices.", text: $answers.paymentInstructions, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            PayLinkField(link: $answers.payLink)
        case .messages:
            Toggle("Show the message-clients option on the Storm screen", isOn: $answers.stormMessagesOn)
            Text("Nothing is sent by itself. You review every message before it goes.").font(.footnote).foregroundStyle(.secondary)
            Text("When a stop is done, an invoice should be:").font(.subheadline)
            Picker("When a stop is done", selection: $answers.invoiceAutomation) {
                ForEach(InvoiceAutomation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(answers.invoiceAutomation.explanation).font(.footnote).foregroundStyle(.secondary)
            Text("Messages need a server and clients who agreed to them. You set those up in Settings.").font(.footnote).foregroundStyle(.secondary)
        case .branding:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 14) {
                ForEach(AppData.accentColors, id: \.self) { name in
                    Button { answers.accentColor = name } label: {
                        Circle().fill(Theme.accent(name)).frame(width: 44, height: 44)
                            .overlay { if answers.accentColor == name { Image(systemName: "checkmark").foregroundStyle(.white).font(.headline) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name.capitalized)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if step >= 0 {
                Button("Back") { step -= 1; problem = nil }.buttonStyle(.bordered)
            }
            Spacer()
            if step >= 0 && !steps[step].required {
                Button("Skip") { skip() }.buttonStyle(.borderless)
            }
            Button(step < 0 ? "Get started" : (step == steps.count - 1 ? "Finish" : "Next")) { next() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    // MARK: actions

    private func membership<T: Hashable>(_ item: T, in keyPath: WritableKeyPath<OnboardingAnswers, Set<T>>) -> Binding<Bool> {
        Binding(
            get: { answers[keyPath: keyPath].contains(item) },
            set: { on in
                if on { _ = answers[keyPath: keyPath].insert(item) } else { _ = answers[keyPath: keyPath].remove(item) }
            })
    }

    private func next() {
        problem = nil
        if step < 0 { step = 0; return }
        if steps[step].id == .business && !answers.problems.isEmpty {
            problem = "Enter your business name to continue."
            return
        }
        if step == steps.count - 1 { finish() } else { step += 1 }
    }

    private func skip() {
        answers.skippedSteps.append(steps[step].id)
        if step == steps.count - 1 { finish() } else { step += 1 }
    }

    private func finish() {
        problem = model.edit { try $0.finishOnboarding(answers, now: Date()) }
    }
}

/// Pro and Max side by side. The choice sets how many employees the owner can add. Everything is free for 14 days.
struct PlanChoiceCards: View {
    @Binding var selection: PlanTier
    let crews: Int

    var body: some View {
        VStack(spacing: 12) {
            card(.pro, name: "Pro", blurb: "Everything to run a crew: clients, jobs, quotes, invoices, time clock and proof of service.",
                 points: ["Up to \(TeamRules.employeeLimit(for: .pro)) employees", "Smart route planning", "Client pages and storm messages"])
            card(.max, name: "Max", blurb: "For bigger operations that want more control.",
                 points: ["Up to \(TeamRules.employeeLimit(for: .max)) employees", "Roles with custom permissions", "Storm automation and subcontractor tools"])
            Text("Free for \(Pricing.trialDays) days with everything unlocked. You pay for the plan. Your employees never pay.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func card(_ tier: PlanTier, name: String, blurb: String, points: [String]) -> some View {
        let chosen = selection == tier
        return Button { selection = tier } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(name).font(.title3.bold())
                    Spacer()
                    Text("\(Pricing.monthly(tier, crews: crews).formatted) per month").font(.callout.bold())
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle").foregroundStyle(chosen ? Color.accentColor : Color.secondary)
                }
                Text(blurb).font(.footnote).foregroundStyle(.secondary)
                ForEach(points, id: \.self) { Label($0, systemImage: "checkmark").font(.footnote) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(chosen ? Color.accentColor : Look.stroke, lineWidth: chosen ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}
#endif
