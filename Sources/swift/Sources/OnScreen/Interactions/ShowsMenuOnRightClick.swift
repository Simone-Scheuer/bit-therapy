import Schwifty
import SwiftUI
#if os(macOS)
import AppKit
#endif

protocol RightClickable: Capability {
    func onRightClick(from window: SomeWindow?, at point: CGPoint)
}

extension RightClickable {
    func onRightClick(from window: SomeWindow?, at point: CGPoint) {
        // Default empty implementation
    }
}

class BaseRightClickable: Capability, RightClickable {
    override func install(on subject: Entity) {
        super.install(on: subject)
        isEnabled = !subject.isEphemeral
    }
    
    func onRightClick(from window: SomeWindow?, at point: CGPoint) {
        // Base implementation
    }
}

extension Entity {
    var rightClick: RightClickable? { capability(for: BaseRightClickable.self) }
}

#if os(macOS)
    class ShowsMenuOnRightClick: BaseRightClickable {
        @Inject private var onScreen: OnScreenCoordinator
        @Inject private var rainyCloudUseCase: RainyCloudUseCase
        @Inject private var speciesNames: SpeciesNamesRepository
        private weak var lastWindow: SomeWindow?
        private var isMenuOpen = false
        private var previousState: EntityState?
        private var previousPosition: CGPoint?
        private var previousSpeed: CGFloat?

        override func install(on subject: Entity) {
            super.install(on: subject)
            isEnabled = !subject.isEphemeral
        }

        override func onRightClick(from window: SomeWindow?, at point: CGPoint) {
            lastWindow = window
            isMenuOpen = true
            
            // Store current state and position
            if let petEntity = subject as? PetEntity {
                previousState = petEntity.state
                previousPosition = petEntity.frame.origin
                previousSpeed = petEntity.speed
                
                // Lock in place with front animation
                petEntity.speed = 0
                if let movement = petEntity.movement {
                    movement.isEnabled = false
                }
                petEntity.setGravity(enabled: false)
                
                // Show front animation with high loop count to persist while menu is open
                if let frontAnimation = petEntity.species.animations.first(where: { $0.id == "front" }) {
                    petEntity.set(state: .action(action: frontAnimation, loops: 100))
                }
                
                // Disable animation scheduler to prevent random animations
                petEntity.capability(for: AnimationsScheduler.self)?.isEnabled = false
            }
            
            let menu = petMenu()
            menu.delegate = menuDelegate
            
            // Show the menu at the clicked location
            if let nsWindow = window as? NSWindow {
                let event = NSEvent.mouseEvent(
                    with: .rightMouseUp,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: nsWindow.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                )
                if let event = event {
                    NSMenu.popUpContextMenu(menu, with: event, for: nsWindow.contentView ?? NSView())
                }
            }
        }

        // MARK: - Menu Creation
        private lazy var menuDelegate: MenuDelegate = {
            let delegate = MenuDelegate()
            delegate.onMenuClose = { [weak self] in
                guard let self = self else { return }
                self.isMenuOpen = false
                
                // Restore previous state and position
                if let petEntity = self.subject as? PetEntity {
                    if let position = self.previousPosition {
                        petEntity.frame.origin = position
                    }
                    if let speed = self.previousSpeed {
                        petEntity.speed = speed
                    }
                    if let movement = petEntity.movement {
                        movement.isEnabled = true
                    }
                    petEntity.setGravity(enabled: true)
                    
                    // Re-enable animation scheduler only if not wall walking
                    if petEntity.wallWalker?.isWallWalkingEnabled != true {
                        if let scheduler = petEntity.capability(for: AnimationsScheduler.self) {
                            scheduler.isEnabled = true
                            // Schedule next animation immediately to restore behavior
                            scheduler.animateNow()
                        }
                    }
                    
                    // Only restore previous state if it wasn't an action
                    if case .move = self.previousState {
                        petEntity.set(state: self.previousState ?? .move)
                        // Set random direction when returning to move state
                        let randomDirection = [-1.0, 1.0].randomElement() ?? 1.0
                        petEntity.direction = CGVector(dx: randomDirection, dy: 0)
                    } else {
                        petEntity.set(state: .move)
                        let randomDirection = [-1.0, 1.0].randomElement() ?? 1.0
                        petEntity.direction = CGVector(dx: randomDirection, dy: 0)
                    }
                }
                
                // Clear stored states
                self.previousState = nil
                self.previousPosition = nil
                self.previousSpeed = nil
            }
            delegate.rainyCloudUseCase = rainyCloudUseCase
            return delegate
        }()

        private func petMenu() -> NSMenu {
            let menu = NSMenu(title: "PetMenu")
            menu.delegate = menuDelegate
            
            // Add pet name as a header (disabled item)
            if let petEntity = subject as? PetEntity {
                // Set menu appearance based on cat type
                #if os(macOS)
                // Make menu transparent
                menu.appearance = NSAppearance(named: .aqua)
                
                // Define colors based on cat type
                let (backgroundColor, nameColor): (NSColor, NSColor)
                switch petEntity.species.id {
                case "cat_strawberry":
                    backgroundColor = NSColor(red: 1.0, green: 0.8, blue: 0.9, alpha: 0.15)  // More transparent pink
                    nameColor = NSColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 0.9)
                case "cat_blue":
                    backgroundColor = NSColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 0.15)  // More transparent blue
                    nameColor = NSColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 0.9)
                default:
                    backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.15)
                    nameColor = NSColor.secondaryLabelColor
                }
                
                // Apply background color to menu
                menu.items.forEach { item in
                    item.view?.wantsLayer = true
                    item.view?.layer?.backgroundColor = backgroundColor.cgColor
                }
                #endif
                
                let petName = speciesNames.currentName(forSpecies: petEntity.species.id)
                let nameItem = NSMenuItem(title: petName, action: nil, keyEquivalent: "")
                nameItem.isEnabled = false
                nameItem.attributedTitle = NSAttributedString(
                    string: petName,
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                        .foregroundColor: nameColor
                    ]
                )
                menu.addItem(nameItem)
                menu.addItem(.separator())
                
                // Add animations submenu with matching style
                let animationsMenu = NSMenu()
                animationsMenu.delegate = menuDelegate
                #if os(macOS)
                animationsMenu.appearance = menu.appearance
                // Apply same transparency to submenu
                animationsMenu.items.forEach { item in
                    item.view?.wantsLayer = true
                    item.view?.layer?.backgroundColor = backgroundColor.cgColor
                }
                #endif
                
                let animationsItem = NSMenuItem(title: "Animations", action: nil, keyEquivalent: "")
                menu.addItem(animationsItem)
                menu.setSubmenu(animationsMenu, for: animationsItem)
                
                // Disable animations menu if wall walking is enabled
                if petEntity.wallWalker?.isWallWalkingEnabled == true {
                    animationsItem.isEnabled = false
                    animationsMenu.items.forEach { $0.isEnabled = false }
                } else {
                    // Add available animations only if not wall walking
                    for animation in petEntity.availableAnimations() {
                        let item = NSMenuItem(
                            title: animation.displayName,
                            action: #selector(MenuDelegate.triggerAnimation(_:)),
                            keyEquivalent: ""
                        )
                        item.target = menuDelegate
                        item.representedObject = (animation.id, petEntity)
                        animationsMenu.addItem(item)
                    }
                }
                
                // Add mouse following toggle for this specific pet
                menu.addItem(.separator())
                menu.addItem(followMouseItem(for: petEntity))
                
                // Add wall walking toggle
                menu.addItem(wallWalkingItem(for: petEntity))
            }
            
            // Add general menu items
            menu.addItem(.separator())
            menu.addItem(showHomeItem())
            menu.addItem(hideAllPetsItem())
            
            return menu
        }

        private func item(title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(
                title: "menu.\(title)".localized(),
                action: action,
                keyEquivalent: ""
            )
            item.target = menuDelegate
            return item
        }

        private func showHomeItem() -> NSMenuItem {
            item(title: "home", action: #selector(MenuDelegate.showHome))
        }

        private func hideAllPetsItem() -> NSMenuItem {
            let item = item(title: "hideAllPet", action: #selector(MenuDelegate.hideAllPets))
            menuDelegate.onScreenCoordinator = onScreen
            return item
        }

        private func followMouseItem(for petEntity: PetEntity) -> NSMenuItem {
            let isFollowingMouse = petEntity.capability(for: MouseChaser.self) != nil
            let title = isFollowingMouse ? "Stop Following Mouse" : "Follow Mouse"
            let item = NSMenuItem(
                title: title,
                action: #selector(MenuDelegate.toggleFollowMouse(_:)),
                keyEquivalent: ""
            )
            item.target = menuDelegate
            item.representedObject = ("", petEntity)
            return item
        }

        private func wallWalkingItem(for petEntity: PetEntity) -> NSMenuItem {
            // Create wall walker capability if it doesn't exist
            if petEntity.wallWalker == nil {
                petEntity.install(WallWalker())
            }
            
            let isWallWalkingEnabled = petEntity.wallWalker?.isWallWalkingEnabled ?? false
            let title = isWallWalkingEnabled ? "Disable Wall Walking" : "Enable Wall Walking"
            let item = NSMenuItem(
                title: title,
                action: #selector(MenuDelegate.toggleWallWalking(_:)),
                keyEquivalent: ""
            )
            item.target = menuDelegate
            item.representedObject = ("", petEntity)
            
            // If wall walking is enabled, add the corner traversal toggle as a submenu
            if isWallWalkingEnabled {
                let submenu = NSMenu()
                let cornerItem = NSMenuItem(
                    title: petEntity.wallWalker?.cornerTraversalMenuTitle ?? "Toggle Corner Traversal",
                    action: #selector(MenuDelegate.toggleCornerTraversal(_:)),
                    keyEquivalent: ""
                )
                cornerItem.target = menuDelegate
                cornerItem.representedObject = ("", petEntity)
                submenu.addItem(cornerItem)
                item.submenu = submenu
            }
            
            return item
        }
    }

    // MARK: - Menu Delegate
    private class MenuDelegate: NSObject, NSMenuDelegate {
        var onMenuClose: (() -> Void)?
        var onScreenCoordinator: OnScreenCoordinator?
        var rainyCloudUseCase: RainyCloudUseCase?
        private var isSubMenuOpen = false
        
        func menuWillOpen(_ menu: NSMenu) {
            // Keep the front animation going when opening submenus
            isSubMenuOpen = true
        }
        
        func menuDidClose(_ menu: NSMenu) {
            // Only trigger the close handler if this is the main menu closing
            // and no submenu is open
            if !isSubMenuOpen {
                onMenuClose?()
            }
            isSubMenuOpen = false
        }
        
        @objc func showHome() {
            MainScene.show()
        }
        
        @objc func hideAllPets() {
            onScreenCoordinator?.hide()
        }
        
        @objc func toggleFollowMouse(_ sender: NSMenuItem) {
            guard let (_, petEntity) = sender.representedObject as? (String, PetEntity) else { return }
            
            // Disable wall walking if it's enabled
            if let wallWalker = petEntity.wallWalker, wallWalker.isWallWalkingEnabled {
                wallWalker.toggleWallWalking()
            }
            
            if let mouseChaser = petEntity.capability(for: MouseChaser.self) {
                // If we're disabling mouse chasing, make sure to restore movement
                mouseChaser.kill()
                if let movement = petEntity.movement {
                    movement.isEnabled = true
                }
                petEntity.resetState()
                petEntity.resetSpeed()
            } else {
                // If we're enabling mouse chasing, let the MouseChaser handle movement
                let chaser = MouseChaser()
                petEntity.install(chaser)
            }
            
            // Update the menu item title
            if let menuItem = sender.menu?.items.first(where: { $0.action == #selector(toggleFollowMouse(_:)) }) {
                menuItem.title = petEntity.capability(for: MouseChaser.self) != nil ? 
                    "Stop Following Mouse" : "Follow Mouse"
            }
        }
        
        @objc func triggerAnimation(_ sender: NSMenuItem) {
            guard let (animationId, petEntity) = sender.representedObject as? (String, PetEntity) else { return }
            
            if animationId == "raincloud" {
                // Special handling for rain cloud
                guard let world = petEntity.world else { return }
                rainyCloudUseCase?.start(target: petEntity, world: world)
                return
            }
            
            // For sleep animation, use more loops and longer duration
            let loops = animationId == "sleep" ? 15 : 10
            let duration = animationId == "sleep" ? 7.0 : 5.0
            
            // Store current position and state
            let currentPosition = petEntity.frame.origin
            let currentSpeed = petEntity.speed
            
            // Keep collision detection enabled but disable movement
            if let movement = petEntity.movement {
                movement.isEnabled = false
            }
            petEntity.speed = 0
            
            // Play the animation
            petEntity.set(state: .action(action: .init(id: animationId), loops: loops))
            
            // Ensure the pet stays at its current position
            petEntity.frame.origin = currentPosition
            
            // Reset to normal state after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak petEntity] in
                guard let petEntity = petEntity else { return }
                if let movement = petEntity.movement {
                    movement.isEnabled = true
                }
                petEntity.frame.origin = currentPosition
                petEntity.resetState()
                petEntity.speed = currentSpeed
            }
        }
        
        @objc func toggleWallWalking(_ sender: NSMenuItem) {
            guard let (_, petEntity) = sender.representedObject as? (String, PetEntity) else { return }
            
            // Disable mouse chasing if it's enabled
            if let mouseChaser = petEntity.capability(for: MouseChaser.self) {
                mouseChaser.kill()
            }
            
            // Create wall walker if it doesn't exist
            if petEntity.wallWalker == nil {
                petEntity.install(WallWalker())
            }
            
            petEntity.wallWalker?.toggleWallWalking()
            
            // Update the menu item title
            if let menuItem = sender.menu?.items.first(where: { $0.action == #selector(toggleWallWalking(_:)) }) {
                menuItem.title = (petEntity.wallWalker?.isWallWalkingEnabled ?? false) ? 
                    "Disable Wall Walking" : "Enable Wall Walking"
            }
            
            // Update mouse following menu item if it exists
            if let mouseItem = sender.menu?.items.first(where: { $0.action == #selector(toggleFollowMouse(_:)) }) {
                mouseItem.title = "Follow Mouse"
            }
        }

        // Add the corner traversal toggle handler to MenuDelegate
        @objc func toggleCornerTraversal(_ sender: NSMenuItem) {
            guard let (_, petEntity) = sender.representedObject as? (String, PetEntity) else { return }
            petEntity.wallWalker?.toggleCornerTraversal()
            
            // Update the menu item title
            sender.title = petEntity.wallWalker?.cornerTraversalMenuTitle ?? "Toggle Corner Traversal"
        }
    }
#else
    class ShowsMenuOnRightClick: BaseRightClickable {}
#endif
