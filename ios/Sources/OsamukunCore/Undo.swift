import Foundation

/// 「元に戻す」の 1 段。破壊的な操作の直前の状態を 1 つだけ保持する。版管理までは持たず、
/// 「直前のやらかしを取り消す」に絞る（拡張と同じ設計判断）。
/// `isUndo` は「この状態に戻すと、いま取り消した操作をやり直すことになる」という印
public struct UndoSnapshot: Codable, Equatable, Sendable {
    public var templates: [Template]
    public var label: String
    public var at: Double
    public var isUndo: Bool

    public init(templates: [Template], label: String, at: Double = Template.nowMs(), isUndo: Bool = false) {
        self.templates = templates
        self.label = label
        self.at = at
        self.isUndo = isUndo
    }
}
