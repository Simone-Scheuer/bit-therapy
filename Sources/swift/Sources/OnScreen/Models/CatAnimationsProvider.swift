import Foundation
import Schwifty

class CatAnimationsProvider: AnimationsProvider {
    @Inject private var settings: AppConfig
    
    private let baseAnimationIds = ["front", "idle", "eat", "sleep"]
    
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
        
        // Only block animations in these specific cases
        if case .drag = subject.state { return nil }
        if subject.wallWalker?.isWallWalkingEnabled == true { return nil }
        if subject.capability(for: MouseChaser.self) != nil { return nil }
        
        // If we're in an action state, only allow a new animation if it's different
        if case .action(let currentAction, _) = subject.state {
            return availableAnimations
                .filter { $0.id != currentAction.id }
                .randomElement()
        }
        
        // Weight-based selection system
        let weights: [(String, Double)] = [
            ("eat", 0.3),    // 30% chance
            ("sleep", 0.3),  // 30% chance
            ("idle", 0.25),  // 25% chance
            ("front", 0.15)  // 15% chance
        ]
        
        // Weighted random selection
        let random = Double.random(in: 0..<1)
        var cumulative = 0.0
        
        for (id, weight) in weights {
            cumulative += weight
            if random < cumulative,
               let animation = availableAnimations.first(where: { $0.id == id }) {
                Logger.log("CatAnimations", "Selected \(id) animation")
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