import Combine
import Schwifty
import SwiftUI
#if os(macOS)
import AppKit
#endif

class MouseChaser: Capability {
    @Inject private var appConfig: AppConfig
    @Inject private var mouse: MouseTrackingUseCase

    private let seeker = Seeker()
    private let mousePosition = MousePosition()
    private var disposables = Set<AnyCancellable>()
    private let minDistanceToMouse: CGFloat = 40  // Doubled minimum distance between pets
    private let maxDistanceToMouse: CGFloat = 60  // Maximum distance before considering "can't reach"
    private var lastIdleCheck: Date = Date()
    private var idleCheckInterval: TimeInterval = 1.0  // Check every second if we should idle
    #if os(macOS)
    private static var originalCursor: NSCursor?  // Made static to persist across instances
    private static var redDotCursor: NSCursor = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.withAlphaComponent(0.7).setFill()  // Made slightly transparent
        NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 10, height: 10)).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }()
    #endif

    override func install(on subject: Entity) {
        super.install(on: subject)
        subject.capabilities.filter { $0 is Seeker }.forEach { $0.kill() }
        subject.capability(for: AnimationsScheduler.self)?.isEnabled = false
        subject.capability(for: RandomPlatformJumper.self)?.isEnabled = false
        subject.setGravity(enabled: false)
        if let petEntity = subject as? PetEntity {
            petEntity.resetSpeed()
            subject.speed = subject.speed * 1.5  // Increase speed for better following
        }
        startSeeker()
        mouse.position()
            .sink { [weak self] in self?.positionChanged(to: $0) }
            .store(in: &disposables)
        mouse.start()
        
        #if os(macOS)
        // Store original cursor and set red dot
        if Self.originalCursor == nil {
            Self.originalCursor = NSCursor.current
        }
        Self.redDotCursor.set()
        #endif
    }

    private func startSeeker() {
        subject?.install(seeker)
        seeker.follow(
            mousePosition,
            to: .center,
            autoAdjustSpeed: true,
            minDistance: minDistanceToMouse,
            maxDistance: maxDistanceToMouse
        ) { [weak self] in self?.handleCapture(state: $0) }
    }

    private func handleCapture(state: Seeker.State) {
        guard let subject = subject else { return }
        
        switch state {
        case .captured:
            // When near the mouse, show idle animation
            if subject.state != .action(action: .init(id: "idle"), loops: 100) {
                if let animation = subject.species.animations.first(where: { $0.id == "idle" }) {
                    subject.set(state: .action(action: animation, loops: 100))
                }
            }
            subject.movement?.isEnabled = true
            
        case .escaped, .following:
            // Check if we're stuck trying to reach an unreachable position
            let now = Date()
            if now.timeIntervalSince(lastIdleCheck) >= idleCheckInterval {
                lastIdleCheck = now
                
                let targetPos = mousePosition.frame.origin
                let currentPos = subject.frame.origin
                let distance = hypot(targetPos.x - currentPos.x, targetPos.y - currentPos.y)
                
                // If we're beyond maxDistance and there might be obstacles, show idle animation
                if distance > maxDistanceToMouse {
                    if subject.state != .action(action: .init(id: "idle"), loops: 100) {
                        if let animation = subject.species.animations.first(where: { $0.id == "idle" }) {
                            subject.set(state: .action(action: animation, loops: 100))
                        }
                    }
                    return
                }
            }
            
            // Normal following behavior
            if case .action = subject.state {
                subject.set(state: .move)
            }
            subject.movement?.isEnabled = true
            
            // Update direction smoothly to face the mouse
            let targetPos = mousePosition.frame.origin
            let currentPos = subject.frame.origin
            let angle = atan2(targetPos.y - currentPos.y, targetPos.x - currentPos.x)
            subject.direction = CGVector(dx: cos(angle), dy: sin(angle))
            
            // Maintain minimum distance from other following pets
            if let world = subject.world {
                for other in world.children where other != subject {
                    if other.capability(for: MouseChaser.self) != nil {
                        let dx = subject.frame.midX - other.frame.midX
                        let dy = subject.frame.midY - other.frame.midY
                        let distance = hypot(dx, dy)
                        
                        if distance < minDistanceToMouse {
                            // Add a small repulsion force
                            let repulsion: CGFloat = 5.0
                            let angle = atan2(dy, dx)
                            subject.frame.origin.x += cos(angle) * repulsion
                            subject.frame.origin.y += sin(angle) * repulsion
                        }
                    }
                }
            }
        }
    }

    private func positionChanged(to point: CGPoint) {
        mousePosition.frame = CGRect(origin: point, size: .zero)
    }

    override func kill(autoremove: Bool = true) {
        mouse.stop()
        seeker.kill()
        subject?.capability(for: AnimationsScheduler.self)?.isEnabled = true
        subject?.capability(for: RandomPlatformJumper.self)?.isEnabled = true
        subject?.setGravity(enabled: appConfig.gravityEnabled)
        subject?.set(state: .move)
        subject?.direction = CGVector(dx: 1, dy: 0)
        subject?.movement?.isEnabled = true
        if let petEntity = subject as? PetEntity {
            petEntity.resetSpeed()
        }
        
        #if os(macOS)
        // Restore original cursor
        Self.originalCursor?.set()
        #endif
        
        disposables.removeAll()
        super.kill(autoremove: autoremove)
    }
}

private class MousePosition: SeekerTarget {
    var frame: CGRect = .zero
}
