import Schwifty
import SwiftUI

class WallWalker: Capability {
    @Inject private var appConfig: AppConfig
    
    enum Wall {
        case floor
        case leftWall
        case rightWall
        case ceiling
        
        var gravityDirection: CGVector {
            switch self {
            case .floor: return CGVector(dx: 0, dy: -4)  // Down (negative Y is down)
            case .leftWall: return CGVector(dx: -4, dy: 0)  // Left
            case .rightWall: return CGVector(dx: 4, dy: 0)  // Right
            case .ceiling: return CGVector(dx: 0, dy: 4)  // Up
            }
        }
        
        var spriteRotation: CGFloat {
            switch self {
            case .floor: return 0  // No rotation for floor
            case .leftWall: return -CGFloat.pi / 2  // 90° counterclockwise
            case .rightWall: return CGFloat.pi / 2   // 90° clockwise
            case .ceiling: return CGFloat.pi  // 180° for ceiling
            }
        }
        
        var shouldFlipSprite: Bool {
            switch self {
            case .floor: return true  // Flip on floor
            case .ceiling: return true  // Flip on ceiling
            case .leftWall: return true  // Flip on left wall
            case .rightWall: return true  // Flip on right wall (reverted back)
            }
        }
    }
    
    private(set) var isWallWalkingEnabled = false
    private var currentWall: Wall = .floor
    private let contactTolerance: CGFloat = 5.0  // Allow small gaps during movement
    private var lastContactTime: TimeInterval = 0
    private let contactMemory: TimeInterval = 0.1  // Remember contact for 100ms
    
    override func install(on subject: Entity) {
        super.install(on: subject)
        isWallWalkingEnabled = false
        
        // Ensure we have rotation capability
        if subject.rotation == nil {
            subject.install(Rotating())
        }
    }
    
    override func doUpdate(with collisions: Collisions, after time: TimeInterval) {
        guard let subject = subject, isWallWalkingEnabled else { return }
        
        // Skip if being dragged
        if subject.state == .drag { return }
        
        // Update contact memory
        lastContactTime += time
        
        // Handle wall collisions and movement
        if let wallContact = detectWallContact(from: collisions) {
            lastContactTime = 0  // Reset contact timer
            handleWallContact(at: wallContact)
        } else if lastContactTime > contactMemory {
            // Only start falling if we've lost contact for long enough
            currentWall = determineNearestWall()
            startFalling()
        }
        
        // Apply wall-specific gravity when falling
        if subject.state == .freeFall {
            applyWallGravity()
        }
        
        // Update sprite orientation
        updateSpriteOrientation()
    }
    
    private func detectWallContact(from collisions: Collisions) -> CGFloat? {
        guard let subject = subject else { return nil }
        let frame = subject.frame
        
        // Filter for static collisions
        let wallCollisions = collisions
            .filter { $0.other?.isStatic == true }
            .filter { !$0.isEphemeral }
        
        // Check for collisions based on current wall
        switch currentWall {
        case .floor:
            return wallCollisions
                .filter { abs($0.intersection.minY - frame.minY) < contactTolerance }
                .map { $0.intersection.minY }
                .min()
        case .ceiling:
            return wallCollisions
                .filter { abs($0.intersection.maxY - frame.maxY) < contactTolerance }
                .map { $0.intersection.maxY }
                .max()
        case .leftWall:
            return wallCollisions
                .filter { abs($0.intersection.minX - frame.minX) < contactTolerance }
                .map { $0.intersection.minX }
                .min()
        case .rightWall:
            return wallCollisions
                .filter { abs($0.intersection.maxX - frame.maxX) < contactTolerance }
                .map { $0.intersection.maxX }
                .max()
        }
    }
    
    private func handleWallContact(at contactPoint: CGFloat) {
        guard let subject = subject else { return }
        
        // If we were falling, transition to walking
        if subject.state == .freeFall {
            subject.set(state: .move)
            subject.movement?.isEnabled = true
            
            // Set initial walking direction based on wall
            switch currentWall {
            case .floor:
                subject.direction = .init(dx: 1, dy: 0)
            case .ceiling:
                subject.direction = .init(dx: 1, dy: 0)  // Start moving right on ceiling
            case .leftWall:
                subject.direction = .init(dx: 0, dy: -1)  // Start moving down on left wall
            case .rightWall:
                subject.direction = .init(dx: 0, dy: 1)  // Start moving up on right wall
            }
        }
        
        // Snap to wall
        var newPosition = subject.frame.origin
        switch currentWall {
        case .floor:
            newPosition.y = contactPoint
        case .ceiling:
            newPosition.y = contactPoint - subject.frame.height
        case .leftWall:
            newPosition.x = contactPoint
        case .rightWall:
            newPosition.x = contactPoint - subject.frame.width
        }
        subject.frame.origin = newPosition
    }
    
    private func startFalling() {
        guard let subject = subject else { return }
        
        // Start falling
        subject.set(state: .freeFall)
        subject.direction = currentWall.gravityDirection
        subject.speed = 8
    }
    
    private func applyWallGravity() {
        guard let subject = subject else { return }
        subject.direction = currentWall.gravityDirection
    }
    
    private func updateSpriteOrientation() {
        guard let subject = subject, let rotating = subject.rotation else { return }
        
        // Set rotation angle
        rotating.zAngle = currentWall.spriteRotation
        
        // Handle sprite flipping based on wall and state
        if subject.state == .freeFall {
            // When falling, orient feet towards target wall
            switch currentWall {
            case .floor:
                rotating.zAngle = 0
                rotating.isFlippedVertically = true  // Flip when falling to floor
            case .ceiling:
                rotating.zAngle = CGFloat.pi
                rotating.isFlippedVertically = true  // Flip when falling to ceiling
            case .leftWall:
                rotating.zAngle = -CGFloat.pi / 2
                rotating.isFlippedVertically = true
            case .rightWall:
                rotating.zAngle = CGFloat.pi / 2
                rotating.isFlippedVertically = true  // Reverted back
            }
        } else {
            // Normal walking orientation
            rotating.isFlippedVertically = currentWall.shouldFlipSprite
        }
        
        // Determine horizontal flip based on movement direction and current wall
        switch currentWall {
        case .floor:
            rotating.isFlippedHorizontally = subject.direction.dx < 0
        case .ceiling:
            rotating.isFlippedHorizontally = subject.direction.dx > 0  // Reversed for ceiling
        case .leftWall:
            rotating.isFlippedHorizontally = subject.direction.dy > 0  // Flip when moving up on left wall
        case .rightWall:
            rotating.isFlippedHorizontally = subject.direction.dy < 0  // Reverted back
        }
    }
    
    func toggleWallWalking() {
        isWallWalkingEnabled = !isWallWalkingEnabled
        
        // Kill any mouse chasing if it's enabled
        subject?.capability(for: MouseChaser.self)?.kill()
        
        if isWallWalkingEnabled {
            enableWallWalking()
        } else {
            resetToFloor()
        }
    }
    
    private func enableWallWalking() {
        guard let subject = subject else { return }
        
        // Start with current wall based on position
        currentWall = determineNearestWall()
        
        // Start falling towards current wall
        subject.movement?.isEnabled = true
        subject.set(state: .freeFall)
        subject.direction = currentWall.gravityDirection
        subject.speed = 8
        
        // Initial sprite orientation
        updateSpriteOrientation()
    }
    
    private func resetToFloor() {
        guard let subject = subject else { return }
        
        // Reset to normal gravity and movement
        currentWall = .floor
        subject.movement?.isEnabled = true
        subject.setGravity(enabled: true)
        
        // Reset sprite orientation
        if let rotating = subject.rotation {
            rotating.zAngle = 0
            rotating.isFlippedVertically = false
            rotating.isFlippedHorizontally = subject.direction.dx < 0
        }
        
        // Start falling to floor
        subject.set(state: .freeFall)
        subject.direction = Wall.floor.gravityDirection
    }
    
    private func determineNearestWall() -> Wall {
        guard let subject = subject, let bounds = subject.world?.bounds else { return .floor }
        
        let position = subject.frame.origin
        let size = subject.frame.size
        let center = CGPoint(x: position.x + size.width/2, y: position.y + size.height/2)
        
        // Calculate distances to each wall
        let distanceToLeft = center.x
        let distanceToRight = bounds.width - center.x
        let distanceToTop = bounds.height - center.y
        let distanceToBottom = center.y
        
        // Find the nearest wall
        let distances = [
            (wall: Wall.leftWall, distance: distanceToLeft),
            (wall: Wall.rightWall, distance: distanceToRight),
            (wall: Wall.ceiling, distance: distanceToTop),
            (wall: Wall.floor, distance: distanceToBottom)
        ]
        
        return distances.min(by: { $0.distance < $1.distance })?.wall ?? .floor
    }
}

extension Entity {
    var wallWalker: WallWalker? {
        capability(for: WallWalker.self)
    }
} 


