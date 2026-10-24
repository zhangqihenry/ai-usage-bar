import Foundation

/// Persists the last successful snapshot so a cold launch paints numbers
/// immediately instead of a row of dashes.
///
/// The file lives at `~/Library/Application Support/UsageBar/snapshot.json` and
/// contains no credentials: only percentages, reset timestamps and plan names.
public struct SnapshotStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: AppPaths.snapshotFile),
              let snapshot = try? decoder.decode(UsageSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    @discardableResult
    public func save(_ snapshot: UsageSnapshot) -> Bool {
        do {
            try AppPaths.ensureSupportDirectory()
            let data = try encoder.encode(snapshot)
            try data.write(to: AppPaths.snapshotFile, options: .atomic)
            return true
        } catch {
            // A failed cache write must never break a refresh; the app simply
            // starts empty next time.
            return false
        }
    }
}
