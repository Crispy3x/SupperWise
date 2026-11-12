import AppIntents
import Foundation

/// "Hey Siri, what's for dinner in Supperwise?" Reads tonight's plan from the saved file; no network.
struct WhatsForDinnerIntent: AppIntent {
    static let title: LocalizedStringResource = "What's for dinner?"
    static let description = IntentDescription("Tells you tonight's dinner from your Supperwise plan.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Self.answer()))
    }

    static func answer(now: Date = .now) -> String {
        guard let data = try? Data(contentsOf: AppModel.defaultURL()),
              let state = try? JSONDecoder().decode(SavedState.self, from: data),
              let plan = state.plan else {
            return "You don't have a plan yet. Open Supperwise to build your week."
        }
        let catalog = Catalog.load()
        let recipes = catalog.recipes + (state.savedRecipes ?? [])
        let today = Weekday(calendarWeekday: Calendar.current.component(.weekday, from: now))
        guard let tonight = plan.dinners.first(where: { $0.day == today }) else {
            if let next = plan.dinners.first(where: { $0.day > today && !$0.cooked }), let r = recipes.first(where: { $0.id == next.recipeID }) {
                return "No dinner planned tonight. \(next.day.name) is \(r.name)."
            }
            return "No dinner planned tonight."
        }
        guard let r = recipes.first(where: { $0.id == tonight.recipeID }) else { return "Open Supperwise to see tonight's dinner." }
        return tonight.cooked ? "You've already cooked tonight: \(r.name)." : "Tonight it's \(r.name). It takes about \(r.minutes) minutes."
    }
}

struct SupperwiseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsForDinnerIntent(),
                    phrases: ["What's for dinner in \(.applicationName)", "What's for dinner tonight in \(.applicationName)", "\(.applicationName) tonight"],
                    shortTitle: "What's for dinner?",
                    systemImageName: "fork.knife")
    }
}
