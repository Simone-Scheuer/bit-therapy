import Foundation
import Schwifty

class CatAnimationsProvider: AnimationsProvider {
    @Inject private var settings: AppConfig
    
    private let baseAnimationIds = ["front", "idle", "eat", "sleep"]
    private var lastAnimationTime: TimeInterval = 0
    private let minTimeBetweenAnimations: TimeInterval = 2.0  // Even more aggressive!
    
    override func randomAnimation() -> EntityAnimation? {
        guard let subject = subject else {
            Logger.log("CatAnimations", "No subject available")
            return nil
        }
        
        // Get available animations first
        let availableAnimations = subject.species.animations.filter { animation in
            baseAnimationIds.contains(animation.id)
        }
        
        guard !availableAnimations.isEmpty else {
            Logger.log("CatAnimations", "No available animations")
            return nil
        }
        
        // CRITICAL STATE CHECKS
        // Only block animations in these specific cases
        if case .drag = subject.state { return nil }
        if subject.wallWalker?.isWallWalkingEnabled == true { return nil }
        
        // Allow animations during other states
        if case .action(let currentAction, _) = subject.state {
            // Only block if we're in the middle of the same animation
            if let nextAnimation = availableAnimations.randomElement(),
               currentAction.id == nextAnimation.id {
                return nil
            }
        }
        
        // OVERRIDE: Super aggressive timing system
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timeSinceLastAnimation = currentTime - lastAnimationTime
        
        // Force an animation if it's been too long (8 seconds)
        let shouldForceAnimation = timeSinceLastAnimation > 8.0
        
        // Normal timing check but more frequent
        let adjustedMinTime = minTimeBetweenAnimations / max(0.5, settings.animationFrequency)
        if !shouldForceAnimation && timeSinceLastAnimation < adjustedMinTime {
            return nil
        }
        
        // Update last animation time
        lastAnimationTime = currentTime
        
        // OVERRIDE: More aggressive weighting system
        let weights: [(String, Double)] = [
            ("eat", 0.35),    // 35% chance for eat
            ("sleep", 0.35),  // 35% chance for sleep
            ("idle", 0.2),    // 20% chance for idle
            ("front", 0.1)    // 10% chance for front
        ]
        
        // If forcing an animation, bias heavily towards eat/sleep
        if shouldForceAnimation {
            let forcedWeights: [(String, Double)] = [
                ("eat", 0.5),     // 50% chance for eat when forced
                ("sleep", 0.5)    // 50% chance for sleep when forced
            ]
            
            // Try to get a forced animation
            let random = Double.random(in: 0..<1)
            var cumulative = 0.0
            
            for (id, weight) in forcedWeights {
                cumulative += weight
                if random < cumulative,
                   let animation = availableAnimations.first(where: { $0.id == id }) {
                    Logger.log("CatAnimations", "Forcing \(id) animation")
                    return animation
                }
            }
        }
        
        // Normal weighted selection
        let random = Double.random(in: 0..<1)
        var cumulative = 0.0
        
        for (id, weight) in weights {
            cumulative += weight
            if random < cumulative,
               let animation = availableAnimations.first(where: { $0.id == id }) {
                Logger.log("CatAnimations", "Playing \(id) animation")
                return animation
            }
        }
        
        // Fallback to any available animation
        let fallback = availableAnimations.randomElement()
        if let fallback = fallback {
            Logger.log("CatAnimations", "Fallback animation: \(fallback.id)")
        }
        return fallback
    }
} 