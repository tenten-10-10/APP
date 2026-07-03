import Foundation
import CloudKit

/// Directly exercises the deployed CloudKit schema from inside the app.
///
/// Why this exists: when NSPersistentCloudKitContainer fails to export/share, the
/// `event.error` the app receives is a bare `CKError #2` (partialFailure) with NO
/// per-record detail — the real reason (a missing/mismatched field, an illegal
/// index, a security-role problem, or a sharing restriction) is written only to
/// the device console. A DIRECT `CKDatabase` operation, by contrast, returns that
/// reason in the CKError's `ServerErrorDescription`. So to find out WHY sharing
/// fails without a Mac/Console/Dashboard, we:
///   1. create a throwaway custom zone in the user's PRIVATE database,
///   2. write a `CD_Project` record (same record type Core Data mirrors),
///   3. create a `CKShare` for it (exactly the operation that is failing),
///   4. report the full server error for whichever step fails,
///   5. delete the throwaway zone so nothing is left behind.
enum CloudKitSchemaProbe {

    static func run(completion: @escaping (String) -> Void) {
        let ck = CKContainer(identifier: AppConfig.cloudKitContainerIdentifier)
        let db = ck.privateCloudDatabase
        // A dedicated probe zone: isolated from real data and safe to delete.
        let zoneID = CKRecordZone.ID(zoneName: "TanamiruProbeZone", ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        var report: [String] = ["=== CloudKit 直接テスト ==="]

        func finish() {
            // Always try to clean up the probe zone (ignore its result).
            db.delete(withRecordZoneID: zoneID) { _, _ in
                DispatchQueue.main.async { completion(report.joined(separator: "\n")) }
            }
        }

        func dump(_ error: Error) -> String {
            CloudKitErrorMapper.fullDiagnosticDump(for: error) ?? (error as NSError).localizedDescription
        }

        // Step 1: create the probe zone.
        db.save(zone) { _, zoneError in
            if let zoneError = zoneError {
                report.append("① ゾーン作成: 失敗")
                report.append(dump(zoneError))
                finish(); return
            }
            report.append("① ゾーン作成: OK")

            // Step 2 + 3: write a CD_Project record AND create a CKShare for it in
            // one operation — this is exactly what fails when the user shares.
            let recordID = CKRecord.ID(recordName: "probe-\(UUID().uuidString)", zoneID: zoneID)
            let record = CKRecord(recordType: "CD_Project", recordID: recordID)
            record["CD_entityName"] = "Project" as CKRecordValue
            record["CD_id"] = UUID().uuidString as CKRecordValue
            record["CD_name"] = "probe" as CKRecordValue

            let share = CKShare(rootRecord: record)
            share[CKShare.SystemFieldKey.title] = "probe share" as CKRecordValue

            let op = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
            op.savePolicy = .allKeys
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    report.append("② CD_Project 書き込み + 共有作成: OK ✅")
                    report.append("→ スキーマ・共有ともに正常。問題は既存の壊れた共有か、特定レコードの可能性。")
                case .failure(let error):
                    report.append("② CD_Project 書き込み + 共有作成: 失敗 ❌")
                    report.append(dump(error))
                }
                finish()
            }
            // Per-record failures carry the most specific ServerErrorDescription.
            op.perRecordSaveBlock = { recordID, result in
                if case .failure(let error) = result {
                    report.append("・レコード \(recordID.recordName.prefix(24))… の理由:")
                    report.append(dump(error))
                }
            }
            db.add(op)
        }
    }
}
