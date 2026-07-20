    import SpriteKit
    import UIKit

    /// A feel-first endless downhill physics slice.
    ///
    /// The bike is one stable chassis rigid body. Its wheels are visual only so
    /// suspension and wheel joints do not obscure the core question: is leaning a
    /// bike down this hill fun?
    final class MountainBikeScene: SKScene, SKPhysicsContactDelegate {
        private enum RunState {
            case intro
            case riding
            case crashing
            case results
        }

        private enum CrashReason: String {
            case lostBalance = "LOST BALANCE"
            case fell = "OUT OF BOUNDS"
        }

        /// Tracks relationships by body identity instead of a mutable contact count.
        /// This remains correct when terrain later grows into multiple chunks.
        private struct ContactBook {
            private var contactsByBody: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]

            mutating func began(_ first: SKPhysicsBody, _ second: SKPhysicsBody) {
                let firstID = ObjectIdentifier(first)
                let secondID = ObjectIdentifier(second)
                contactsByBody[firstID, default: []].insert(secondID)
                contactsByBody[secondID, default: []].insert(firstID)
            }

            mutating func ended(_ first: SKPhysicsBody, _ second: SKPhysicsBody) {
                remove(ObjectIdentifier(first), other: ObjectIdentifier(second))
                remove(ObjectIdentifier(second), other: ObjectIdentifier(first))
            }

            func touches(_ body: SKPhysicsBody, anyOf IDs: Set<ObjectIdentifier>) -> Bool {
                guard let contacts = contactsByBody[ObjectIdentifier(body)] else { return false }
                return !contacts.isDisjoint(with: IDs)
            }

            mutating func removeAll() {
                contactsByBody.removeAll(keepingCapacity: true)
            }

            mutating func forget(_ bodyID: ObjectIdentifier) {
                contactsByBody.removeValue(forKey: bodyID)
                let remainingBodyIDs = Array(contactsByBody.keys)
                for remainingBodyID in remainingBodyIDs {
                    remove(remainingBodyID, other: bodyID)
                }
            }

            private mutating func remove(_ body: ObjectIdentifier, other: ObjectIdentifier) {
                guard var contacts = contactsByBody[body] else { return }
                contacts.remove(other)
                if contacts.isEmpty {
                    contactsByBody.removeValue(forKey: body)
                } else {
                    contactsByBody[body] = contacts
                }
            }
        }

        private let skyLayer = SKNode()
        private let alpineAtmosphere = SKSpriteNode(
            color: SKColor(red: 0.67, green: 0.82, blue: 0.96, alpha: 1),
            size: .zero
        )
        private let treeLayer = SKNode()
        private let terrainLayer = SKNode()
        private let bike = BikeNode()
        private lazy var terrainStream = TerrainStreamController(
            terrainLayer: terrainLayer,
            sceneryLayer: treeLayer
        )
        private let cameraNode = SKCameraNode()

        private let hudLayer = SKNode()
        private let overlay = SKNode()
        private let distanceLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        private let speedLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        private let surfaceLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        private let toastLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        private let overlayCard = SKShapeNode()
        private let overlayTitle = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        private let overlaySubtitle = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        private let overlayPrompt = SKLabelNode(fontNamed: "AvenirNext-Bold")
        private let backControl = SKNode()
        private let pedalControl = SKNode()
        private let forwardControl = SKNode()

        private var contacts = ContactBook()
        private var activeTouches: [ObjectIdentifier: CGPoint] = [:]

        private var isConfigured = false
        private var runState: RunState = .intro
        private var lastUpdateTime: TimeInterval = 0
        private var frameDelta: TimeInterval = 0
        private var elapsedRunTime: TimeInterval = 0
        private var unsafeLeanTime: TimeInterval = 0
        private var pendingCrash: CrashReason?
        private var leanInput: CGFloat = 0
        private var pedalHeld = false
        private var lastGroundedRunTime: TimeInterval = -1_000
        private var lastTwoWheelSupportRunTime: TimeInterval = -1_000
        /// Measured after collision resolution, then applied on the following
        /// physics step. This carries a terrain reaction moment without injecting
        /// velocity or bypassing SpriteKit's gravity/collision solution.
    private var terrainPitchTorque: CGFloat = 0
    private var previousGroundVelocityX: CGFloat?
    private var takeoffAngle: CGFloat?
    private var previousAirborneAngle: CGFloat?
    private var airborneRotation: CGFloat = 0
    private var bestDistance = UserDefaults.standard.integer(forKey: "TrailRush.physicsBestDistance")

        private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
        private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

        private var levelStartX: CGFloat { terrainStream.levelStartX }
        private var levelEndX: CGFloat { terrainStream.levelEndX }
        private var currentDistance: Int {
            max(0, Int((bike.position.x - GameTuning.Bike.spawnX) / GameTuning.Display.worldUnitsPerMeter))
        }
        private var alpineBiomeBlend: CGFloat {
            let distanceMeters = max(
                0,
                (bike.position.x - GameTuning.Bike.spawnX) / GameTuning.Display.worldUnitsPerMeter
            )
            return 1 - clamp(
                (distanceMeters - GameTuning.Terrain.alpineBiomeEndDistanceMeters)
                    / GameTuning.Terrain.alpineBiomeBlendDistanceMeters,
                0,
                1
            )
        }
        private var currentSpeed: Int {
            Int(max(0, bike.physicsBody?.velocity.dx ?? 0) * GameTuning.Display.speedKilometersPerHourScale)
        }
        private var isGrounded: Bool {
            guard let bikeBody = bike.physicsBody else { return false }
            return contacts.touches(bikeBody, anyOf: terrainStream.terrainBodyIDs)
        }
    private var isPedalSupported: Bool {
        if isGrounded { return true }

            // Terrain contacts can arrive a frame after a wheel reaches a sampled
            // edge. Measure each tire against that same collision surface so a
            // rider can begin on, or continue up, an ordinary incline without
            // allowing PEDAL to reach across genuine airtime.
            let wheelCenters = [
                CGPoint(x: -GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY),
                CGPoint(x: GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY)
            ]
        return wheelCenters.contains(where: isWheelSettledOnTerrain)
    }
    /// A settled two-wheel landing is dynamically stable even across a sharp
    /// change in sampled terrain angle. Balance failures should begin only
    /// after one wheel has genuinely lost that support, not from a transient
    /// frame of geometry interpolation.
    private var hasTwoWheelSupport: Bool {
        let wheelCenters = [
            CGPoint(x: -GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY),
            CGPoint(x: GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY)
        ]
        return wheelCenters.allSatisfy(isWheelSettledOnTerrain)
    }

    private func isWheelSettledOnTerrain(_ localCenter: CGPoint) -> Bool {
        let worldCenter = bikeWorldPoint(from: localCenter)
        guard let surfaceHeight = terrainStream.surfaceTerrainHeight(at: worldCenter.x),
              let surfaceSlope = terrainStream.surfaceTerrainSlope(at: worldCenter.x) else {
            return false
        }
        let normalDistance = (worldCenter.y - surfaceHeight)
            / CGFloat(sqrt(1 + surfaceSlope * surfaceSlope))
        let minimumNormalDistance = GameTuning.Bike.collisionWheelRadius
            - GameTuning.Handling.pedalMaximumWheelPenetration
        let maximumNormalDistance = GameTuning.Bike.collisionWheelRadius
            + GameTuning.Handling.pedalWheelContactSlop
        return normalDistance >= minimumNormalDistance
            && normalDistance <= maximumNormalDistance
    }
        private var hasRecentGroundContact: Bool {
            elapsedRunTime - lastGroundedRunTime <= GameTuning.Handling.handlingContactGrace
        }
        private var hasRecentTwoWheelSupport: Bool {
            elapsedRunTime - lastTwoWheelSupportRunTime <= GameTuning.Crash.crestSupportGrace
        }
        private var isHandlingGrounded: Bool {
            isGrounded || hasRecentGroundContact
        }
        /// Attitude should switch to air behavior on the first actual contact gap.
        /// The longer handling grace remains reserved for drive input only.
        private var isAttitudeGrounded: Bool {
            isGrounded
        }

        override init(size: CGSize) {
            super.init(size: size)
            scaleMode = .aspectFill
            backgroundColor = .black
        }

        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
            scaleMode = .aspectFill
        }

        override func didMove(to view: SKView) {
            guard !isConfigured else { return }
            isConfigured = true
            view.isMultipleTouchEnabled = true
            view.preferredFramesPerSecond = GameTuning.Simulation.targetFramesPerSecond
            isUserInteractionEnabled = true
            physicsWorld.gravity = GameTuning.Simulation.gravity
            physicsWorld.speed = 1
            physicsWorld.contactDelegate = self

            configureScene()
            resetRun(showIntro: true)
            lightHaptic.prepare()
            heavyHaptic.prepare()
        }

        override func didChangeSize(_ oldSize: CGSize) {
            super.didChangeSize(oldSize)
            guard isConfigured else { return }
            buildBackdrop()
            layoutHUD()
            updateCamera(immediately: true)
        }

        // update(_:) occurs before SpriteKit simulates this frame's physics.
        override func update(_ currentTime: TimeInterval) {
            guard isConfigured else { return }

            if lastUpdateTime == 0 {
                lastUpdateTime = currentTime
                return
            }

            frameDelta = min(currentTime - lastUpdateTime, GameTuning.Simulation.maximumFrameDelta)
            lastUpdateTime = currentTime
            guard runState == .riding, let body = bike.physicsBody else { return }
            terrainStream.ensureTerrainAhead(of: bike.position.x)
            applyFlightPhysics(to: body)
            applyTerrainPitchLoad(to: body)
            applyAttitudeControl(to: body)
            applyPedalDrive(to: body)
        }

        // This is after contact callbacks and collision resolution for the frame.
        override func didSimulatePhysics() {
            guard isConfigured else { return }

            if runState == .riding {
                elapsedRunTime += frameDelta
                recoverEmbeddedWheels()
            updateGroundTracking()
            capBikeMotion()
            if let body = bike.physicsBody {
                captureTerrainPitchLoad(from: body)
            }
            trackAirborneRotation()
            evaluateRunState()
                commitPendingCrashIfNeeded()
                bike.spin(by: (bike.physicsBody?.velocity.dx ?? 0) * CGFloat(frameDelta))
                updateHUD()
                if runState == .riding {
                    retireTerrainBehindBike()
                }
            }

            updateCamera()
        }

        // MARK: - Scene construction

        private func configureScene() {
            skyLayer.zPosition = -100
            treeLayer.zPosition = -5
            terrainLayer.zPosition = 0
            bike.zPosition = 6
            cameraNode.zPosition = 50

            [treeLayer, terrainLayer, bike, cameraNode].forEach(addChild)
            camera = cameraNode
            cameraNode.addChild(skyLayer)
            cameraNode.addChild(hudLayer)
            cameraNode.addChild(overlay)

            buildBackdrop()
            configureHUD()
        }

        private func buildBackdrop() {
            skyLayer.removeAllChildren()

            // The photograph is attached to the camera so the endless course can
            // travel beneath it without ever revealing a finite backdrop edge.
            let backdropWidth = max(size.width * 3, 1_200)
            let backdropHeight = max(size.height * 3, 1_000)
            let texture = SKTexture(imageNamed: "mountain-background.jpg")
            let textureSize = texture.size()
            let scale = max(backdropWidth / textureSize.width, backdropHeight / textureSize.height)
            let photo = SKSpriteNode(texture: texture)
            photo.size = CGSize(width: textureSize.width * scale, height: textureSize.height * scale)
            photo.position = .zero
            skyLayer.addChild(photo)

            alpineAtmosphere.size = CGSize(width: backdropWidth, height: backdropHeight)
            alpineAtmosphere.position = .zero
            alpineAtmosphere.zPosition = 1
            alpineAtmosphere.blendMode = .screen
            alpineAtmosphere.alpha = alpineBiomeBlend * 0.62
            skyLayer.addChild(alpineAtmosphere)
        }


        // MARK: - HUD

        private func configureHUD() {
            [distanceLabel, speedLabel, surfaceLabel, toastLabel].forEach {
                $0.verticalAlignmentMode = .center
                hudLayer.addChild($0)
            }

            distanceLabel.fontSize = 23
            distanceLabel.fontColor = .white
            distanceLabel.horizontalAlignmentMode = .left

            speedLabel.fontSize = 16
            speedLabel.fontColor = SKColor(white: 1, alpha: 0.80)
            speedLabel.horizontalAlignmentMode = .right

            surfaceLabel.fontSize = 13
            surfaceLabel.fontColor = SKColor(red: 0.63, green: 0.95, blue: 0.86, alpha: 1)
            surfaceLabel.horizontalAlignmentMode = .center

            toastLabel.fontSize = 17
            toastLabel.fontColor = SKColor(red: 1, green: 0.87, blue: 0.33, alpha: 1)
            toastLabel.horizontalAlignmentMode = .center
            toastLabel.alpha = 0

            configureOverlay()
            configureControl(backControl, title: "LEAN", subtitle: "BACK")
            configureControl(pedalControl, title: "PEDAL", subtitle: "DRIVE")
            configureControl(forwardControl, title: "LEAN", subtitle: "FORWARD")
            hudLayer.addChild(backControl)
            hudLayer.addChild(pedalControl)
            hudLayer.addChild(forwardControl)
            layoutHUD()
        }

        private func configureOverlay() {
            overlayCard.fillColor = SKColor(red: 0.03, green: 0.08, blue: 0.14, alpha: 0.72)
            overlayCard.strokeColor = SKColor(white: 1, alpha: 0.22)
            overlayCard.lineWidth = 1
            overlay.addChild(overlayCard)

            overlayTitle.fontSize = 32
            overlayTitle.fontColor = .white
            overlayTitle.horizontalAlignmentMode = .center
            overlayTitle.verticalAlignmentMode = .center

            overlaySubtitle.fontSize = 12
            overlaySubtitle.fontColor = SKColor(red: 0.65, green: 0.94, blue: 0.86, alpha: 1)
            overlaySubtitle.horizontalAlignmentMode = .center
            overlaySubtitle.verticalAlignmentMode = .center

            overlayPrompt.fontSize = 15
            overlayPrompt.fontColor = SKColor(red: 1, green: 0.86, blue: 0.32, alpha: 1)
            overlayPrompt.horizontalAlignmentMode = .center
            overlayPrompt.verticalAlignmentMode = .center

            [overlayTitle, overlaySubtitle, overlayPrompt].forEach(overlay.addChild)
        }

        private func configureControl(_ control: SKNode, title: String, subtitle: String) {
            let circle = SKShapeNode(circleOfRadius: 38)
            circle.fillColor = SKColor(red: 0.05, green: 0.12, blue: 0.17, alpha: 0.45)
            circle.strokeColor = SKColor(white: 1, alpha: 0.25)
            circle.lineWidth = 1.5
            control.addChild(circle)

            let titleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
            titleLabel.text = title
            titleLabel.fontSize = 10
            titleLabel.fontColor = SKColor(white: 1, alpha: 0.90)
            titleLabel.horizontalAlignmentMode = .center
            titleLabel.verticalAlignmentMode = .center
            titleLabel.position.y = 6
            control.addChild(titleLabel)

            let subtitleLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            subtitleLabel.text = subtitle
            subtitleLabel.fontSize = 8
            subtitleLabel.fontColor = SKColor(white: 1, alpha: 0.66)
            subtitleLabel.horizontalAlignmentMode = .center
            subtitleLabel.verticalAlignmentMode = .center
            subtitleLabel.position.y = -9
            control.addChild(subtitleLabel)
        }

        private func layoutHUD() {
            let halfWidth = size.width / 2
            let halfHeight = size.height / 2
            let inset: CGFloat = 22

            distanceLabel.position = CGPoint(x: -halfWidth + inset, y: halfHeight - 28)
            speedLabel.position = CGPoint(x: halfWidth - inset, y: halfHeight - 28)
            surfaceLabel.position = CGPoint(x: 0, y: halfHeight - 28)
            toastLabel.position = CGPoint(x: 0, y: halfHeight * 0.24)

            backControl.position = CGPoint(x: -halfWidth + 66, y: -halfHeight + 58)
            pedalControl.position = CGPoint(x: 0, y: -halfHeight + 58)
            forwardControl.position = CGPoint(x: halfWidth - 66, y: -halfHeight + 58)

            let cardWidth = min(size.width - 52, 520)
            let cardHeight: CGFloat = 142
            overlayCard.path = CGPath(
                roundedRect: CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight),
                cornerWidth: 20,
                cornerHeight: 20,
                transform: nil
            )
            overlayTitle.position = CGPoint(x: 0, y: 27)
            overlaySubtitle.position = CGPoint(x: 0, y: -2)
            overlayPrompt.position = CGPoint(x: 0, y: -42)
        }

        private func updateHUD() {
            distanceLabel.text = "\(currentDistance)m"
            speedLabel.text = "\(currentSpeed) km/h"
            surfaceLabel.text = isGrounded ? "CONTACT" : "AIR"
        }

        // MARK: - Run state

        private func resetRun(showIntro: Bool) {
            contacts.removeAll()
            activeTouches.removeAll()
            leanInput = 0
        pedalHeld = false
        lastGroundedRunTime = -1_000
        lastTwoWheelSupportRunTime = -1_000
            elapsedRunTime = 0
            unsafeLeanTime = 0
            pendingCrash = nil
        terrainPitchTorque = 0
        previousGroundVelocityX = nil
        takeoffAngle = nil
        previousAirborneAngle = nil
        airborneRotation = 0
        runState = .intro

            bike.resetAppearance()
            bike.prepareForSpawn()
            terrainStream.reset()
            bike.position = CGPoint(
                x: GameTuning.Bike.spawnX,
                y: terrainStream.terrainHeight(at: GameTuning.Bike.spawnX) + GameTuning.Bike.spawnClearance
            )
            bike.zRotation = terrainStream.supportAngle(at: GameTuning.Bike.spawnX)

            backControl.setScale(1)
            pedalControl.setScale(1)
            forwardControl.setScale(1)
            if showIntro {
                showIntroOverlay()
            }
            updateHUD()
            updateCamera(immediately: true)
        }

        private func startRun() {
            if runState == .crashing || runState == .results {
                resetRun(showIntro: false)
            }

            guard runState == .intro, let body = bike.physicsBody else { return }
            runState = .riding
            body.isDynamic = true
            body.velocity = GameTuning.Bike.startVelocity
            body.angularVelocity = 0
            overlay.isHidden = true
            toast("DROP IN")
            lightHaptic.impactOccurred()
            lightHaptic.prepare()
        }

        private func evaluateRunState() {
            guard runState == .riding else { return }

            let hasLeftStart = bike.position.x >= GameTuning.Bike.spawnX + GameTuning.Crash.minimumTravelBeforeCrashChecks
            if elapsedRunTime >= GameTuning.Crash.spawnGrace && hasLeftStart {
            if !hasRecentTwoWheelSupport, frameHasStruckTerrain() {
                requestCrash(.lostBalance)
            }

            if abs(airborneRotation) >= GameTuning.Crash.maximumAirborneRotation {
                requestCrash(.lostBalance)
            }

            // Preserve airborneRotation through this frame so an inverted
            // landing cannot erase the evidence before the crash evaluator
            // sees it. A normal settled landing starts fresh immediately.
            if isAttitudeGrounded, pendingCrash == nil {
                airborneRotation = 0
            }

            if isHandlingGrounded {
                    let trailAngle = terrainStream.supportAngle(at: bike.position.x)
                    let leanError = abs(normalizedAngle(bike.zRotation - trailAngle))
                    let speedChallenge = clamp(
                        ((bike.physicsBody?.velocity.dx ?? 0)
                            - GameTuning.Crash.highSpeedLeanChallengeStart)
                            / (GameTuning.Crash.highSpeedLeanChallengeFull
                                - GameTuning.Crash.highSpeedLeanChallengeStart),
                        0,
                        1
                    )
                    let maximumLeanAngle = GameTuning.Crash.maximumRelativeLeanAngle
                        + (GameTuning.Crash.highSpeedMaximumRelativeLeanAngle
                            - GameTuning.Crash.maximumRelativeLeanAngle) * speedChallenge
                    let unsafeLeanDuration = GameTuning.Crash.unsafeLeanDuration
                        + (GameTuning.Crash.highSpeedUnsafeLeanDuration
                            - GameTuning.Crash.unsafeLeanDuration) * speedChallenge
                if leanError > maximumLeanAngle,
                   !hasTwoWheelSupport,
                   !hasRecentTwoWheelSupport {
                    unsafeLeanTime += frameDelta
                } else {
                    unsafeLeanTime = 0
                    }

                    if unsafeLeanTime >= unsafeLeanDuration {
                        requestCrash(.lostBalance)
                    }
                } else {
                    unsafeLeanTime = 0
                }
            }
            if bike.position.y < terrainStream.terrainHeight(at: bike.position.x) - GameTuning.Crash.fallBelowTerrainDistance {
                requestCrash(.fell)
            }
        }

        private func requestCrash(_ reason: CrashReason) {
            guard runState == .riding, pendingCrash == nil else { return }
            pendingCrash = reason
        }

        private func commitPendingCrashIfNeeded() {
            guard let reason = pendingCrash else { return }
            pendingCrash = nil
            enterCrash(reason)
        }

        private func enterCrash(_ reason: CrashReason) {
            guard runState == .riding else { return }
            runState = .crashing
            activeTouches.removeAll()
            leanInput = 0
            pedalHeld = false
            bike.freezePhysics()
            bike.crash()
            bestDistance = max(bestDistance, currentDistance)
            UserDefaults.standard.set(bestDistance, forKey: "TrailRush.physicsBestDistance")
            heavyHaptic.impactOccurred()
            heavyHaptic.prepare()
            showCrashOverlay(reason: reason)
            runState = .results
        }

        // MARK: - Physics contacts

        func didBegin(_ contact: SKPhysicsContact) {
            if matches(contact, first: PhysicsCategory.bike, second: PhysicsCategory.terrain) {
                contacts.began(contact.bodyA, contact.bodyB)
            }

        }

        func didEnd(_ contact: SKPhysicsContact) {
            if matches(contact, first: PhysicsCategory.bike, second: PhysicsCategory.terrain) {
                contacts.ended(contact.bodyA, contact.bodyB)
            }
        }

        private func matches(_ contact: SKPhysicsContact, first: UInt32, second: UInt32) -> Bool {
            let firstMatchesA = contact.bodyA.categoryBitMask & first != 0
            let secondMatchesB = contact.bodyB.categoryBitMask & second != 0
            let secondMatchesA = contact.bodyA.categoryBitMask & second != 0
            let firstMatchesB = contact.bodyB.categoryBitMask & first != 0
            return (firstMatchesA && secondMatchesB) || (secondMatchesA && firstMatchesB)
        }

        private func capBikeMotion() {
            guard let body = bike.physicsBody else { return }
            let speed = vectorLength(body.velocity)
            if speed > GameTuning.Bike.maximumSpeed {
                let scale = GameTuning.Bike.maximumSpeed / speed
                body.velocity = CGVector(dx: body.velocity.dx * scale, dy: body.velocity.dy * scale)
            }
            let groundHandlingFraction = clamp(
                (body.velocity.dx - GameTuning.Handling.highSpeedHandlingStart)
                    / (GameTuning.Handling.highSpeedHandlingFull
                        - GameTuning.Handling.highSpeedHandlingStart),
                0,
                1
            )
            let angularVelocityLimit: CGFloat
            if isAttitudeGrounded {
                angularVelocityLimit = GameTuning.Handling.groundMaximumAngularVelocity
                    + (GameTuning.Handling.highSpeedGroundAngularVelocity
                        - GameTuning.Handling.groundMaximumAngularVelocity)
                        * groundHandlingFraction
            } else {
                angularVelocityLimit = GameTuning.Handling.airMaximumAngularVelocity
            }
            body.angularVelocity = clamp(body.angularVelocity, -angularVelocityLimit, angularVelocityLimit)
        }

        /// A bike in flight follows the same constant gravity as it did on the
        /// trail. The only transition is the removal of ground-only damping and
        /// drive, so momentum leaving a lip becomes a clean ballistic arc.
        private func applyFlightPhysics(to body: SKPhysicsBody) {
            body.linearDamping = isGrounded
                ? GameTuning.Bike.groundLinearDamping
                : GameTuning.Bike.airLinearDamping
        }

        /// SpriteKit resolves the terrain's linear collision response itself. The
    /// bike is intentionally a single compound body, however, so that response
    /// does not fully express the wheelbase moment from suddenly losing forward
    /// speed. Apply only that measured, bounded reaction as torque; it never
    /// creates momentum.
        private func applyTerrainPitchLoad(to body: SKPhysicsBody) {
            guard isAttitudeGrounded, terrainPitchTorque != 0 else { return }
            body.applyTorque(terrainPitchTorque)
        }

    /// Samples the completed physics step rather than predicting a feature.
    /// The load follows sustained deceleration only; terrain angle changes are
    /// handled by real contact and rider control, preventing sampled rail
    /// detail from making the chassis bounce.
    private func captureTerrainPitchLoad(from body: SKPhysicsBody) {
        guard isAttitudeGrounded, frameDelta > 0 else {
            terrainPitchTorque = 0
            previousGroundVelocityX = nil
            return
        }

            let speed = max(body.velocity.dx, 0)
            let speedFraction = clamp(
                (speed - GameTuning.Handling.terrainPitchStartSpeed)
                    / (GameTuning.Handling.terrainPitchFullSpeed
                        - GameTuning.Handling.terrainPitchStartSpeed),
                0,
                1
            )
        defer {
            previousGroundVelocityX = body.velocity.dx
        }

        guard speedFraction > 0,
              let previousVelocityX = previousGroundVelocityX else {
            terrainPitchTorque = 0
            return
            }

            let deceleration = max(0, previousVelocityX - body.velocity.dx) / CGFloat(frameDelta)
            let decelerationFraction = clamp(
                deceleration / GameTuning.Handling.terrainDecelerationForFullPitch,
                0,
                1
            )
        let targetPitchTorque = -GameTuning.Handling.terrainDecelerationPitchTorque
            * decelerationFraction
            * speedFraction
        let responseFraction = clamp(
            CGFloat(frameDelta / GameTuning.Handling.terrainPitchResponseTime),
            0,
            1
        )
        terrainPitchTorque += (targetPitchTorque - terrainPitchTorque) * responseFraction
        terrainPitchTorque = clamp(
            terrainPitchTorque,
            -GameTuning.Handling.terrainMaximumPitchTorque,
            GameTuning.Handling.terrainMaximumPitchTorque
        )
    }

    /// Keep an unwrapped record of the bike's actual air rotation. A normalized
    /// angle alone would let a full 360-degree flip read as upright again.
    private func trackAirborneRotation() {
        guard !isAttitudeGrounded else {
            takeoffAngle = nil
            previousAirborneAngle = nil
            return
        }

        guard let previousAngle = previousAirborneAngle else {
            takeoffAngle = bike.zRotation
            previousAirborneAngle = bike.zRotation
            airborneRotation = 0
            return
        }
        airborneRotation += normalizedAngle(bike.zRotation - previousAngle)
        previousAirborneAngle = bike.zRotation
    }

        /// The bike already uses precise collision detection, but an edge rail can
        /// very occasionally leave one tire across the wrong side of a rail while
        /// the other remains supported. Resolve that shallow state by pivoting
        /// around the supported tire instead of lifting the whole bike. A deep
        /// miss is left to the normal crash/fall flow rather than being promoted to
        /// the top of the feature.
        private func recoverEmbeddedWheels() {
            guard let body = bike.physicsBody, isGrounded else {
                return
            }

            let wheelCenters = [
                CGPoint(x: -GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY),
                CGPoint(x: GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY)
            ]

            for embeddedIndex in wheelCenters.indices {
                let supportIndex = embeddedIndex == 0 ? 1 : 0
                let embeddedLocalCenter = wheelCenters[embeddedIndex]
                let supportLocalCenter = wheelCenters[supportIndex]
                let embeddedWorldCenter = bikeWorldPoint(from: embeddedLocalCenter)
                let supportWorldCenter = bikeWorldPoint(from: supportLocalCenter)
                guard let embeddedSurfaceHeight = terrainStream.surfaceTerrainHeight(at: embeddedWorldCenter.x),
                      let embeddedSurfaceSlope = terrainStream.surfaceTerrainSlope(at: embeddedWorldCenter.x),
                      let supportSurfaceHeight = terrainStream.surfaceTerrainHeight(at: supportWorldCenter.x),
                      let supportSurfaceSlope = terrainStream.surfaceTerrainSlope(at: supportWorldCenter.x) else {
                    continue
                }

                let recoveryTrigger = embeddedSurfaceHeight + GameTuning.Terrain.wheelPenetrationRecoveryTrigger
                guard embeddedWorldCenter.y < recoveryTrigger else { continue }

                let embeddedNormalScale = CGFloat(sqrt(1 + embeddedSurfaceSlope * embeddedSurfaceSlope))
                let requiredEmbeddedHeight = embeddedSurfaceHeight
                    + GameTuning.Bike.collisionWheelRadius * embeddedNormalScale
                    + GameTuning.Terrain.wheelPenetrationRecoveryClearance
                let supportNormalScale = CGFloat(sqrt(1 + supportSurfaceSlope * supportSurfaceSlope))
                let requiredSupportHeight = supportSurfaceHeight
                    + GameTuning.Bike.collisionWheelRadius * supportNormalScale
                    - GameTuning.Terrain.wheelPenetrationRecoveryClearance
                guard supportWorldCenter.y >= requiredSupportHeight else {
                    continue
                }

                let wheelSpanX = embeddedWorldCenter.x - supportWorldCenter.x
                guard abs(wheelSpanX) > 1 else { continue }
                let pivot = (requiredEmbeddedHeight - embeddedWorldCenter.y) / wheelSpanX
                guard abs(pivot) <= GameTuning.Terrain.wheelPenetrationMaximumPivot else {
                    continue
                }

                // Keep the supported tire in place while rotating the chassis up
                // and out of the invalid rail overlap.
                bike.zRotation += pivot
                let rotatedSupportCenter = bikeWorldPoint(from: supportLocalCenter)
                bike.position.x += supportWorldCenter.x - rotatedSupportCenter.x
                bike.position.y += supportWorldCenter.y - rotatedSupportCenter.y
                body.angularVelocity *= 0.25
                body.isResting = false
                return
            }
        }

        // MARK: - Input

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if runState != .riding {
                startRun()
            }

            guard runState == .riding else { return }

            for touch in touches {
                activeTouches[ObjectIdentifier(touch)] = touch.location(in: hudLayer)
            }
            updateControls()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard runState == .riding else { return }
            for touch in touches {
                activeTouches[ObjectIdentifier(touch)] = touch.location(in: hudLayer)
            }
            updateControls()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                activeTouches.removeValue(forKey: ObjectIdentifier(touch))
            }
            updateControls()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchesEnded(touches, with: event)
        }

        private func updateControls() {
            let laneWidth = size.width / 3
            let backHeld = activeTouches.values.contains { $0.x < -laneWidth / 2 }
            pedalHeld = activeTouches.values.contains { abs($0.x) <= laneWidth / 2 }
            let forwardHeld = activeTouches.values.contains { $0.x > laneWidth / 2 }

            // SpriteKit is y-up and the bike faces +x: positive torque pitches the nose up (back lean).
            switch (backHeld, forwardHeld) {
            case (true, false): leanInput = 1
            case (false, true): leanInput = -1
            default: leanInput = 0
            }

            backControl.setScale(backHeld ? 1.08 : 1)
            pedalControl.setScale(pedalHeld ? 1.08 : 1)
            forwardControl.setScale(forwardHeld ? 1.08 : 1)
        }

        /// PEDAL applies physical force only while a tire is actually on dirt.
        /// It never writes velocity or extends into an air gap, so launch speed
        /// remains the speed gravity and the rider carried to the lip.
        private func applyPedalDrive(to body: SKPhysicsBody) {
            guard pedalHeld, isPedalSupported else { return }

            guard let tangent = terrainStream.surfaceTerrainTangent(at: bike.position.x) else { return }
            let currentAlongTrail = body.velocity.dx * tangent.dx + body.velocity.dy * tangent.dy
            let assistFraction = clamp(
                1 - max(currentAlongTrail, 0) / GameTuning.Handling.pedalAssistSpeed,
                0,
                1
            )
            let uphillEffort = max(tangent.dy, 0)
            let pedalForce = GameTuning.Handling.pedalForce * assistFraction
            + GameTuning.Handling.pedalClimbForce * uphillEffort
        guard pedalForce > 0 else { return }

        body.isResting = false
        let driveForce = CGVector(
            dx: tangent.dx * pedalForce,
            dy: tangent.dy * pedalForce
        )
        let rearTractionShare = GameTuning.Handling.rearTractionForceShare
        body.applyForce(CGVector(
            dx: driveForce.dx * (1 - rearTractionShare),
            dy: driveForce.dy * (1 - rearTractionShare)
        ))
        let rearTirePoint = bike.convert(
            CGPoint(
                x: -GameTuning.Bike.wheelOffsetX,
                y: GameTuning.Bike.wheelOffsetY
            ),
            to: self
        )
        body.applyForce(CGVector(
            dx: driveForce.dx * rearTractionShare,
            dy: driveForce.dy * rearTractionShare
        ), at: rearTirePoint)
    }

    /// Leaning targets a modest pitch relative to the trail while rolling.
    /// This is a physical correction lever, not an impulse or a rotation-rate
    /// command that can topple a stationary bike.
    private func applyAttitudeControl(to body: SKPhysicsBody) {
        guard isAttitudeGrounded else {
            body.angularDamping = GameTuning.Handling.airAngularDamping
            guard leanInput != 0, let takeoffAngle else { return }
            let targetAngle = takeoffAngle
                + leanInput * GameTuning.Handling.airLeanMaximumOffset
            body.applyTorque(
                normalizedAngle(targetAngle - bike.zRotation)
                    * GameTuning.Handling.airLeanResponseTorque
            )
            return
        }

        let trailAngle = terrainStream.supportAngle(at: bike.position.x)
        let speed = max(body.velocity.dx, 0)
        let stabilizationFraction = clamp(
            1 - speed / GameTuning.Handling.groundStabilizationFadeSpeed,
            0,
            1
        )
        let leanSpeedFraction = clamp(
            (speed - GameTuning.Handling.groundLeanMinimumSpeed)
                / (GameTuning.Handling.groundLeanFullSpeed
                    - GameTuning.Handling.groundLeanMinimumSpeed),
            0,
            1
        )
        let highSpeedHandlingFraction = clamp(
            (speed - GameTuning.Handling.highSpeedHandlingStart)
                / (GameTuning.Handling.highSpeedHandlingFull
                    - GameTuning.Handling.highSpeedHandlingStart),
            0,
            1
        )
        body.angularDamping = GameTuning.Handling.groundAngularDamping
            + (GameTuning.Handling.highSpeedGroundAngularDamping
                - GameTuning.Handling.groundAngularDamping)
                * highSpeedHandlingFraction
        // Passive trail alignment fades almost entirely at speed. It prevents
        // a stopped bike from falling over, but cannot erase the pitch load of
        // a fast compression or crest when the player is not leaning.
        let trailAlignmentError = normalizedAngle(trailAngle - bike.zRotation)
        let trailAlignmentTorque = GameTuning.Handling.groundStabilizationTorque
            * stabilizationFraction
            + GameTuning.Handling.highSpeedTrailAlignmentTorque
                * (1 - stabilizationFraction)
        body.applyTorque(trailAlignmentError * trailAlignmentTorque)

        // Player input is intentionally stronger than the residual autopilot:
        // lean is the tool that catches the forward/rearward inertia above.
        guard leanInput != 0, leanSpeedFraction > 0 else { return }
        let leanTargetAngle = trailAngle
            + leanInput
                * GameTuning.Handling.groundLeanMaximumOffset
                * leanSpeedFraction
        let leanError = normalizedAngle(leanTargetAngle - bike.zRotation)
        body.applyTorque(
            leanError
                * GameTuning.Handling.groundLeanResponseTorque
                * leanSpeedFraction
        )
    }

    private func updateGroundTracking() {
        if isGrounded {
            lastGroundedRunTime = elapsedRunTime
        }
        if hasTwoWheelSupport {
            lastTwoWheelSupportRunTime = elapsedRunTime
        }
    }

    private func retireTerrainBehindBike() {
        guard let bikeBody = bike.physicsBody else { return }
        terrainStream.retireTerrain(
            behind: bike.position.x,
            isTouching: { terrainBodyIDs in
                contacts.touches(bikeBody, anyOf: terrainBodyIDs)
            },
            forgetBody: { contacts.forget($0) }
        )
    }

    // MARK: - Camera, feedback, and overlay

    private func updateCamera(immediately: Bool = false) {
        guard terrainStream.levelEndX > terrainStream.levelStartX else { return }
        let velocityX = bike.physicsBody?.velocity.dx ?? 0
        let lookAhead = clamp(
            GameTuning.Camera.baseLookAhead + velocityX * GameTuning.Camera.velocityLookAheadFactor,
            GameTuning.Camera.minimumLookAhead,
            GameTuning.Camera.maximumLookAhead
        )
        let horizontalInset = size.width * 0.44
        let target = CGPoint(
            x: max(bike.position.x + lookAhead, levelStartX + horizontalInset),
            y: bike.position.y + GameTuning.Camera.verticalBias
        )
        let amount: CGFloat
        if immediately {
            amount = 1
        } else {
            amount = min(CGFloat(frameDelta) * GameTuning.Camera.followResponsiveness, 1)
        }
        cameraNode.position.x += (target.x - cameraNode.position.x) * amount
        cameraNode.position.y += (target.y - cameraNode.position.y) * amount
        alpineAtmosphere.alpha = alpineBiomeBlend * 0.62
        hudLayer.zRotation = 0
        overlay.zRotation = 0
    }

    private func toast(_ text: String) {
        toastLabel.removeAllActions()
        toastLabel.text = text
        toastLabel.alpha = 1
        toastLabel.setScale(0.88)
        toastLabel.run(.sequence([
            .group([.scale(to: 1, duration: 0.14), .moveBy(x: 0, y: 7, duration: 0.14)]),
            .wait(forDuration: 0.34),
            .fadeOut(withDuration: 0.24),
            .moveBy(x: 0, y: -7, duration: 0)
        ]))
    }

    private func showIntroOverlay() {
        overlay.isHidden = false
        overlay.alpha = 1
        overlayTitle.text = "TRAIL RUSH"
        overlaySubtitle.text = "PINE RIDGE  •  PHYSICS PROTOTYPE"
        overlayPrompt.text = "HOLD PEDAL TO RIDE  •  LEAN LEFT / RIGHT"
    }

    private func showCrashOverlay(reason: CrashReason) {
        overlay.isHidden = false
        overlay.alpha = 0
        overlayTitle.text = "WIPEOUT"
        overlaySubtitle.text = "\(reason.rawValue)  •  \(currentDistance)m  •  BEST \(bestDistance)m"
        overlayPrompt.text = "TAP TO RIDE AGAIN"
        overlay.run(.fadeIn(withDuration: 0.18))
    }

    /// The rider/frame is visual, so it has no SpriteKit collision body of its
    /// own. These probes give it the one consequence a Trials-style bike needs:
    /// if the frame or bars strike the trail, the run is over.
    private func frameHasStruckTerrain() -> Bool {
        let relativePitch = normalizedAngle(bike.zRotation - terrainStream.supportAngle(at: bike.position.x))
        let minimumFrameStrikePitch = relativePitch > 0
            ? GameTuning.Crash.minimumRearWheelieFrameStrikePitch
            : GameTuning.Crash.minimumFrameStrikePitch
        guard abs(relativePitch) >= minimumFrameStrikePitch else { return false }

        // Only the leading end of a genuinely over-pitched bike can cause a
        // frame strike. This avoids false crashes from a normal wheel contact
        // while traversing a curved or steep section of trail.
        let localProbe = relativePitch > 0
            ? CGPoint(x: -43, y: 8)
            : CGPoint(x: 43, y: 8)
        let worldPoint = bikeWorldPoint(from: localProbe)
        // A sharp terrain transition can briefly intersect a visual-frame probe
        // even though the two tire contacts are still riding it correctly.
        // Reserve this crash path for a true frame strike on a manageable face.
        guard abs(terrainStream.terrainSlope(at: worldPoint.x)) <= GameTuning.Crash.frameStrikeMaximumTerrainSlope else {
            return false
        }
        return worldPoint.y <= terrainStream.terrainHeight(at: worldPoint.x) + GameTuning.Crash.frameProbeClearance
    }

    private func bikeWorldPoint(from localPoint: CGPoint) -> CGPoint {
        let cosine = CGFloat(cos(Double(bike.zRotation)))
        let sine = CGFloat(sin(Double(bike.zRotation)))
        return CGPoint(
            x: bike.position.x + localPoint.x * cosine - localPoint.y * sine,
            y: bike.position.y + localPoint.x * sine + localPoint.y * cosine
        )
    }

    // MARK: - Math

    private func vectorLength(_ vector: CGVector) -> CGFloat {
        CGFloat(hypot(Double(vector.dx), Double(vector.dy)))
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        max(lower, min(value, upper))
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var result = angle
        while result > .pi { result -= .pi * 2 }
        while result < -.pi { result += .pi * 2 }
        return result
    }

}
