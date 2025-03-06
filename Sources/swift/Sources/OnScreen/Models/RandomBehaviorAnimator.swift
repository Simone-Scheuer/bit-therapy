import Foundation
import Schwifty

/// A dedicated capability for managing random pet behaviors/animations
public class RandomBehaviorAnimator: Capability {
    @Inject private var settings: AppConfig
    
    // Core animation configuration
    private let behaviors = [
        Behavior(id: "sleep", weight: 0.25, minDuration: 8, maxDuration: 12),
        Behavior(id: "eat", weight: 0.25, minDuration: 4, maxDuration: 6),
        Behavior(id: "idle", weight: 0.15, minDuration: 2, maxDuration: 3),
        Behavior(id: "front", weight: 0.10, minDuration: 1, maxDuration: 2)
    ]
    
    // Sleep mode
    private(set) var isSleepModeEnabled = false
    private var sleepTimer: Timer?
    
    // State tracking
    private var isPerformingBehavior = false
    private var currentBehaviorTimer: Timer?
    private var nextBehaviorTimer: Timer?
    private var lastBehaviorTime: TimeInterval = 0
    private var lastGroundY: CGFloat?
    private var lastAnimationEndTime: TimeInterval = 0
    private let animationCooldown: TimeInterval = 8.0  // 8 second cooldown
    
    // Per-cat randomization
    private var randomSeed: UInt64 = 0
    private var rng: SeededRandomNumberGenerator
    
    // Configuration
    private let baseAnimationInterval: TimeInterval = 45.0  // Increased from 25 to 45 seconds
    private let randomIntervalVariation: TimeInterval = 20.0 // Increased variation
    private let groundCheckThreshold: CGFloat = 5.0  // Threshold for ground detection
    private let minimumMovementTime: TimeInterval = 15.0  // Increased from 8 to 15 seconds
    
    // Track gravity state
    private var wasGravityEnabled: Bool = true
    
    required init() {
        // Initialize rng with a default seed
        self.randomSeed = UInt64(ProcessInfo.processInfo.systemUptime * 1000)
        self.rng = SeededRandomNumberGenerator(seed: self.randomSeed)
        super.init()
    }
    
    override public func install(on subject: Entity) {
        super.install(on: subject)
        
        // Create a unique random seed for this cat based on its ID
        if let petEntity = subject as? PetEntity {
            randomSeed = UInt64(abs(petEntity.id.hash))
        } else {
            randomSeed = UInt64(ProcessInfo.processInfo.systemUptime * 1000)
        }
        rng = SeededRandomNumberGenerator(seed: randomSeed)
        
        Logger.log("RandomBehavior", "Installing on \(subject) with seed \(randomSeed)")
        isEnabled = true
        
        // Reset state tracking variables
        isPerformingBehavior = false
        lastBehaviorTime = 0
        lastAnimationEndTime = 0
        lastGroundY = nil
        
        // Start with a random delay unique to this cat
        let initialDelay = Double.random(in: 5.0...30.0, using: &rng)
        scheduleBehavior(delay: initialDelay)
        
        // Add observer for state changes to handle interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .init("EntityStateChanged"),
            object: subject
        )
    }
    
    override public func kill(autoremove: Bool = true) {
        NotificationCenter.default.removeObserver(self)
        stopAllTimers()
        super.kill(autoremove: autoremove)
    }
    
    private func stopAllTimers() {
        currentBehaviorTimer?.invalidate()
        nextBehaviorTimer?.invalidate()
        sleepTimer?.invalidate()
        currentBehaviorTimer = nil
        nextBehaviorTimer = nil
        sleepTimer = nil
    }
    
    // MARK: - Sleep Mode
    
    public func toggleSleepMode() {
        isSleepModeEnabled = !isSleepModeEnabled
        
        if isSleepModeEnabled {
            enableSleepMode()
        } else {
            disableSleepMode()
        }
    }
    
    private func enableSleepMode() {
        guard let subject = subject else { return }
        
        // Store gravity state before disabling
        wasGravityEnabled = settings.gravityEnabled
        
        // Stop all current behaviors and movement
        stopAllTimers()
        subject.movement?.isEnabled = false
        subject.setGravity(enabled: false)  // Explicitly disable gravity
        
        // Start sleeping animation with high loop count
        let animation = EntityAnimation(id: "sleep")
        subject.set(state: .action(action: animation, loops: 1000))
        
        // Keep checking if sleep mode is still enabled
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let subject = self.subject,
                  self.isSleepModeEnabled else {
                self?.sleepTimer?.invalidate()
                return
            }
            
            // Ensure sleep animation continues and gravity stays disabled
            if case .move = subject.state {
                subject.setGravity(enabled: false)
                subject.set(state: .action(action: animation, loops: 1000))
            }
        }
    }
    
    private func disableSleepMode() {
        guard let subject = subject else { return }
        
        // Stop sleep timer
        sleepTimer?.invalidate()
        sleepTimer = nil
        
        // Reset to normal state
        subject.movement?.isEnabled = true
        subject.set(state: .move)
        
        // Restore previous gravity state
        subject.setGravity(enabled: wasGravityEnabled && settings.gravityEnabled)
        
        if let petEntity = subject as? PetEntity {
            petEntity.resetSpeed()
        }
        
        // Ensure the animation system is properly re-enabled
        isEnabled = true
        isPerformingBehavior = false
        lastBehaviorTime = 0
        lastAnimationEndTime = 0
        
        // Resume normal behavior scheduling with random delay
        scheduleBehavior(delay: Double.random(in: 5.0...10.0, using: &rng))
        
        Logger.log("RandomBehavior", "[\(subject.id)] Sleep mode disabled, resuming normal animations")
    }
    
    private func scheduleBehavior(delay: TimeInterval? = nil) {
        guard let subject = subject,
              subject.isAlive,
              !isSleepModeEnabled else { return }
        
        stopAllTimers()
        
        // Ensure minimum movement time between animations
        let timeSinceLastBehavior = ProcessInfo.processInfo.systemUptime - lastBehaviorTime
        let minimumDelay = max(0, minimumMovementTime - timeSinceLastBehavior)
        
        // Calculate delay if not provided, using per-cat RNG
        let baseDelay = delay ?? calculateNextBehaviorDelay()
        let actualDelay = max(baseDelay, minimumDelay)
        
        Logger.log("RandomBehavior", "[\(subject.id)] Scheduling next behavior in \(String(format: "%.1f", actualDelay))s")
        
        nextBehaviorTimer = Timer.scheduledTimer(withTimeInterval: actualDelay, repeats: false) { [weak self] _ in
            self?.tryStartBehavior()
        }
    }
    
    private func calculateNextBehaviorDelay() -> TimeInterval {
        // Base interval plus random variation, using per-cat RNG
        let baseDelay = baseAnimationInterval + Double.random(in: -randomIntervalVariation...randomIntervalVariation, using: &rng)
        return baseDelay / max(0.5, settings.animationFrequency)
    }
    
    private func tryStartBehavior() {
        guard let subject = subject,
              subject.isAlive,
              isEnabled,
              !isPerformingBehavior,
              !isSleepModeEnabled else {  // Added sleep mode check
            scheduleBehavior()
            return
        }
        
        // Increased chance to skip animation (from 0.4 to 0.6)
        if Double.random(in: 0...1, using: &rng) < 0.6 {
            Logger.log("RandomBehavior", "[\(subject.id)] Skipping animation to continue movement")
            scheduleBehavior()
            return
        }
        
        // Check animation cooldown
        let currentTime = ProcessInfo.processInfo.systemUptime
        if currentTime - lastAnimationEndTime < animationCooldown {
            scheduleBehavior(delay: animationCooldown - (currentTime - lastAnimationEndTime))
            return
        }
        
        // Don't start behaviors in these states
        if case .drag = subject.state { 
            scheduleBehavior(delay: Double.random(in: 1.0...3.0, using: &rng))
            return 
        }
        if case .freeFall = subject.state {
            scheduleBehavior(delay: Double.random(in: 1.0...3.0, using: &rng))
            return
        }
        if subject.wallWalker?.isWallWalkingEnabled == true { 
            scheduleBehavior(delay: Double.random(in: 1.0...3.0, using: &rng))
            return 
        }
        if subject.capability(for: MouseChaser.self) != nil { 
            scheduleBehavior(delay: Double.random(in: 1.0...3.0, using: &rng))
            return 
        }
        
        // Check if we're on stable ground
        let currentY = subject.frame.origin.y
        if let lastY = lastGroundY {
            if abs(currentY - lastY) > groundCheckThreshold {
                scheduleBehavior(delay: Double.random(in: 1.0...3.0, using: &rng))
                return
            }
        }
        lastGroundY = currentY
        
        // Select and perform a behavior
        if let behavior = selectBehavior() {
            performBehavior(behavior)
        } else {
            scheduleBehavior()
        }
    }
    
    private func selectBehavior() -> Behavior? {
        guard let subject = subject else { return nil }
        
        // Get available behaviors for this species
        let availableBehaviors = behaviors.filter { behavior in
            subject.species.animations.contains { $0.id == behavior.id }
        }
        
        guard !availableBehaviors.isEmpty else { return nil }
        
        // If currently in an action, slightly lower chance of same animation
        if case .action(let currentAction, _) = subject.state {
            let currentBehavior = availableBehaviors.first { $0.id == currentAction.id }
            if let current = currentBehavior,
               Double.random(in: 0...1, using: &rng) < 0.7 { // 70% chance to pick different animation
                let others = availableBehaviors.filter { $0.id != current.id }
                if !others.isEmpty {
                    return weightedRandomBehavior(from: others)
                }
            }
        }
        
        return weightedRandomBehavior(from: availableBehaviors)
    }
    
    private func weightedRandomBehavior(from behaviors: [Behavior]) -> Behavior? {
        let totalWeight = behaviors.reduce(0.0) { $0 + $1.weight }
        let random = Double.random(in: 0..<totalWeight, using: &rng)
        
        var accumulated = 0.0
        for behavior in behaviors {
            accumulated += behavior.weight
            if random < accumulated {
                return behavior
            }
        }
        
        return behaviors.last
    }
    
    private func performBehavior(_ behavior: Behavior) {
        guard let subject = subject else { return }
        
        isPerformingBehavior = true
        lastBehaviorTime = ProcessInfo.processInfo.systemUptime
        
        // Store current state
        let currentPosition = subject.frame.origin
        let currentDirection = subject.direction
        let currentGravityState = settings.gravityEnabled
        
        // Temporarily disable movement but maintain gravity state
        subject.movement?.isEnabled = false
        
        // Create and play the animation with random duration
        let animation = EntityAnimation(id: behavior.id)
        let duration = Double.random(in: behavior.minDuration...behavior.maxDuration, using: &rng)
        let loops = Int(duration * Double(subject.fps))
        
        // Add safety check for eat animation
        let maxLoops = behavior.id == "eat" ? 20 : loops  // Limit eat animation to prevent infinite loops
        
        Logger.log("RandomBehavior", "[\(subject.id)] Starting behavior: \(behavior.id) for \(String(format: "%.1f", duration))s")
        
        // Set the animation state
        subject.set(state: .action(action: animation, loops: maxLoops))
        
        // Ensure position is maintained if not falling
        if case .freeFall = subject.state {
            // Let gravity continue to work
        } else {
            subject.frame.origin = currentPosition
        }
        
        // Schedule behavior end
        currentBehaviorTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self, weak subject] _ in
            guard let self = self, let subject = subject else { return }
            
            // Only reset position if we're not falling
            if case .freeFall = subject.state {
                // Let the pet continue falling
            } else {
                subject.frame.origin = currentPosition
            }
            
            // Reset state and ensure movement is enabled
            subject.movement?.isEnabled = true
            subject.set(state: .move)
            
            // Restore gravity state
            subject.setGravity(enabled: currentGravityState && self.settings.gravityEnabled)
            
            // Randomly choose new direction using per-cat RNG
            if Double.random(in: 0...1, using: &self.rng) < 0.5 {
                subject.direction = CGVector(dx: currentDirection.dx * -1, dy: 0)
            } else {
                subject.direction = currentDirection
            }
            
            // Reset speed to ensure movement
            if let petEntity = subject as? PetEntity {
                petEntity.resetSpeed()
            }
            
            // Update animation end time for cooldown
            self.lastAnimationEndTime = ProcessInfo.processInfo.systemUptime
            
            // Schedule next behavior
            self.isPerformingBehavior = false
            self.scheduleBehavior()
            
            Logger.log("RandomBehavior", "[\(subject.id)] Completed behavior: \(behavior.id)")
        }
    }
    
    /// Public method to request a behavior attempt
    public func requestBehavior() {
        tryStartBehavior()
    }
    
    @objc private func handleStateChange() {
        guard let subject = subject else { return }
        
        // If we're in move state and not performing a behavior, ensure scheduling is active
        if case .move = subject.state, !isPerformingBehavior {
            if nextBehaviorTimer == nil {
                Logger.log("RandomBehavior", "[\(subject.id)] Restarting behavior scheduling after state change")
                scheduleBehavior(delay: Double.random(in: 2.0...5.0, using: &rng))
            }
        }
    }
}

// MARK: - Supporting Types

private struct Behavior {
    let id: String
    let weight: Double
    let minDuration: TimeInterval
    let maxDuration: TimeInterval
}

// MARK: - Random Number Generator

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var rng: RandomXoshiro
    
    init(seed: UInt64) {
        rng = RandomXoshiro(seed: seed)
    }
    
    mutating func next() -> UInt64 {
        rng.next()
    }
}

// MARK: - Entity Extension

public extension Entity {
    internal var randomBehavior: RandomBehaviorAnimator? {
        capability(for: RandomBehaviorAnimator.self)
    }
} 