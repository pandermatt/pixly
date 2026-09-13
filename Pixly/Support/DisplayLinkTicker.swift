import QuartzCore
#if os(macOS)
import AppKit
#endif

@MainActor
final class DisplayLinkTicker: NSObject {
    private var link: CADisplayLink?
    private let onTick: @MainActor (CFTimeInterval) -> Void

    init(onTick: @escaping @MainActor (CFTimeInterval) -> Void) {
        self.onTick = onTick
    }

    func start() {
        guard link == nil else { return }
        #if os(macOS)
        // CADisplayLink has no public initializer on macOS; the screen vends one.
        guard let link = NSScreen.main?.displayLink(target: self, selector: #selector(step)) else { return }
        #else
        let link = CADisplayLink(target: self, selector: #selector(step))
        #endif
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        onTick(link.timestamp)
    }
}
