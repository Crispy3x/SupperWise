import SwiftUI

struct GroceriesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.todayAccent) private var accent
    @State private var showHow = false
    @State private var showScanner = false
    @State private var showReceipt = false

    var body: some View {
        NavigationStack {
            if let plan = model.plan {
                let cost = model.cost(of: plan)
                let toBuy = cost.lines.filter { !$0.inKitchen }
                let have = cost.lines.filter(\.inKitchen)
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .bottom) {
                                Text(cost.total.dollars)
                                    .font(.serif(92))
                                    .displayTracking(92)
                                    .foregroundStyle(accent)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Spacer()
                                OnionGlyph(color: accent, ground: Paper.ground)
                                    .frame(width: 52, height: 52)
                                    .padding(.bottom, 12)
                            }
                            Text("of \(model.settings.budget.dollars) at \(storeLine). Priced by the pack you buy, not the spoonful you use.")
                                .font(.subheadline)
                                .foregroundStyle(Paper.ink2)
                            Button {
                                showHow = true
                            } label: {
                                Label("How we price this", systemImage: "info.circle")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(accent)
                            let left = toBuy.filter { !plan.bought.contains($0.id) }.count
                            Text(left == 0 ? "Everything's in the cart." : "\(left) of \(toBuy.count) items left to buy.")
                                .font(.footnote)
                                .foregroundStyle(Paper.ink2)
                            HStack(spacing: 10) {
                                GatedButton(feature: .scanner, action: { showScanner = true }) { Label("Scan a product", systemImage: "barcode.viewfinder") }
                                GatedButton(feature: .receipt, action: { showReceipt = true }) { Label("Check my receipt", systemImage: "doc.text.viewfinder") }
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(accent)
                            .padding(.top, 4)
                        }
                        .listRowBackground(Paper.ground)
                        .listRowSeparator(.hidden)
                    }

                    ForEach(Aisle.allCases, id: \.self) { aisle in
                        let lines = toBuy.filter { $0.ingredient.aisle == aisle }
                        if !lines.isEmpty {
                            Section {
                                ForEach(lines) { line in
                                    GroceryRow(line: line, bought: plan.bought.contains(line.id)) {
                                        model.toggleBought(line.id)
                                    }
                                    .listRowBackground(Paper.ground)
                                    .listRowSeparatorTint(Paper.rule)
                                    .swipeActions {
                                        Button("I have it") { model.setInKitchen(line.id, true) }
                                            .tint(Paper.ink2)
                                    }
                                }
                            } header: {
                                HStack(alignment: .lastTextBaseline) {
                                    Text(aisle.title)
                                        .font(.serif(28, relativeTo: .title2))
                                        .foregroundStyle(Paper.ink)
                                        .textCase(nil)
                                    Spacer()
                                    Text(lines.reduce(0) { $0 + $1.cost }.dollars)
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(Paper.ink2)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }

                    if !have.isEmpty {
                        Section {
                            ForEach(have) { line in
                                HStack {
                                    Text(line.ingredient.name)
                                    Spacer()
                                    Text("You have it").font(.footnote).foregroundStyle(Paper.ink2)
                                }
                                .listRowBackground(Paper.ground)
                                .swipeActions {
                                    Button("Buy it") { model.setInKitchen(line.id, false) }.tint(accent)
                                }
                            }
                        } header: {
                            Text("Already in your kitchen")
                                .font(.serif(28, relativeTo: .title2))
                                .foregroundStyle(Paper.ink)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Paper.ground)
                .navigationTitle("Groceries")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: shareText(cost: cost, plan: plan)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share list")
                    }
                }
                .sheet(isPresented: $showHow) { HowWePriceView() }
                .sheet(isPresented: $showScanner) { ScannerView() }
                .sheet(isPresented: $showReceipt) { ReceiptView() }
            }
        }
    }

    private var storeLine: String {
        let p = model.settings.price
        return p.storeName.isEmpty ? p.storeKind.label.lowercased() : p.storeName
    }

    /// Plain text that pastes into Notes, a message, or a store's search box.
    private func shareText(cost: WeekCost, plan: WeekPlan) -> String {
        var s = "Groceries, about \(cost.total.dollars)\n"
        for aisle in Aisle.allCases {
            let lines = cost.lines.filter { $0.ingredient.aisle == aisle && !$0.inKitchen }
            guard !lines.isEmpty else { continue }
            s += "\n\(aisle.title)\n"
            for l in lines { s += "\(plan.bought.contains(l.id) ? "✓" : "○") \(l.ingredient.name), \(l.packText)\n" }
        }
        return s
    }
}

struct GroceryRow: View {
    @Environment(\.todayAccent) private var accent
    let line: GroceryLine
    let bought: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().strokeBorder(bought ? Color.clear : Paper.ink2, lineWidth: 1.5)
                    if bought {
                        Circle().fill(accent)
                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Ink.onDay)
                    }
                }
                .frame(width: 24, height: 24)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(line.ingredient.name)
                        .strikethrough(bought)
                        .foregroundStyle(bought ? Paper.ink2 : Paper.ink)
                    Text("\(line.packText) · \((line.days.map(\.abbreviation) + (line.lunch ? ["lunches"] : [])).joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(Paper.ink2)
                    if let note = line.leftoverNote, !bought {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Paper.ink)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Paper.chip))
                    }
                }
                Spacer()
                Text(line.cost.dollars).monospacedDigit().foregroundStyle(bought ? Paper.ink2 : Paper.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(bought ? .isSelected : [])
    }
}

struct HowWePriceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Prices are estimates. Here's how they're made.")
                        .font(.serif(34))
                    Group {
                        Text("Each ingredient starts from a national reference price for one pack, the size you'd pick off the shelf.")
                        Text("It's adjusted for the kind of store you chose (\(model.settings.price.storeKind.label.lowercased())) and your region, from your ZIP or postal code.")
                        Text("You pay for whole packs. If a dinner needs a tablespoon of salsa, the list prices the jar, and tells you how long the rest keeps.")
                        Text("Shelf prices change often and differ by branch, so your total at the register will differ. Supperwise isn't affiliated with any grocery store.")
                        Text("Tick what you already have in Kitchen and it comes off the bill.")
                    }
                    .font(.body)
                    .foregroundStyle(Paper.ink2)
                }
                .padding(22)
            }
            .background(Paper.ground)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
