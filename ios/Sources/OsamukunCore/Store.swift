import Foundation

/// 保存先。定型文は `templates.json`（Snapshot）、元に戻す用の控えは `undo.json`。
/// 場所はアプリ側から渡す（Mac は Application Support/Osamukun、テストは一時フォルダ）。
/// 書き込みはアトミック（途中で落ちても前のファイルが残る）
public struct Store: Sendable {
    public let directory: URL
    public var snapshotURL: URL { directory.appendingPathComponent("templates.json") }
    public var undoURL: URL { directory.appendingPathComponent("undo.json") }

    public init(directory: URL) { self.directory = directory }

    public func loadSnapshot() -> Snapshot {
        guard let data = try? Data(contentsOf: snapshotURL) else { return Snapshot() }
        return (try? JSONDecoder().decode(Snapshot.self, from: data)) ?? Snapshot()
    }

    public func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(snapshot).write(to: snapshotURL, options: .atomic)
    }

    public func loadUndo() -> UndoSnapshot? {
        guard let data = try? Data(contentsOf: undoURL) else { return nil }
        return try? JSONDecoder().decode(UndoSnapshot.self, from: data)
    }

    public func save(_ undo: UndoSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(undo).write(to: undoURL, options: .atomic)
    }
}
