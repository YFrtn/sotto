import AppKit
import SwiftUI

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }
}

/// A floating, non-activating panel adapted from a blog-style NSPanel implementation.
final class FloatingPanel<Content: View>: NSPanel {
    @Binding private var isPresented: Bool
    private let hostingView: TransparentHostingView<Content>

    init(
        @ViewBuilder view: () -> Content,
        contentRect: NSRect,
        isPresented: Binding<Bool>
    ) {
        self._isPresented = isPresented
        self.hostingView = TransparentHostingView(rootView: view())

        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        ignoresMouseEvents = true
        hasShadow = false

        contentView = hostingView
    }

    func updateView(@ViewBuilder _ view: () -> Content) {
        hostingView.rootView = view()
    }

    override func resignMain() {
        super.resignMain()
        close()
    }

    override func close() {
        super.close()
        isPresented = false
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Position the panel at the bottom-center of the main screen.
    func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - (frame.width / 2)
        let y = screenFrame.minY + 15
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Сдвинуть окно на дельту от drag-жеста SwiftUI.
    /// SwiftUI отдаёт translation в координатах "сверху вниз" — на macOS Y инвертирован.
    func move(by translation: CGSize) {
        let newOrigin = NSPoint(
            x: frame.origin.x + translation.width,
            y: frame.origin.y - translation.height
        )
        setFrameOrigin(clamp(origin: newOrigin))
    }

    /// Не позволяем утащить пилюлю полностью за пределы экрана.
    private func clamp(origin: NSPoint) -> NSPoint {
        guard let screen = NSScreen.main else { return origin }
        let visible = screen.visibleFrame
        let minX = visible.minX - frame.width + 40   // оставляем 40pt пилюли видимыми
        let maxX = visible.maxX - 40
        let minY = visible.minY - frame.height + 40
        let maxY = visible.maxY - 40
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
}
