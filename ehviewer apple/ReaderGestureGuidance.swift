/// Presentation of existing reader controls. Recognition stays in the reader views.
struct ReaderGestureGuidance {
    enum Input { case touch, pointer }

    let direction: ReadingDirection

    var directionTitle: String {
        switch direction {
        case .leftToRight: "左→右"
        case .rightToLeft: "右→左"
        case .topToBottom: "上→下"
        }
    }

    var leftPageTitle: String { direction == .rightToLeft ? "次のページ" : "前のページ" }
    var rightPageTitle: String { direction == .rightToLeft ? "前のページ" : "次のページ" }
    var showsDoubleTapZoom: Bool { direction != .topToBottom }

    func motionTitle(for input: Input) -> String {
        if direction == .topToBottom { return "上下にスクロールして読む" }
        switch input {
        case .touch: return "左右にスワイプしてもページをめくれます"
        case .pointer: return "ホイールまたはトラックパッドでページをめくる"
        }
    }
}
