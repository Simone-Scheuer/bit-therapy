import Combine
import Schwifty
import SwiftUI

class MouseChaser: Capability {
    @Inject private var appConfig: AppConfig
    @Inject private var mouse: MouseTrackingUseCase

    private let seeker = Seeker()
    private let mousePosition = MousePosition()
    private var disposables = Set<AnyCancellable>()

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
    }

    private func startSeeker() {
        subject?.install(seeker)
        seeker.follow(
            mousePosition,
            to: .center,
            autoAdjustSpeed: true,
            minDistance: 20,  // Increased minimum distance to maintain gap
            maxDistance: 60   // Increased maximum distance for smoother following
        ) { [weak self] in self?.handleCapture(state: $0) }
    }

    private func handleCapture(state: Seeker.State) {
        switch state {
        case .captured:
            // Keep current direction when near the mouse
            if subject?.state != .action(action: .init(id: "idle"), loops: 100) {
                if let animation = subject?.species.animations.first(where: { $0.id == "idle" }) {
                    subject?.set(state: .action(action: animation, loops: 100))
                }
            }
            subject?.movement?.isEnabled = true
        case .escaped, .following:
            // Update direction only when significantly far from target
            if case .action = subject?.state {
                subject?.set(state: .move)
            }
            subject?.movement?.isEnabled = true
            
            // Update direction smoothly to face the mouse
            if let subject = subject {
                let targetPos = mousePosition.frame.origin
                let currentPos = subject.frame.origin
                let angle = atan2(targetPos.y - currentPos.y, targetPos.x - currentPos.x)
                subject.direction = CGVector(dx: cos(angle), dy: sin(angle))
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
        disposables.removeAll()
        super.kill(autoremove: autoremove)
    }
}

private class MousePosition: SeekerTarget {
    var frame: CGRect = .zero
}
