import Foundation
import Schwifty

public class AnimationsScheduler: Capability {
    @Inject private var settings: AppConfig
    
    private static let logTag = "AnimationsScheduler"
    private var isAnimating = false
    private var scheduledAnimationTimer: Timer?
    private var lastAnimationTime: TimeInterval = 0
    private let minTimeBetweenAnimations: TimeInterval = 3.0
    
    override public func install(on subject: Entity) {
        super.install(on: subject)
        Logger.log(Self.logTag, "Installing on \(subject)")
        
        // Always start enabled
        isEnabled = true
        
        // Start with an immediate animation after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.animateNow()
        }
        
        // Start the animation timer
        scheduleNextAnimation()
        
        // Add observer for state changes to re-enable animations
        NotificationCenter.default.addObserver(forName: .init("EntityStateChanged"), object: subject, queue: .main) { [weak self] _ in
            guard let self = self,
                  let subject = self.subject,
                  case .move = subject.state else { return }
            
            // Re-enable animations when returning to move state
            if !self.isEnabled {
                Logger.log(Self.logTag, "Re-enabling animations after state change")
                self.isEnabled = true
                self.scheduleNextAnimation()
            }
        }
    }
    
    override public func kill(autoremove: Bool = true) {
        NotificationCenter.default.removeObserver(self)
        scheduledAnimationTimer?.invalidate()
        scheduledAnimationTimer = nil
        super.kill(autoremove: autoremove)
    }

    public func animateNow() {
        let subjectAlive = subject?.isAlive == true
        guard let subject = self.subject,
              subjectAlive,
              !isAnimating else {
            Logger.log(Self.logTag, "Cannot animate now - isAnimating: \(isAnimating), subject alive: \(subjectAlive)")
            return
        }
        
        // Check if enough time has passed since last animation
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timeSinceLastAnimation = currentTime - lastAnimationTime
        let adjustedMinTime = minTimeBetweenAnimations / max(0.5, settings.animationFrequency)
        
        if timeSinceLastAnimation < adjustedMinTime {
            Logger.log(Self.logTag, "Too soon for next animation, waiting...")
            return
        }
        
        // Get a random animation
        guard let animation = subject.animationsProvider?.randomAnimation() else {
            Logger.log(Self.logTag, "No animation available")
            return
        }
        
        let loops = animation.requiredLoops ?? Int.random(in: 3 ... 5)
        schedule(animation, times: loops, after: 0)
        Logger.log(Self.logTag, "Immediate animation requested: \(animation.id) x\(loops)")
    }

    private func scheduleNextAnimation() {
        // Cancel any existing timer
        scheduledAnimationTimer?.invalidate()
        
        guard let subject = self.subject,
              subject.isAlive else {
            Logger.log(Self.logTag, "Cannot schedule - subject not available or not alive")
            return
        }
        
        // Calculate next animation delay based on frequency setting
        let baseDelay = TimeInterval.random(in: 5 ... 10)
        let adjustedDelay = baseDelay / max(0.5, settings.animationFrequency)
        
        Logger.log(Self.logTag, "Scheduling next animation in \(adjustedDelay)s")
        
        // Use Timer for more reliable scheduling
        scheduledAnimationTimer = Timer.scheduledTimer(withTimeInterval: adjustedDelay, repeats: false) { [weak self] _ in
            self?.tryAnimation()
        }
    }
    
    private func tryAnimation() {
        guard let subject = self.subject,
              subject.isAlive,
              isEnabled else {
            scheduleNextAnimation() // Reschedule if not ready
            return
        }
        
        // Force an animation if it's been too long
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timeSinceLastAnimation = currentTime - lastAnimationTime
        
        if timeSinceLastAnimation > 15.0 {  // Force after 15 seconds
            if let animation = subject.animationsProvider?.randomAnimation() {
                let loops = animation.requiredLoops ?? Int.random(in: 3 ... 5)
                load(animation, times: loops)
                lastAnimationTime = currentTime
            }
        } else {
            animateNow()  // Try normal animation
        }
        
        scheduleNextAnimation()  // Schedule next attempt
    }

    public func schedule(_ animation: EntityAnimation, times: Int, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self,
                  let subject = self.subject,
                  self.isEnabled,
                  subject.isAlive else {
                Logger.log(Self.logTag, "Cannot schedule - scheduler is disabled or subject unavailable")
                return
            }
            
            self.load(animation, times: times)
            self.scheduleNextAnimation()
        }
    }

    public func load(_ animation: EntityAnimation, times: Int) {
        guard let subject = self.subject else { return }
        
        // Allow loading even if not in move state
        if case .action(let currentAction, _) = subject.state {
            // Only skip if we're in the middle of the same animation
            if currentAction.id == animation.id { return }
        }
        
        isAnimating = true
        Logger.log(Self.logTag, "Loading animation: \(animation.id) x\(times)")
        
        // Store current position and direction
        let currentPosition = subject.frame.origin
        let currentDirection = subject.direction
        
        // Temporarily disable movement while animating
        subject.movement?.isEnabled = false
        
        // Play the animation
        subject.set(state: .action(action: animation, loops: times))
        
        // Ensure the pet stays at its current position
        subject.frame.origin = currentPosition
        
        // Calculate animation duration based on fps and loops
        let duration = Double(times) / Double(subject.fps)
        
        // Reset state after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak subject] in
            guard let subject = subject else { return }
            
            // Re-enable movement
            subject.movement?.isEnabled = true
            
            // Reset to move state with original direction
            subject.set(state: .move)
            subject.direction = currentDirection
            
            // Reset animation flag and update timing
            self?.isAnimating = false
            self?.lastAnimationTime = ProcessInfo.processInfo.systemUptime
            self?.scheduleNextAnimation()
            
            Logger.log(Self.logTag, "Animation completed: \(animation.id)")
        }
    }
}

public extension Entity {
    var animationsScheduler: AnimationsScheduler? {
        capability(for: AnimationsScheduler.self)
    }
}
