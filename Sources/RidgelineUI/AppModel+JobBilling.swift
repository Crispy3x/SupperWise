#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Job prices, and turning finished jobs into invoices (see JobBilling.swift).
extension AppModel {
    /// Adds a job with how often it repeats and what one visit costs. Returns a message to show, or nil on success.
    func addJob(title: String, kind: JobKind, customerID: UUID?, siteID: UUID?, start: Date, durationMinutes: Int,
                assigneeIDs: [UUID], notes: String, isTask: Bool, repeatRule: RepeatRule?, priceLines: [JobPriceLine]) -> String? {
        edit { d in
            let job = try d.addJob(title: title, kind: kind, customerID: customerID, siteID: siteID, start: start,
                                   durationMinutes: durationMinutes, assigneeIDs: assigneeIDs, notes: notes, isTask: isTask, now: Date())
            try d.setJobRepeat(repeatRule, id: job.id)
            if !isTask { try d.setJobPrice(priceLines, id: job.id) }
        }
    }

    /// Sets or clears what one visit of a job costs. Returns a message to show, or nil on success.
    func setJobPrice(_ lines: [JobPriceLine], id: UUID) -> String? {
        edit { try $0.setJobPrice(lines, id: id) }
    }

    /// Makes a draft invoice for one finished visit. Returns the new invoice number, or a sentence saying what is missing.
    func createInvoice(forJobVisit jobID: UUID, on day: Date) -> (number: String?, problem: String?) {
        var copy = data
        do {
            let invoice = try copy.createInvoice(forJobVisit: jobID, on: day, now: Date())
            data = copy
            save()
            return (invoice.number, nil)
        } catch let error as JobBillingError {
            return (nil, error.message)
        } catch {
            return (nil, "Could not create the invoice.")
        }
    }

    /// Makes one draft invoice per client for finished jobs that are not invoiced yet. Pass a client to bill only them.
    func billFinishedWork(forClient customerID: UUID? = nil) -> JobBillingResult {
        var copy = data
        let result = copy.createInvoices(forClient: customerID, now: Date())
        if !result.invoices.isEmpty {
            data = copy
            save()
        }
        return result
    }
}
#endif
