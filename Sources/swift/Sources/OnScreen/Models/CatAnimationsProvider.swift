import Foundation
import Schwifty

class CatAnimationsProvider: AnimationsProvider {
    private let baseAnimationIds = ["front", "idle", "eat", "sleep"]
    
    override func randomAnimation() -> EntityAnimation? {
        guard let subject = subject else { return nil }
        
        // Filter animations to only include base animations
        let baseAnimations = subject.species.animations.filter { animation in
            baseAnimationIds.contains(animation.id)
        }
        
        return baseAnimations.randomElement()
    }
} 