#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

extension AppModel {
    /// Makes a draft invoice from the Quick invoice screen. Returns the new invoice number, or a sentence saying what is missing.
    func createQuickInvoice(customerID: UUID, siteID: UUID?, newAddress: String, picks: [QuickInvoicePick], note: String) -> (number: String?, problem: String?) {
        var copy = data
        do {
            let invoice = try copy.createQuickInvoice(customerID: customerID, siteID: siteID, newAddress: newAddress, picks: picks, note: note, now: Date())
            data = copy
            save()
            return (invoice.number, nil)
        } catch let error as QuickInvoiceError {
            return (nil, error.message)
        } catch {
            return (nil, "Could not create the invoice.")
        }
    }

    /// Changes one service on the price list and saves.
    func updateService(id: UUID, _ change: (inout ServicePrice) -> Void) {
        var list = data.priceList
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        data.setPriceList(list)
        save()
    }
}
#endif
