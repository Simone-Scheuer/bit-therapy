import Combine
import Schwifty
import SwiftUI

class PetEntity: Entity {
    @Inject private var settings: AppConfig

    private var disposables = Set<AnyCancellable>()

    public init(of species: Species, in world: World) {
        super.init(
            species: species,
            id: PetEntity.id(for: species),
            frame: PetEntity.initialFrame(for: species),
            in: world
        )
        resetSpeed()
        setInitialPosition()
        setInitialDirection()
        bindGravity()
        bindBounceOffPets()
    }

    private func bindBounceOffPets() {
        settings.$bounceOffPetsEnabled
            .sink { [weak self] in self?.setBounceOffPets(enabled: $0) }
            .store(in: &disposables)
    }

    private func setBounceOffPets(enabled: Bool) {
        guard let bounce = capability(for: BounceOnLateralCollisions.self) else { return }
        if enabled {
            bounce.customCollisionsFilter = { _ in true }
        } else {
            bounce.customCollisionsFilter = nil
        }
    }

    private func bindGravity() {
        settings.$gravityEnabled
            .sink { [weak self] in self?.setGravity(enabled: $0) }
            .store(in: &disposables)
    }

    override open func set(state: EntityState) {
        // If it's an action state (animation), validate it first
        if case .action(let animation, _) = state {
            // Check if the species supports this animation
            guard species.animations.contains(where: { $0.id == animation.id }) else { return }
        }
        
        super.set(state: state)
        
        // Reset speed when changing state (unless it's an animation)
        if case .move = state { resetSpeed() }
    }

    public func resetSpeed() {
        // Base speed calculation
        let baseSpeed = PetEntity.speed(
            for: species,
            size: frame.width,
            settings: settings.speedMultiplier
        )
        
        // Add slight random variation (-10% to +10%)
        let randomVariation = CGFloat.random(in: 0.9...1.1)
        speed = baseSpeed * randomVariation
        
        // Occasionally (5% chance) give them a burst of speed
        if Double.random(in: 0...1) < 0.05 {
            applySpeedBurst()
        }
    }
    
    private func applySpeedBurst() {
        // Double the speed temporarily
        speed *= 2
        
        // Reset speed after a random duration (1-3 seconds)
        let duration = Double.random(in: 1...3)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.resetSpeed()
        }
    }

    func setInitialPosition() {
        let randomX = worldBounds.width * .random(in: 0.05 ... 0.95)
        let randomY: CGFloat

        if capability(for: WallCrawler.self) != nil {
            randomY = worldBounds.height - frame.height
        } else {
            randomY = 60
        }
        frame.origin = CGPoint(x: randomX, y: randomY)
    }

    func setInitialDirection() {
        direction = .init(dx: 1, dy: 0)
    }

    override open func kill() {
        disposables.removeAll()
        super.kill()
    }
}

// MARK: - Incremental Id

extension PetEntity {
    static func id(for species: Species) -> String {
        nextNumber += 1
        return "\(species.id)-\(nextNumber)"
    }

    private static var nextNumber = 0
}

// MARK: - Speed

extension PetEntity {
    static let baseSpeed: CGFloat = 30

    static func initialFrame(for species: Species) -> CGRect {
        @Inject var appConfig: AppConfig
        return CGRect(square: appConfig.petSize * species.scale)
    }

    static func speed(for species: Species, size: CGFloat, settings: CGFloat) -> CGFloat {
        species.speed * speedMultiplier(for: size) * settings
    }

    static func speedMultiplier(for size: CGFloat) -> CGFloat {
        let sizeRatio = size / PetSize.defaultSize
        return baseSpeed * sizeRatio
    }
}

// MARK: - Animations

extension PetEntity {
    func availableAnimations() -> [PetAnimation] {
        // Get standard animations based on what the species supports
        let standardAnimations = PetAnimation.all.filter { animation in
            // Check if the animation exists in the species animations
            animation.id != "raincloud" && species.animations.contains { $0.id == animation.id }
        }
        
        // Always add the rain cloud as it's a special effect that works on all pets
        return standardAnimations + [PetAnimation.rainCloud]
    }
    
    func resetState() {
        // Return to idle or walking state
        set(state: .move)
    }
    
    func playAnimation(_ animationId: String, loops: Int = 5) {
        if let animation = species.animations.first(where: { $0.id == animationId }) {
            // Use the animation's required loops if specified, otherwise use the provided loops
            let loopCount = animation.requiredLoops ?? loops
            set(state: .action(action: animation, loops: loopCount))
        }
    }
}
