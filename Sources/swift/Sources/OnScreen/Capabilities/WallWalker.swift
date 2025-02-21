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
    private(set) var canTraverseCorners = true  // New property for corner traversal toggle
    private var currentWall: Wall = .floor
    private let contactTolerance: CGFloat = 5.0  // Allow small gaps during movement
    private var lastContactTime: TimeInterval = 0
    private let contactMemory: TimeInterval = 0.1  // Remember contact for 100ms
    private let cornerDetectionDistance: CGFloat = 20.0  // Distance to detect corners
    private var isTransitioningCorner = false
    private var transitionProgress: CGFloat = 0.0
    private var transitionStartPosition: CGPoint = .zero
    private var transitionEndPosition: CGPoint = .zero
    private var transitionStartWall: Wall = .floor
    private var transitionTargetWall: Wall = .floor
    
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
        
        if isTransitioningCorner {
            updateCornerTransition(after: time)
            return
        }
        
        // Update contact memory
        lastContactTime += time
        
        // Check for corner transitions first if enabled
        if canTraverseCorners && subject.state == .move, let corner = detectCorner(from: collisions) {
            startCornerTransition(at: corner)
            return
        } else if !canTraverseCorners && subject.state == .move {
            // Handle bouncing at corners when traversal is disabled
            handleBounceAtCorners()
        }
        
        // Existing wall collision and movement logic
        if let wallContact = detectWallContact(from: collisions) {
            lastContactTime = 0
            handleWallContact(at: wallContact)
        } else if lastContactTime > contactMemory {
            currentWall = determineNearestWall()
            startFalling()
        }
        
        if subject.state == .freeFall {
            applyWallGravity()
        }
        
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
        subject.speed = 16  // Doubled from 8 to 16 for faster falling
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
            switch currentWall {
            case .floor, .ceiling:
                rotating.isFlippedVertically = currentWall.shouldFlipSprite
            case .leftWall:
                rotating.isFlippedVertically = !(subject.direction.dy > 0)  // Invert the vertical flip on left wall
            case .rightWall:
                rotating.isFlippedVertically = subject.direction.dy > 0  // Opposite of left wall
            }
        }
        
        // Determine horizontal flip based on movement direction and current wall
        switch currentWall {
        case .floor:
            rotating.isFlippedHorizontally = subject.direction.dx < 0
        case .ceiling:
            rotating.isFlippedHorizontally = subject.direction.dx > 0  // Reversed for ceiling
        case .leftWall:
            rotating.isFlippedHorizontally = false  // Never flip horizontally on left wall
        case .rightWall:
            rotating.isFlippedHorizontally = false  // Never flip horizontally on right wall
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
    
    func toggleCornerTraversal() {
        guard isWallWalkingEnabled else { return }
        canTraverseCorners = !canTraverseCorners
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
        
        // Re-enable animation scheduler and ensure it's properly initialized
        if let scheduler = subject.capability(for: AnimationsScheduler.self) {
            scheduler.isEnabled = true
            scheduler.animateNow() // Trigger an immediate animation to restore behavior
        }
        
        // Reset state and movement
        subject.set(state: .move)
        // Pick a random direction from an array
        let randomDirection = [-1.0, 1.0].randomElement() ?? 1.0
        subject.direction = CGVector(dx: randomDirection, dy: 0) // Random initial direction
        
        // Reset speed based on entity type
        if let petEntity = subject as? PetEntity {
            petEntity.resetSpeed()
        } else {
            // Default speed for non-pet entities
            subject.speed = 30
        }
        
        // Reset sprite orientation
        if let rotating = subject.rotation {
            rotating.zAngle = 0
            rotating.isFlippedVertically = false
            rotating.isFlippedHorizontally = subject.direction.dx < 0
        }
        
        // Re-enable gravity
        subject.setGravity(enabled: appConfig.gravityEnabled)
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
    
    private func detectCorner(from collisions: Collisions) -> (position: CGPoint, nextWall: Wall)? {
        guard let subject = subject, let bounds = subject.world?.bounds else { return nil }
        let frame = subject.frame
        
        // Define corner positions based on current wall and movement direction
        switch currentWall {
        case .floor:
            if subject.direction.dx > 0 && frame.maxX >= bounds.width - cornerDetectionDistance {
                // Ensure we're actually at the corner and not just near the edge
                let cornerPosition = CGPoint(x: bounds.width - frame.width, y: frame.minY)
                return (cornerPosition, .rightWall)
            }
            if subject.direction.dx < 0 && frame.minX <= cornerDetectionDistance {
                let cornerPosition = CGPoint(x: 0, y: frame.minY)
                return (cornerPosition, .leftWall)
            }
            
        case .ceiling:
            if subject.direction.dx > 0 && frame.maxX >= bounds.width - cornerDetectionDistance {
                let cornerPosition = CGPoint(x: bounds.width - frame.width, y: bounds.height - frame.height)
                return (cornerPosition, .rightWall)
            }
            if subject.direction.dx < 0 && frame.minX <= cornerDetectionDistance {
                let cornerPosition = CGPoint(x: 0, y: bounds.height - frame.height)
                return (cornerPosition, .leftWall)
            }
            
        case .leftWall:
            if subject.direction.dy > 0 && frame.maxY >= bounds.height - cornerDetectionDistance {
                let cornerPosition = CGPoint(x: frame.minX, y: bounds.height - frame.height)
                return (cornerPosition, .ceiling)
            }
            if subject.direction.dy < 0 && frame.minY <= cornerDetectionDistance {
                let cornerPosition = CGPoint(x: frame.minX, y: 0)
                return (cornerPosition, .floor)
            }
            
        case .rightWall:
            if subject.direction.dy > 0 && frame.maxY >= bounds.height - cornerDetectionDistance {
                let cornerPosition = CGPoint(x: bounds.width - frame.width, y: bounds.height - frame.height)
                return (cornerPosition, .ceiling)
            }
            if subject.direction.dy < 0 && frame.minY <= cornerDetectionDistance {
                let cornerPosition = CGPoint(x: bounds.width - frame.width, y: 0)
                return (cornerPosition, .floor)
            }
        }
        
        return nil
    }
    
    private func startCornerTransition(at corner: (position: CGPoint, nextWall: Wall)) {
        guard let subject = subject else { return }
        
        isTransitioningCorner = true
        transitionProgress = 0.0
        transitionStartPosition = subject.frame.origin
        transitionStartWall = currentWall
        transitionTargetWall = corner.nextWall
        
        // Calculate end position based on target wall
        var endPosition = corner.position
        switch corner.nextWall {
        case .floor:
            endPosition.y = 0
        case .ceiling:
            endPosition.y = (subject.world?.bounds.height ?? 0) - subject.frame.height
        case .leftWall:
            endPosition.x = 0
        case .rightWall:
            endPosition.x = (subject.world?.bounds.width ?? 0) - subject.frame.width
        }
        
        // Ensure the end position is within bounds
        if let bounds = subject.world?.bounds {
            endPosition.x = max(0, min(bounds.width - subject.frame.width, endPosition.x))
            endPosition.y = max(0, min(bounds.height - subject.frame.height, endPosition.y))
        }
        
        transitionEndPosition = endPosition
    }
    
    private func updateCornerTransition(after time: TimeInterval) {
        guard let subject = subject else { return }
        
        // Progress the transition
        transitionProgress += CGFloat(time * 5.0)  // Adjust speed as needed
        
        if transitionProgress >= 1.0 {
            // Finish transition
            isTransitioningCorner = false
            currentWall = transitionTargetWall
            subject.frame.origin = transitionEndPosition
            
            // Set new movement direction
            switch transitionTargetWall {
            case .floor, .ceiling:
                subject.direction = CGVector(dx: transitionStartWall == .leftWall ? 1 : -1, dy: 0)
            case .leftWall, .rightWall:
                subject.direction = CGVector(dx: 0, dy: transitionStartWall == .floor ? 1 : -1)
            }
        } else {
            // Interpolate position
            let t = CGFloat(sin(Double.pi * Double(transitionProgress) / 2))  // Smooth easing
            let newX = transitionStartPosition.x + (transitionEndPosition.x - transitionStartPosition.x) * t
            let newY = transitionStartPosition.y + (transitionEndPosition.y - transitionStartPosition.y) * t
            subject.frame.origin = CGPoint(x: newX, y: newY)
            
            // Interpolate rotation
            if let rotating = subject.rotation {
                let startAngle = transitionStartWall.spriteRotation
                let endAngle = transitionTargetWall.spriteRotation
                rotating.zAngle = startAngle + (endAngle - startAngle) * t
            }
        }
        
        // Update sprite orientation during transition
        updateSpriteOrientation()
    }
    
    private func handleBounceAtCorners() {
        guard let subject = subject, let bounds = subject.world?.bounds else { return }
        let frame = subject.frame
        
        switch currentWall {
        case .floor, .ceiling:
            if (subject.direction.dx > 0 && frame.maxX >= bounds.width - cornerDetectionDistance) ||
               (subject.direction.dx < 0 && frame.minX <= cornerDetectionDistance) {
                // Reverse horizontal direction
                subject.direction.dx *= -1
            }
            
        case .leftWall, .rightWall:
            if (subject.direction.dy > 0 && frame.maxY >= bounds.height - cornerDetectionDistance) ||
               (subject.direction.dy < 0 && frame.minY <= cornerDetectionDistance) {
                // Reverse vertical direction
                subject.direction.dy *= -1
            }
        }
    }

    // Add a method to get the current corner traversal state
    var isCornerTraversalEnabled: Bool {
        canTraverseCorners
    }

    // Add a method to get a descriptive title for the menu
    var cornerTraversalMenuTitle: String {
        isCornerTraversalEnabled ? "Disable Corner Traversal" : "Enable Corner Traversal"
    }
}

extension Entity {
    var wallWalker: WallWalker? {
        capability(for: WallWalker.self)
    }
} 


