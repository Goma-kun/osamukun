import XCTest
@testable import OsamukunCore

final class StoreTests: XCTestCase {
    func tempStore() -> Store {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("osamukun-test-\(UUID().uuidString)")
        return Store(directory: dir)
    }

    func testSaveAndLoad() throws {
        let store = tempStore()
        XCTAssertEqual(store.loadSnapshot(), Snapshot())
        var s = Snapshot()
        s.upsert(Template(category: "依頼", title: "t", body: "b"), now: 10)
        try store.save(s)
        XCTAssertEqual(store.loadSnapshot(), s)
        let undo = UndoSnapshot(templates: [], label: "「t」の追加", at: 5)
        try store.save(undo)
        XCTAssertEqual(store.loadUndo(), undo)
    }

    /// 拡張機能の JSON エクスポート（配列）をそのまま読める
    func testReadsExtensionExport() throws {
        let json = """
        [{"id":"abc","category":"依頼","title":"資料","body":"本文\\n2行目","createdAt":1722700000000,"updatedAt":1722700000000}]
        """
        let items = try Delimited.templates(fromJSON: Data(json.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].body, "本文\n2行目")
    }

    /// 保存ファイルに新しい欄（deleted）が無くても読める（拡張から移した直後の形）
    func testSnapshotWithoutDeleted() throws {
        let json = #"{"templates":[{"id":"a","category":"","title":"x","body":"y","createdAt":1,"updatedAt":1}]}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.templates.count, 1)
        XCTAssertEqual(s.deleted, [:])
    }

    func testCategoriesAreSortedAndUnique() {
        var s = Snapshot()
        for c in ["連絡", "依頼", " 依頼 ", "", "お礼"] { s.upsert(Template(category: c, title: "t", body: "")) }
        XCTAssertEqual(s.categories, ["お礼", "依頼", "連絡"])
    }

    func testRemoveLeavesTombstone() {
        var s = Snapshot()
        let t = Template(title: "x")
        s.upsert(t, now: 1)
        s.remove(id: t.id, now: 2)
        XCTAssertEqual(s.templates, [])
        XCTAssertEqual(s.deleted[t.id], 2)
        s.restore([t], now: 3)
        XCTAssertNil(s.deleted[t.id])
    }

    func testImportPrependsOrReplaces() {
        var s = Snapshot()
        let old = Template(title: "old")
        s.upsert(old, now: 1)
        let new = Template(title: "new")
        s.importTemplates([new], replace: false, now: 2)
        XCTAssertEqual(s.templates.map(\.title), ["new", "old"])
        s.importTemplates([Template(title: "only")], replace: true, now: 3)
        XCTAssertEqual(s.templates.map(\.title), ["only"])
        XCTAssertEqual(s.deleted[old.id], 3)
    }
}

final class MergeTests: XCTestCase {
    func testNewerWinsAndDeletionPropagates() {
        let a1 = Template(id: "a", title: "a-old", createdAt: 1, updatedAt: 1)
        let a2 = Template(id: "a", title: "a-new", createdAt: 1, updatedAt: 5)
        let b = Template(id: "b", title: "b", createdAt: 2, updatedAt: 2)
        let c = Template(id: "c", title: "c", createdAt: 3, updatedAt: 3)
        let mac = Snapshot(templates: [a2, b], updatedAt: 6, deleted: ["c": 6])
        let phone = Snapshot(templates: [c, a1], updatedAt: 4, deleted: [:])
        let m1 = Merge.snapshots(mac, phone)
        let m2 = Merge.snapshots(phone, mac)
        XCTAssertEqual(m1, m2)
        XCTAssertEqual(m1.templates.map(\.title), ["a-new", "b"])
        XCTAssertEqual(m1.deleted["c"], 6)
    }

    func testEditAfterDeleteRevives() {
        let t = Template(id: "a", title: "revived", createdAt: 1, updatedAt: 9)
        let x = Snapshot(templates: [], updatedAt: 5, deleted: ["a": 5])
        let y = Snapshot(templates: [t], updatedAt: 9)
        let m = Merge.snapshots(x, y)
        XCTAssertEqual(m.templates, [t])
        XCTAssertNil(m.deleted["a"])
    }

    func testConverges() {
        var a = Snapshot(templates: [Template(id: "1", title: "x", createdAt: 1, updatedAt: 1)], updatedAt: 1)
        var b = Snapshot(templates: [Template(id: "2", title: "y", createdAt: 2, updatedAt: 2)], updatedAt: 2)
        for _ in 0..<3 {
            let m = Merge.snapshots(a, b)
            a = m; b = m
        }
        XCTAssertEqual(Set(a.templates.map(\.id)), ["1", "2"])
    }
}

final class SearchTests: XCTestCase {
    func testFilter() {
        let items = [Template(category: "依頼", title: "資料送付", body: "お願いします"),
                     Template(category: "お礼", title: "打ち合わせ", body: "ありがとう"),
                     Template(category: "依頼", title: "Follow Up", body: "Thanks")]
        XCTAssertEqual(Search.filter(items, query: "", category: "").count, 3)
        XCTAssertEqual(Search.filter(items, query: "", category: "依頼").count, 2)
        XCTAssertEqual(Search.filter(items, query: "follow", category: "").map(\.title), ["Follow Up"])
        XCTAssertEqual(Search.filter(items, query: "ありがとう", category: "依頼").count, 0)
        XCTAssertEqual(Search.filter(items, query: " お礼 ", category: "").count, 1)
    }

    func testPreview() {
        XCTAssertEqual(Search.preview("1行目\n\n  3行目  "), "1行目 3行目")
    }
}
