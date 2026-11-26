import Foundation

public enum BackupError: Error, Equatable {
    case unreadable
    case newerVersion(found: Int, supported: Int)
}

public struct RestoreResult: Equatable, Sendable {
    public let data: AppData
    /// False when the proof-of-service log in the file fails its tamper check.
    public let visitLogVerified: Bool
    public var customerCount: Int { data.customers.count }
    public var siteCount: Int { data.sites.count }
    public var invoiceCount: Int { data.invoices.count }
    public var visitCount: Int { data.visitLog.entries.count }
}

/// Getting your data out (a full backup and spreadsheets) and back in. Photo files are not part of the backup:
/// the backup keeps each photo's name and fingerprint, but the pictures themselves stay on the device.
public enum DataExport {
    public static let supportedSchemaVersion = SchemaMigrations.currentVersion

    /// Everything, as one JSON file that can be restored.
    public static func backupJSON(_ data: AppData) throws -> Data {
        try FileStore.encoder.encode(data)
    }

    /// Reads a backup. Refuses files that are not a backup or come from a newer version of the app, and upgrades older ones.
    /// The saved sign-in is always dropped: a backup never signs anyone in. Before using the data on a device, pass it
    /// through `preparedForDevice(_:current:)` so logins from someone else's backup are not imported.
    public static func restore(from file: Data) throws -> RestoreResult {
        // Every field has a default, so any JSON object at all would read as an empty backup and offer to replace
        // everything with nothing. A real backup names its version, or at least the business or its clients.
        guard let object = (try? JSONSerialization.jsonObject(with: file)) as? [String: Any],
              object["schemaVersion"] != nil || object["customers"] != nil || object["companyName"] != nil else { throw BackupError.unreadable }
        guard var data = try? FileStore.decoder.decode(AppData.self, from: file) else { throw BackupError.unreadable }
        guard data.schemaVersion <= supportedSchemaVersion else {
            throw BackupError.newerVersion(found: data.schemaVersion, supported: supportedSchemaVersion)
        }
        if data.schemaVersion < supportedSchemaVersion {
            guard let upgraded = try? SchemaMigrations.migrate(file),
                  let migrated = try? FileStore.decoder.decode(AppData.self, from: upgraded) else { throw BackupError.unreadable }
            data = migrated
        }
        data.session = nil
        return RestoreResult(data: data, visitLogVerified: data.visitLog.verify())
    }

    public struct NamedFile: Equatable, Sendable {
        public let name: String
        public let content: String
    }

    /// One spreadsheet-friendly CSV per kind of record. Times are UTC.
    public static func csvFiles(_ d: AppData, now: Date) -> [NamedFile] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        func day(_ date: Date) -> String { f.string(from: date) }
        func money(_ m: Money) -> String {
            let c = abs(m.cents)
            return "\(m.cents < 0 ? "-" : "")\(c / 100).\(String(format: "%02d", c % 100))"
        }
        func text(_ s: String) -> String { InvoiceCSV.cell(s) }
        func num(_ s: String) -> String { InvoiceCSV.cell(s, guardFormula: false) }
        func file(_ name: String, _ header: [String], _ rows: [[String]]) -> NamedFile {
            NamedFile(name: name, content: ([header.map(text).joined(separator: ",")] + rows.map { $0.joined(separator: ",") }).joined(separator: "\r\n") + "\r\n")
        }
        let customer: (UUID) -> String = { id in d.customers.first { $0.id == id }?.name ?? "" }
        let siteAddress: (UUID?) -> String = { id in d.sites.first { $0.id == id }?.address ?? "" }
        let siteOf: (UUID) -> Site? = { id in d.sites.first { $0.id == id } }

        return [
            file("customers.csv", ["Name", "Phone", "Email", "Notes"],
                 d.customers.map { [text($0.name), text($0.phone), text($0.email), text($0.notes)] }),
            file("sites.csv", ["Customer", "Address", "Latitude", "Longitude", "Priority", "Trigger inches", "Instructions"],
                 d.sites.map { [text(customer($0.customerID)), text($0.address), num($0.latitude.map { String($0) } ?? ""),
                                num($0.longitude.map { String($0) } ?? ""), num(String($0.priority)), num(String($0.triggerInches)), text($0.instructions)] }),
            file("contracts.csv", ["Customer", "Address", "Season", "Terms"],
                 d.contracts.map { c in
                     let s = siteOf(c.siteID)
                     return [text(s.map { customer($0.customerID) } ?? ""), text(s?.address ?? ""), text(c.season), text(c.terms.summary)]
                 }),
            file("visits.csv", ["Address", "Storm", "Arrival (UTC)", "Departure (UTC)", "Status", "Reason", "Snow depth in", "Salt lb",
                                "Crew member", "Location check", "Photos", "Note"],
                 d.visitLog.entries.map { e in
                     let r = e.record
                     var status = "completed", reason = ""
                     if case .skipped(let why) = r.status { status = "skipped"; reason = why }
                     return [text(siteAddress(r.siteID)), text(r.stormID), text(day(r.arrival)), text(r.departure.map(day) ?? ""), text(status), text(reason),
                             num(String(r.snowDepthInches)), num(String(r.saltPounds)), text(r.crewMemberName), text(r.geofence.rawValue),
                             num(String(r.photos.count)), text(r.note)]
                 }),
            NamedFile(name: "invoices.csv", content: InvoiceCSV.export(d.invoices, customerName: customer, now: now)),
            file("payments.csv", ["Invoice", "Date (UTC)", "Amount", "Method", "Note"],
                 d.invoices.flatMap { inv in inv.payments.map { [text(inv.number), text(day($0.date)), num(money($0.amount)), text($0.method.rawValue), text($0.note)] } }),
            file("time_entries.csv", ["Name", "Job", "Start (UTC)", "End (UTC)", "Hours", "Corrections"],
                 d.timeEntries.map { e in
                     [text(e.memberName), text(e.siteID.map { siteAddress($0) } ?? "General"), text(day(e.start)), text(e.end.map(day) ?? "still clocked in"),
                      num(String(format: "%.2f", e.hours(now: now))), num(String(e.adjustments.count))]
                 }),
            file("quotes.csv", ["Number", "Customer", "Address", "Season", "Terms", "Status", "Created (UTC)", "Valid until (UTC)"],
                 d.quotes.map { [text($0.number), text(customer($0.customerID)), text($0.address), text($0.season), text($0.terms.summary),
                                 text($0.status(now: now).rawValue), text(day($0.createdAt)), text(day($0.validUntil))] }),
        ]
    }
}
