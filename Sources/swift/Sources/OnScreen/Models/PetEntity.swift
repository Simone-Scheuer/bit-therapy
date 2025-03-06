import Combine
import Schwifty
import SwiftUI

class PetEntity: Entity {
    @Inject private var settings: AppConfig

    private var disposables = Set<AnyCancellable>()
    private var lastDirectionChangeTime: TimeInterval = 0
    private let minTimeBetweenDirectionChanges: TimeInterval = 4.0
    private let chanceToChangeDirection: Double = 0.08
    private let directionChangeCheckInterval: TimeInterval = 1.0
    private var directionChangeTimer: Timer?
    
    // Add individual size and speed properties
    private var individualSize: CGFloat
    private var individualSpeedMultiplier: CGFloat = 1.0

    public init(of species: Species, in world: World) {
        // Initialize with global settings
        self.individualSize = PetSize.defaultSize
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
        
        // Initialize behavior system
        install(RandomBehaviorAnimator())
        
        // Start direction change timer
        startDirectionChangeTimer()
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
            guard species.animations.contains(where: { $0.id == animation.id }) else {
                Logger.log(id, "Animation not supported: \(animation.id)")
                return
            }
        }
        
        super.set(state: state)
        
        // Post notification about state change
        NotificationCenter.default.post(name: .init("EntityStateChanged"), object: self)
        
        // Reset speed when changing to move state
        if case .move = state { 
            resetSpeed() 
        }
    }

    public func resetSpeed() {
        // Base speed calculation using individual multiplier
        let baseSpeed = PetEntity.speed(
            for: species,
            size: frame.width,
            settings: settings.speedMultiplier * individualSpeedMultiplier
        )
        
        // Add slight random variation (-10% to +10%)
        let randomVariation = CGFloat.random(in: 0.9...1.1)
        speed = baseSpeed * randomVariation
        
        // Occasionally (10% chance) give them a burst of speed
        if Double.random(in: 0...1) < 0.1 {
            applySpeedBurst()
        }
    }
    
    private func applySpeedBurst() {
        // Double the speed temporarily
        speed *= 2
        
        // Reset speed after a random duration (2.5-7.5 seconds)
        let duration = Double.random(in: 2.5...7.5)
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
        directionChangeTimer?.invalidate()
        directionChangeTimer = nil
        disposables.removeAll()
        super.kill()
    }

    private func startDirectionChangeTimer() {
        // Create a timer that fires every second to check for direction changes
        directionChangeTimer = Timer.scheduledTimer(withTimeInterval: directionChangeCheckInterval, repeats: true) { [weak self] _ in
            self?.checkForDirectionChange()
        }
        directionChangeTimer?.tolerance = 0.1 // Reduced tolerance for more precise timing
    }
    
    private func checkForDirectionChange() {
        guard case .move = state,
              capability(for: MouseChaser.self) == nil,  // Don't change direction if chasing mouse
              wallWalker?.isWallWalkingEnabled != true,  // Don't change direction if wall walking
              !isBeingDragged() else { return }  // Don't change direction if being dragged
        
        let currentTime = ProcessInfo.processInfo.systemUptime
        
        // Only allow direction change if minimum time has passed
        guard currentTime - lastDirectionChangeTime >= minTimeBetweenDirectionChanges else { return }
        
        // 8% chance to change direction per second
        if Double.random(in: 0...1) < chanceToChangeDirection {
            // Change direction
            direction = CGVector(dx: direction.dx * -1, dy: 0)
            lastDirectionChangeTime = currentTime
            
            // Small chance to trigger an animation when changing direction (10% chance)
            if Double.random(in: 0...1) < 0.1,
               let randomBehavior = capability(for: RandomBehaviorAnimator.self) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    randomBehavior.requestBehavior()
                }
            }
        }
    }
    
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
        
        // Give a chance to trigger an animation after resetting
        if let scheduler = capability(for: AnimationsScheduler.self) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                scheduler.animateNow()
            }
        }
    }
    
    func playAnimation(_ animationId: String, loops: Int = 5) {
        if let animation = species.animations.first(where: { $0.id == animationId }) {
            // Use the animation's required loops if specified, otherwise use the provided loops
            let loopCount = animation.requiredLoops ?? loops
            set(state: .action(action: animation, loops: loopCount))
        }
    }

    // Add methods to get/set individual properties
    public func setIndividualSize(_ size: CGFloat) {
        individualSize = size
        // Update frame size
        frame.size = CGSize(square: individualSize * species.scale)
    }
    
    public func getIndividualSize() -> CGFloat {
        return individualSize
    }
    
    public func setIndividualSpeedMultiplier(_ multiplier: CGFloat) {
        individualSpeedMultiplier = multiplier
        resetSpeed()
    }
    
    public func getIndividualSpeedMultiplier() -> CGFloat {
        return individualSpeedMultiplier
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
    // Remove duplicate declarations since they already exist in the main class
}
