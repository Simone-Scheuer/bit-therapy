import Foundation

extension ScreenEnvironment {
    func scheduleRainyCloud() {
        scheduleRandomly(withinHours: 0 ..< 5) { [weak self] in
            guard let self else { return }
            guard self.settings.randomEvents else { return }
            guard let victim = self.randomPet() else { return }
            self.rainyCloudUseCase.start(target: victim, world: self)
        }
    }
}

protocol RainyCloudUseCase {
    func start(target: Entity, world: World)
}

class RainyCloudUseCaseImpl: RainyCloudUseCase {
    private var currentCloud: Entity?

    func start(target: Entity, world: World) {
        // If there's already a cloud, remove it first
        if let existingCloud = currentCloud {
            existingCloud.kill()
            world.children.remove(existingCloud)
        }

        let cloud = buildCloud(at: target.frame.origin, in: world)
        currentCloud = cloud
        setupSeeker(for: cloud, to: target)
        scheduleCleanUp(cloud: cloud, world: world)
    }

    private func buildCloud(at origin: CGPoint, in world: World) -> Entity {
        let cloud = PetEntity(of: .cloud, in: world)
        cloud.frame.size = CGSize(
            width: cloud.frame.size.width * 2,
            height: cloud.frame.size.height * 2
        )
        cloud.frame.origin = origin
        cloud.isEphemeral = true
        world.children.append(cloud)
        return cloud
    }

    private func setupSeeker(for cloud: Entity, to target: Entity) {
        let yOffset = cloud.frame.height - target.frame.height
        let seeker = Seeker()
        cloud.install(seeker)
        seeker.follow(
            target,
            to: .above,
            offset: CGSize(width: 0, height: yOffset),
            autoAdjustSpeed: true
        ) { _ in }
    }

    private func scheduleCleanUp(cloud: Entity, world: World) {
        // For manual triggering, use a fixed duration of 30 seconds
        let duration: TimeInterval = 30
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak world, weak cloud] in
            guard let cloud = cloud else { return }
            cloud.kill()
            world?.children.remove(cloud)
            if let self = self, self.currentCloud === cloud {
                self.currentCloud = nil
            }
        }
    }
}

private extension Species {
    static let cloud = Species(
        id: "fantozzi",
        capabilities: [
            "AnimatedSprite",
            "AnimationsProvider",
            "LinearMovement",
            "PetsSpritesProvider"
        ],
        dragPath: "front",
        movementPath: "front",
        speed: 2,
        zIndex: 200
    )
}
