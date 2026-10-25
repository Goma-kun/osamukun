import Foundation

/// サンプル定型文。画面の言語に合わせて出し分ける（拡張の `SAMPLE_TEMPLATES_JA` / `_EN` と同じ 10 件）。
/// 職場の実データは一切含めない。一般的なビジネス定型文を新規に書いたもの
public enum Samples {
    public static func templates(japanese: Bool, now: Double = Template.nowMs()) -> [Template] {
        let src = japanese ? ja : en
        return src.enumerated().map { i, s in
            Template(id: Template.newID(), category: s.0, title: s.1, body: s.2,
                     createdAt: now + Double(i), updatedAt: now + Double(i))
        }
    }

    static let ja: [(String, String, String)] = [
        ("挨拶", "初回の挨拶（社外）",
         "お世話になっております。\n株式会社〇〇の△△と申します。\n\nこの度は□□の件でご連絡いたしました。\n今後ともどうぞよろしくお願いいたします。"),
        ("依頼", "資料送付のお願い",
         "お世話になっております。\n\n〇〇の件につきまして、関連資料をお送りいただけますでしょうか。\nお忙しいところ恐れ入りますが、□月□日までにいただけますと幸いです。\n\nよろしくお願いいたします。"),
        ("依頼", "確認のお願い",
         "お世話になっております。\n\n先日お送りした〇〇について、ご確認いただけましたでしょうか。\nご不明な点がございましたら、お気軽にお知らせください。\n\nよろしくお願いいたします。"),
        ("お礼", "打ち合わせのお礼",
         "お世話になっております。\n\n本日はお忙しい中、お時間をいただきありがとうございました。\nいただいたご意見をもとに、〇〇を進めてまいります。\n\n引き続きよろしくお願いいたします。"),
        ("日程調整", "打ち合わせ日程の候補提示",
         "お世話になっております。\n\n〇〇の打ち合わせにつきまして、下記の日程でご都合はいかがでしょうか。\n\n・□月□日（□）□:00〜\n・□月□日（□）□:00〜\n・□月□日（□）□:00〜\n\nご都合の良い日時をお知らせいただけますと幸いです。"),
        ("日程調整", "日程変更のお願い",
         "お世話になっております。\n\n□月□日にお約束しておりました打ち合わせについて、誠に恐れ入りますが、都合により日程を変更させていただけないでしょうか。\n\n改めて候補日をお送りいたしますので、ご検討いただけますと幸いです。\nご迷惑をおかけして申し訳ございません。"),
        ("謝罪", "返信遅れのお詫び",
         "お世話になっております。\n\nご連絡いただいておりました件、返信が遅くなり申し訳ございません。\n\n〇〇につきましては、下記のとおりです。\n\n今後ともよろしくお願いいたします。"),
        ("連絡", "添付ファイル送付",
         "お世話になっております。\n\n〇〇の資料を添付にてお送りいたします。\nご確認のほど、よろしくお願いいたします。\n\n※添付：□□.pdf"),
        ("連絡", "不在のお知らせ",
         "お世話になっております。\n\n誠に勝手ながら、□月□日（□）は終日不在にしております。\nお急ぎの場合は、△△（メール：xxx@example.com）までご連絡ください。\n\nご不便をおかけしますが、よろしくお願いいたします。"),
        ("社内", "会議リマインド",
         "お疲れさまです。\n\n本日□:00より〇〇会議を行います。\n場所：△△（オンラインの場合はリンク参照）\n\n資料は事前に共有フォルダをご確認ください。\nよろしくお願いします。"),
    ]

    static let en: [(String, String, String)] = [
        ("Greetings", "First contact (external)",
         "Hello,\n\nMy name is [your name] from [company]. I am getting in touch about [subject].\n\nI look forward to working with you.\n\nBest regards,\n[your name]"),
        ("Requests", "Asking for documents",
         "Hello,\n\nCould you send over the material related to [subject]?\n\nIf you are able to get it to me by [date], that would be a great help.\n\nThank you,\n[your name]"),
        ("Requests", "Following up for a review",
         "Hello,\n\nI wanted to check whether you have had a chance to look at [subject] that I sent over on [date].\n\nHappy to answer any questions.\n\nThank you,\n[your name]"),
        ("Thanks", "After a meeting",
         "Hello,\n\nThank you for making time today. I appreciated the discussion.\n\nBased on what we agreed, I will move ahead with [next step] and come back to you by [date].\n\nBest regards,\n[your name]"),
        ("Scheduling", "Offering meeting times",
         "Hello,\n\nWould any of the following work for a meeting about [subject]?\n\n- [date], [time]\n- [date], [time]\n- [date], [time]\n\nEach slot is about [duration]. Let me know which suits you and I will send an invitation.\n\nThank you,\n[your name]"),
        ("Scheduling", "Asking to reschedule",
         "Hello,\n\nI am sorry to ask, but something has come up and I need to move our meeting on [date].\n\nI will send a few alternative times shortly. Apologies for the inconvenience.\n\nThank you for understanding,\n[your name]"),
        ("Apologies", "Late reply",
         "Hello,\n\nApologies for the slow reply on [subject].\n\nHere is where things stand: [details]\n\nThank you for your patience,\n[your name]"),
        ("Updates", "Sending an attachment",
         "Hello,\n\nPlease find the [subject] material attached.\n\nDo let me know if anything is unclear.\n\nBest regards,\n[your name]\n\nAttached: [filename]"),
        ("Updates", "Out of office",
         "Hello,\n\nI will be away from my desk all day on [date].\n\nIf it is urgent, please contact [colleague] at [email].\n\nThank you,\n[your name]"),
        ("Internal", "Meeting reminder",
         "Hi all,\n\nA reminder that the [subject] meeting starts at [time] today.\n\nWhere: [room, or the link in the invitation]\n\nThe material is in the shared folder — please take a look beforehand.\n\nThanks,\n[your name]"),
    ]
}
