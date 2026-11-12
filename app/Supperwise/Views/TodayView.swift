import SwiftUI

/// The title card: tonight's dinner on its weekday's colour.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var subs
    @Environment(\.colorScheme) private var scheme
    @State private var showRecipe: Recipe? = nil
    @State private var showPlan = false
    @State private var showSettings = false
    @State private var showRecap = false
    @State private var showEatOut = false
    @State private var holiday: HolidayMenu? = nil
    /// The holiday menu in season (30 days before until the day after), if any.
    private var seasonal: HolidayMenu? { HolidayMenu.bundled.first { $0.inSeason() } }
    @State private var spin = 0.0
    @State private var spinning = false

    var body: some View {
        NavigationStack {
            if let plan = model.plan, let tonight = model.tonight(), let recipe = model.catalog.recipe(tonight.recipeID) {
                let palette = DayPalette.of(tonight.day)
                let cost = model.cost(of: plan)
                let index = (plan.dinners.firstIndex { $0.day == tonight.day } ?? 0) + 1
                let plate = cost.perDinner[tonight.day] ?? 0
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Episode \(index) of \(plan.dinners.count)")
                            Spacer()
                            Text(budgetLine(cost.total))
                                .contentTransition(.numericText())
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        .foregroundStyle(Ink.onDay2)

                        Text(tonight.day.name)
                            .font(.serif(92))
                            .displayTracking(92)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Ink.onDay)
                            .accessibilityAddTraits(.isHeader)

                        stage(recipe: recipe, palette: palette)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tonight · \(recipe.minutes) minutes")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Ink.onDay2)
                            Text(recipe.name)
                                .font(.serif(46, relativeTo: .title))
                                .displayTracking(46)
                                .foregroundStyle(Ink.onDay)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(recipe.id)
                                .transition(.asymmetric(insertion: .offset(y: 8).combined(with: .opacity), removal: .opacity))
                            (Text(plate.dollars).bold().foregroundStyle(Ink.onDay)
                             + Text(" feeds all \(model.settings.householdSize), \((plate / Double(model.settings.householdSize)).dollars) a plate. \(recipe.side)"))
                                .font(.subheadline)
                                .foregroundStyle(Ink.onDay2)
                                .contentTransition(.numericText())
                                .monospacedDigit()
                        }

                        HStack(spacing: 10) {
                            Button("Start cooking") { showRecipe = recipe }
                                .buttonStyle(PillButtonStyle(fill: Ink.onDay, ink: palette.ground))
                            Button {
                                swapTonight(tonight.day)
                            } label: {
                                Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(PillButtonStyle(fill: .clear, ink: Ink.onDay, outlined: true))
                            .disabled(spinning)
                            .sensoryFeedback(.impact(weight: .light), trigger: spin)
                        }
                        .padding(.top, 14)

                        GatedButton(feature: .leftovers, action: { model.toggleLeftovers(tonight.day) }) {
                            let on = plan.leftovers?.contains(tonight.day) == true
                            Text(on ? "✓ Making 2 extra portions for lunch" : "+ Make extra for lunch tomorrow")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(on ? palette.ground : Ink.onDay)
                                .background(Capsule().fill(on ? Ink.onDay : Color.black.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)

                        if let baby = model.baby, subs.has(.firstFoods) {
                            BabyTonightCard(recipe: recipe, baby: baby)
                                .padding(.top, 14)
                        }

                        DayStrip(plan: plan, current: tonight.day)
                            .padding(.top, 22)

                        if let next = plan.dinners.first(where: { $0.day > tonight.day && !$0.cooked }),
                           let nr = model.catalog.recipe(next.recipeID) {
                            HStack(spacing: 10) {
                                Text("Next episode")
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.22)))
                                Text("\(next.day.abbreviation) · \(nr.name), \(nr.minutes) min")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Ink.onDay)
                            .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)

                    HStack(spacing: 20) {
                        GatedButton(feature: .recap, action: { showRecap = true }) { Text("Your week") }
                        GatedButton(feature: .eatOut, action: { showEatOut = true }) { Text("Eating out") }
                        if let seasonal {
                            GatedButton(feature: .holidayMenus, action: { holiday = seasonal }) { Text(seasonal.name) }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.onDay)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .background(palette.ground(scheme).ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Next week") { showPlan = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
                            .accessibilityLabel("Settings")
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .tint(Ink.onDay)
                .navigationDestination(item: $showRecipe) { RecipeView(recipe: $0, day: tonight.day) }
                .sheet(isPresented: $showPlan) { PlanView() }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .sheet(isPresented: $showRecap) { RecapView() }
                .sheet(isPresented: $showEatOut) { EatOutView() }
                .sheet(item: $holiday) { HolidayMenuView(menu: $0) }
            } else if let plan = model.plan {
                WeekDoneView(plan: plan, showPlan: $showPlan)
                    .sheet(isPresented: $showPlan) { PlanView() }
            }
        }
    }

    private func budgetLine(_ total: Double) -> String {
        let diff = model.settings.budget - total
        return diff >= 0 ? "\(diff.dollars) under budget" : "\((-diff).dollars) over budget"
    }

    @ViewBuilder
    private func stage(recipe: Recipe, palette: DayPalette) -> some View {
        ZStack {
            CutPaperSet(deep: palette.deep(scheme), ground: palette.ground(scheme))
                .rotationEffect(.degrees(spin * 0.4))
            PlateView(recipe: recipe, tint: palette.deep(scheme))
                .frame(width: 236, height: 236)
                .rotationEffect(.degrees(spin))
                .id(recipe.id)
                .transition(.asymmetric(
                    insertion: .offset(x: 160).combined(with: .opacity),
                    removal: .offset(x: -160).combined(with: .opacity)))
                .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                    if abs(v.translation.width) > 60 { swapTonight(model.tonight()?.day ?? .mon) }
                })
        }
        .frame(height: 252)
        .padding(.top, 4)
    }

    /// The signature: the plate turns like a lazy Susan, the dish leaves and the new one arrives,
    /// and the price rolls. Reduced motion gets a cross-fade with the same rolling price.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func swapTonight(_ day: Weekday) {
        spinning = true
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { model.swap(day) }
            spinning = false
            return
        }
        withAnimation(.snappy(duration: 0.12)) { spin += 40 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.smooth(duration: 0.3)) {
                spin += 120
                model.swap(day)
            }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(duration: 0.1, bounce: 0)) { spin = 0 }
            spinning = false
        }
    }
}

/// The five nights as small plates. Cooked nights are dimmed with a tick.
struct DayStrip: View {
    @Environment(AppModel.self) private var model
    let plan: WeekPlan
    let current: Weekday

    var body: some View {
        HStack {
            ForEach(plan.dinners) { d in
                if let r = model.catalog.recipe(d.recipeID) {
                    VStack(spacing: 6) {
                        ZStack {
                            PlateView(recipe: r, rim: 0)
                                .saturation(d.cooked ? 0.4 : 1)
                                .brightness(d.cooked ? -0.35 : 0)
                            if d.cooked {
                                Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(Ink.onDay)
                            }
                        }
                        .frame(width: 50, height: 50)
                        .overlay(Circle().strokeBorder(d.day == current ? Ink.onDay : Ink.onDay.opacity(0.35), lineWidth: d.day == current ? 3 : 4))
                        Text(d.day.short)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(d.day == current ? Ink.onDay : Ink.onDay2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(d.day.name): \(r.name)\(d.cooked ? ", cooked" : "")")
                }
            }
        }
    }
}

/// Every dinner this week is cooked.
struct WeekDoneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.todayAccent) private var accent
    let plan: WeekPlan
    @Binding var showPlan: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("That's the season.")
                .font(.serif(46))
                .foregroundStyle(Paper.ink)
            Text("All \(plan.dinners.count) dinners this week are cooked. Plan next week and it will be ready on Monday.")
                .font(.body)
                .foregroundStyle(Paper.ink2)
            Button("Plan next week") { showPlan = true }
                .buttonStyle(PillButtonStyle(fill: accent, ink: Ink.onDay))
            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paper.ground.ignoresSafeArea())
    }
}
