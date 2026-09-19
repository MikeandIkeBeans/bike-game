import SpriteKit
import UIKit

/// Endless downhill scene using one compound mountain-bike body. Its compact
/// frame and two tire fixtures receive SpriteKit terrain contact; wheel art
/// and rider are visual children of that same body.
final class MountainBikeScene: SKScene, SKPhysicsContactDelegate {
    private enum RunState {
        case intro
        case riding
        case crashing
        case results
    }

    private enum CrashReason: String {
        case frameStrike = "FRAME STRIKE"
        case lostControl = "LOST CONTROL"
        case fell = "OUT OF BOUNDS"
    }

    /// Tracks each body pair rather than trusting a mutable contact count.
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

        func touches(_ body: SKPhysicsBody, anyOf bodyIDs: Set<ObjectIdentifier>) -> Bool {
            guard let contacts = contactsByBody[ObjectIdentifier(body)] else { return false }
            return !contacts.isDisjoint(with: bodyIDs)
        }

        func touches(_ body: SKPhysicsBody) -> Bool {
            !(contactsByBody[ObjectIdentifier(body)]?.isEmpty ?? true)
        }

        mutating func removeAll() {
            contactsByBody.removeAll(keepingCapacity: true)
        }

        mutating func forget(_ bodyID: ObjectIdentifier) {
            guard let otherIDs = contactsByBody.removeValue(forKey: bodyID) else { return }
            for otherID in otherIDs {
                remove(otherID, other: bodyID)
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
    private let effectsLayer = SKNode()
    private var roostTimer: TimeInterval = 0
    private lazy var dustTexture: SKTexture = {
        let diameter: CGFloat = 16
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { ctx in
            let rect = CGRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
        }
        return SKTexture(image: image)
    }()
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
    private let hudMapButton = SKShapeNode()
    private let hudMapLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private let overlayCard = SKShapeNode()
    private let overlayTitle = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let overlaySubtitle = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let overlayPrompt = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let mapSelector = SKNode()
    private let trailRushButton = SKShapeNode()
    private let megaJumpButton = SKShapeNode()
    private let trailRushTitle = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let trailRushSubtitle = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let megaJumpTitle = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let megaJumpSubtitle = SKLabelNode(fontNamed: "AvenirNext-Medium")

    private let backControl = SKNode()
    private let pedalControl = SKNode()
    private let forwardControl = SKNode()

    private(set) var mapMode: TerrainStreamController.GameMapMode = {
        if let saved = UserDefaults.standard.string(forKey: "MountainBike.mapMode"),
           let mode = TerrainStreamController.GameMapMode(rawValue: saved) {
            return mode
        }
        return .trailRush
    }()

    private var bestDistanceKey: String {
        mapMode == .megaJump ? "MegaJump.physicsBestDistance" : "TrailRush.physicsBestDistance"
    }

    private var contacts = ContactBook()
    private var activeTouches: [ObjectIdentifier: CGPoint] = [:]
    private var runState: RunState = .intro
    private var pendingCrash: CrashReason?
    private var isConfigured = false
    private var lastUpdateTime: TimeInterval = 0
    private var frameDelta: TimeInterval = 0
    private var elapsedRunTime: TimeInterval = 0
    private var leanInput: CGFloat = 0
    private var pedalHeld = false
    private var keyboardBackHeld = false
    private var keyboardForwardHeld = false
    private var keyboardPedalHeld = false
    private var previousAirborneAngle: CGFloat?
    private var airborneRotation: CGFloat = 0
    private var wasGrounded = true
    private var airborneTime: TimeInterval = 0
    private var airborneStartX: CGFloat = 0
    private var spawnPitchLockRemaining: TimeInterval = 0
    private lazy var bestDistance = UserDefaults.standard.integer(forKey: bestDistanceKey)

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    private var currentDistance: Int {
        max(0, Int((bike.chassisPosition.x - GameTuning.Bike.spawnX) / GameTuning.Display.worldUnitsPerMeter))
    }

    private var currentSpeed: Int {
        let speed = hypot(bike.velocity.dx, bike.velocity.dy)
        return Int(speed * GameTuning.Display.speedKilometersPerHourScale)
    }

    private var distanceMeters: CGFloat {
        max(0, (bike.chassisPosition.x - GameTuning.Bike.spawnX) / GameTuning.Display.worldUnitsPerMeter)
    }

    private var alpineBiomeBlend: CGFloat {
        1 - clamp(
            (distanceMeters - GameTuning.Terrain.alpineBiomeEndDistanceMeters)
                / GameTuning.Terrain.alpineBiomeBlendDistanceMeters,
            0,
            1
        )
    }

    /// Ground truth read straight from tire height vs. terrain, not from
    /// SpriteKit's contact-event bookkeeping. A compound body rolling across
    /// a stream of separate terrain-chunk bodies can go a frame or more
    /// without a fresh didBegin/didEnd even while a tire is resting on the
    /// ground, and pedal drive can't afford to miss those frames. `contacts`
    /// stays in place below for terrain retirement, which can tolerate that
    /// lag.
    private var isGrounded: Bool {
        axleClearance(at: bike.rearAxlePosition) != nil
            || axleClearance(at: bike.frontAxlePosition) != nil
    }

    private func axleClearance(at axlePosition: CGPoint) -> CGFloat? {
        guard let terrainY = terrainStream.surfaceTerrainHeight(at: axlePosition.x) else {
            return nil
        }
        let clearance = axlePosition.y - terrainY
        let minClearance = -GameTuning.Terrain.wheelPenetrationRecoveryTrigger
        let maxClearance = GameTuning.Bike.collisionWheelRadius + GameTuning.Bike.groundedTolerance
        return (clearance >= minClearance && clearance <= maxClearance) ? clearance : nil
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

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        guard isConfigured else { return }
        guard lastUpdateTime != 0 else {
            lastUpdateTime = currentTime
            return
        }

        frameDelta = min(currentTime - lastUpdateTime, GameTuning.Simulation.maximumFrameDelta)
        lastUpdateTime = currentTime
        guard runState == .riding else { return }

        updateSpawnPitchLock()
        terrainStream.ensureTerrainAhead(of: bike.chassisPosition.x)
        applyPedalDrive()
        applyBraking()
        updatePedalRoost()
        applyRiderLean()
        capVehicleMotion()
    }

    override func didSimulatePhysics() {
        guard isConfigured else { return }

        if runState == .riding {
            bike.recoverTerrainPenetration(
                terrainHeightAt: { [weak self] x in
                    guard let self = self else { return 0 }
                    return self.terrainStream.surfaceTerrainHeight(at: x) ?? self.terrainStream.terrainHeight(at: x)
                },
                terrainSlopeAt: { [weak self] x in
                    guard let self = self else { return 0 }
                    return self.terrainStream.surfaceTerrainSlope(at: x) ?? self.terrainStream.terrainSlope(at: x)
                }
            )

            // Catastrophic tunneling failsafe: if a frame hitch or solver glitch
            // ever places the chassis >25 units beneath the terrain line while NOT grounded,
            // immediately rescue the bike back onto the trail with preserved momentum.
            let chassisX = bike.chassisPosition.x
            let terrainY = terrainStream.surfaceTerrainHeight(at: chassisX) ?? terrainStream.terrainHeight(at: chassisX)
            if !isGrounded && bike.chassisPosition.y < terrainY - 25 {
                let attitude = terrainStream.supportAngle(at: chassisX)
                let safeY = terrainY + bike.spawnClearance(for: attitude) + 2.0
                let currentSpeed = max(bike.velocity.dx, 150)
                bike.reset(at: CGPoint(x: chassisX, y: safeY), attitude: attitude)
                bike.activatePhysics()
                bike.chassisBody.velocity = CGVector(dx: currentSpeed, dy: 0)
            }

            elapsedRunTime += frameDelta
            bike.updateVisuals(deltaTime: frameDelta, leanInput: leanInput, pedalHeld: pedalHeld)
            capVehicleMotion()
            updateAirborneRotation()
            updateAirborneAndLandingState()
            evaluateRunState()
            commitPendingCrashIfNeeded()
            updateHUD()
            if runState == .riding {
                retireTerrainBehindBike()
            }
        }

        updateCamera()
    }

    // MARK: - Physics input and state

    /// PEDAL applies a tangential rider force only while the compound bike is
    /// genuinely in terrain contact. Downhill speed remains gravity and
    /// collision driven; pedalling cannot accelerate an air gap.
    private func applyPedalDrive() {
        guard pedalHeld, isGrounded,
              let tangent = pedalSupportTangent() else {
            return
        }

        let alongTrail = bike.velocity.dx * tangent.dx + bike.velocity.dy * tangent.dy

        // Anti-rollback ratcheting freewheel: if sliding backward on an uphill slope,
        // cancel the backward slide so pedal drive immediately powers forward.
        if alongTrail < 0 && tangent.dy > 0 {
            for body in bike.allBodies {
                body.velocity.dx -= tangent.dx * alongTrail
                body.velocity.dy -= tangent.dy * alongTrail
            }
        }

        let forwardSpeed = max(0, bike.velocity.dx * tangent.dx + bike.velocity.dy * tangent.dy)
        let forceFade = clamp(
            1 - forwardSpeed / GameTuning.Handling.pedalFadeSpeed,
            0,
            1
        )
        let climbLoad = max(tangent.dy, 0)
        let riderForce = (GameTuning.Handling.pedalForce + GameTuning.Handling.pedalClimbForce * climbLoad) * forceFade
        guard riderForce > 0 else { return }

        // Apply force across all bodies proportional to mass for smooth, unified acceleration
        let forceVector = CGVector(
            dx: tangent.dx * riderForce,
            dy: tangent.dy * riderForce
        )
        let totalMass: CGFloat = GameTuning.Bike.chassisMass
            + GameTuning.Bike.swingarmMass
            + GameTuning.Bike.rearWheelMass
            + GameTuning.Bike.frontForkMass
            + GameTuning.Bike.frontWheelMass

        for body in bike.allBodies {
            body.isResting = false
            let massFraction = body.mass / totalMass
            body.applyForce(CGVector(
                dx: forceVector.dx * massFraction,
                dy: forceVector.dy * massFraction
            ))
        }
    }

    /// Rear wheel braking applied while grounded when leaning back (or pressing brake key).
    /// Decelerates the bike along the trail tangent, decreases cached rolling momentum,
    /// and allows controlled speed management on technical trails.
    private func applyBraking() {
        guard isGrounded, leanInput < 0, let tangent = pedalSupportTangent() else { return }
        let alongTrail = bike.velocity.dx * tangent.dx + bike.velocity.dy * tangent.dy
        guard alongTrail > 20 else { return }

        // Progressive rear wheel braking deceleration (450 pt/s² ~ 100 km/h per second)
        let brakeDecel = CGFloat(frameDelta) * 450.0

        let targetSpeed = max(0, alongTrail - brakeDecel)
        let targetVx = tangent.dx * targetSpeed
        let targetVy = tangent.dy * targetSpeed

        let blend: CGFloat = min(CGFloat(frameDelta) * 16.0, 0.65)
        let newVx = bike.velocity.dx * (1 - blend) + targetVx * blend
        let newVy = bike.velocity.dy * (1 - blend) + targetVy * blend
        let newVelocity = CGVector(dx: newVx, dy: newVy)
        for body in bike.allBodies {
            body.velocity = newVelocity
        }

        // Emit brake skid dust if braking at speed
        if alongTrail > 150 && roostTimer >= 0.08 {
            roostTimer = 0
            emitPedalRoost(at: CGPoint(
                x: bike.rearAxlePosition.x,
                y: bike.rearAxlePosition.y - GameTuning.Bike.collisionWheelRadius
            ))
        }
    }

    private func updatePedalRoost() {
        guard pedalHeld, isGrounded else {
            roostTimer = 0
            return
        }
        roostTimer += frameDelta
        if roostTimer >= 0.08 {
            roostTimer = 0
            let contactPoint = CGPoint(
                x: bike.rearAxlePosition.x,
                y: bike.rearAxlePosition.y - GameTuning.Bike.collisionWheelRadius
            )
            emitPedalRoost(at: contactPoint)
        }
    }

    /// A terrain contact can occur beneath either tire while the chassis
    /// centre is over a lip or gap. Resolve drive direction from the wheelbase
    /// first so the forward support surface remains stable.
    private func pedalSupportTangent() -> CGVector? {
        let sampleXs = [
            bike.rearAxlePosition.x,
            bike.frontAxlePosition.x,
            bike.chassisPosition.x
        ]
        for x in sampleXs {
            if let tangent = terrainStream.surfaceTerrainTangent(at: x) {
                return tangent
            }
        }
        return nil
    }

    /// Lean applies physical pitch torque to the one-piece bike body. It has
    /// no linear assist or velocity correction.
    private func applyRiderLean() {
        guard leanInput != 0 else { return }
        let torqueMagnitude = isGrounded
            ? GameTuning.Handling.groundLeanTorque
            : GameTuning.Handling.airLeanTorque
        let torque = leanInput * torqueMagnitude
        bike.chassisBody.applyTorque(torque)
    }

    private func capVehicleMotion() {
        let maxAllowedSpeed = GameTuning.Bike.maximumSpeed
        for body in bike.allBodies {
            let speed = vectorLength(body.velocity)
            if speed > maxAllowedSpeed {
                let scale = maxAllowedSpeed / speed
                body.velocity = CGVector(dx: body.velocity.dx * scale, dy: body.velocity.dy * scale)
            }
        }
        for body in [bike.chassisBody, bike.swingarmBody, bike.frontForkBody] {
            body.angularVelocity = clamp(
                body.angularVelocity,
                -GameTuning.Bike.maximumChassisAngularVelocity,
                GameTuning.Bike.maximumChassisAngularVelocity
            )
        }
    }

    private func updateAirborneRotation() {
        guard !isGrounded else {
            previousAirborneAngle = nil
            airborneRotation = 0
            return
        }
        guard let previousAngle = previousAirborneAngle else {
            previousAirborneAngle = bike.chassisRotation
            airborneRotation = 0
            return
        }
        airborneRotation += normalizedAngle(bike.chassisRotation - previousAngle)
        previousAirborneAngle = bike.chassisRotation
    }

    private func updateAirborneAndLandingState() {
        let currentlyGrounded = isGrounded
        if !currentlyGrounded {
            if wasGrounded {
                airborneStartX = bike.chassisPosition.x
                airborneTime = 0
            }
            airborneTime += frameDelta
        } else if !wasGrounded {
            if airborneTime >= 0.25 {
                lightHaptic.impactOccurred()
                lightHaptic.prepare()
                let rearContact = CGPoint(x: bike.rearAxlePosition.x, y: bike.rearAxlePosition.y - GameTuning.Bike.collisionWheelRadius)
                let frontContact = CGPoint(x: bike.frontAxlePosition.x, y: bike.frontAxlePosition.y - GameTuning.Bike.collisionWheelRadius)
                emitLandingDust(at: rearContact)
                emitLandingDust(at: frontContact)
                let airDistance = max(0, Int((bike.chassisPosition.x - airborneStartX) / GameTuning.Display.worldUnitsPerMeter))
                if airborneTime >= 0.75 || airDistance >= 20 {
                    let airToast: String
                    if airDistance >= 60 {
                        airToast = "MEGA AIR \(airDistance)m"
                    } else if airDistance >= 30 {
                        airToast = "HUGE AIR \(airDistance)m"
                    } else {
                        airToast = "BIG AIR \(airDistance)m"
                    }
                    toast(airToast)
                }
            }
            airborneTime = 0
            airborneStartX = 0
        }
        wasGrounded = currentlyGrounded
    }

    private func evaluateRunState() {
        guard runState == .riding else { return }
        let hasLeftStart = bike.chassisPosition.x >= GameTuning.Bike.spawnX + GameTuning.Crash.minimumTravelBeforeCrashChecks

        if elapsedRunTime >= GameTuning.Crash.spawnGrace, hasLeftStart {
            if abs(airborneRotation) >= GameTuning.Crash.maximumAirborneRotation || abs(bike.chassisRotation) >= GameTuning.Crash.maximumRelativeLeanAngle {
                requestCrash(.lostControl)
            }
            let frameContact = contacts.touches(bike.chassisBody)
            if frameContact && abs(bike.chassisRotation) >= GameTuning.Crash.minimumFrameStrikePitch {
                requestCrash(.frameStrike)
            }
        }

        if bike.chassisPosition.y < terrainStream.terrainHeight(at: bike.chassisPosition.x) - GameTuning.Crash.fallBelowTerrainDistance {
            requestCrash(.fell)
        }
    }

    // MARK: - Contacts and lifecycle

    func didBegin(_ contact: SKPhysicsContact) {
        if matches(contact, first: PhysicsCategory.allBike, second: PhysicsCategory.terrain) {
            contacts.began(contact.bodyA, contact.bodyB)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        if matches(contact, first: PhysicsCategory.allBike, second: PhysicsCategory.terrain) {
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

    private func requestCrash(_ reason: CrashReason) {
        guard runState == .riding, pendingCrash == nil else { return }
        pendingCrash = reason
    }

    private func commitPendingCrashIfNeeded() {
        guard let reason = pendingCrash else { return }
        pendingCrash = nil
        enterCrash(reason)
    }

    private func resetRun(showIntro: Bool) {
        removeAction(forKey: "crashSequence")
        cameraNode.removeAction(forKey: "crashCameraShake")
        contacts.removeAll()
        activeTouches.removeAll()
        leanInput = 0
        pedalHeld = false
        keyboardBackHeld = false
        keyboardForwardHeld = false
        keyboardPedalHeld = false
        elapsedRunTime = 0
        previousAirborneAngle = nil
        airborneRotation = 0
        wasGrounded = true
        airborneTime = 0
        airborneStartX = 0
        roostTimer = 0
        effectsLayer.removeAllChildren()
        spawnPitchLockRemaining = 0
        pendingCrash = nil
        runState = .intro

        terrainStream.mapMode = mapMode
        bestDistance = UserDefaults.standard.integer(forKey: bestDistanceKey)
        terrainStream.reset()
        bike.resetAppearance()
        bike.prepareForSpawn()
        let spawnAttitude = terrainStream.supportAngle(at: GameTuning.Bike.spawnX)
        bike.reset(
            at: CGPoint(
                x: GameTuning.Bike.spawnX,
                y: terrainStream.terrainHeight(at: GameTuning.Bike.spawnX)
                    + bike.spawnClearance(for: spawnAttitude)
            ),
            attitude: spawnAttitude
        )

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
        guard runState != .crashing else { return }
        if runState == .results {
            resetRun(showIntro: false)
        }
        guard runState == .intro else { return }
        spawnPitchLockRemaining = GameTuning.Bike.spawnPitchLockDuration
        bike.activatePhysics(lockPitch: spawnPitchLockRemaining > 0)
        runState = .riding
        overlay.isHidden = true
        toast("DROP IN")
        lightHaptic.impactOccurred()
        lightHaptic.prepare()
    }

    /// The bike begins already aligned to the supporting rail. Locking pitch
    /// briefly lets both tire fixtures settle before terrain impulses can act
    /// on the full wheelbase as a launch lever.
    private func updateSpawnPitchLock() {
        guard spawnPitchLockRemaining > 0 else { return }
        spawnPitchLockRemaining -= frameDelta
        if spawnPitchLockRemaining <= 0 {
            spawnPitchLockRemaining = 0
            bike.unlockPitch()
        }
    }

    private func enterCrash(_ reason: CrashReason) {
        guard runState == .riding else { return }
        runState = .crashing
        activeTouches.removeAll()
        leanInput = 0
        pedalHeld = false
        keyboardBackHeld = false
        keyboardForwardHeld = false
        keyboardPedalHeld = false
        airborneTime = 0
        airborneStartX = 0
        bike.freezePhysics()
        bike.crash()
        emitCrashDust(at: bike.chassisPosition)
        bestDistance = max(bestDistance, currentDistance)
        UserDefaults.standard.set(bestDistance, forKey: bestDistanceKey)
        heavyHaptic.impactOccurred()
        heavyHaptic.prepare()

        cameraNode.run(.sequence([
            .moveBy(x: -8, y: 6, duration: 0.04),
            .moveBy(x: 14, y: -10, duration: 0.04),
            .moveBy(x: -10, y: 7, duration: 0.04),
            .moveBy(x: 4, y: -3, duration: 0.04)
        ]), withKey: "crashCameraShake")

        run(.sequence([
            .wait(forDuration: 0.8),
            .run { [weak self] in
                guard let self = self, self.runState == .crashing else { return }
                self.showCrashOverlay(reason: reason)
                self.runState = .results
            }
        ]), withKey: "crashSequence")
    }

    private func retireTerrainBehindBike() {
        terrainStream.retireTerrain(
            behind: bike.chassisPosition.x,
            isTouching: { terrainBodyIDs in
                bike.allBodies.contains { contacts.touches($0, anyOf: terrainBodyIDs) }
            },
            forgetBody: { contacts.forget($0) }
        )
    }

    // MARK: - Touch and Keyboard input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if !overlay.isHidden {
                let posInSelector = touch.location(in: mapSelector)
                if trailRushButton.contains(posInSelector) {
                    selectMapMode(.trailRush)
                    return
                } else if megaJumpButton.contains(posInSelector) {
                    selectMapMode(.megaJump)
                    return
                }
            }
            let posInHud = touch.location(in: hudLayer)
            if hudMapButton.contains(posInHud) {
                toggleMapMode()
                return
            }
        }

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

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let chars = key.charactersIgnoringModifiers.lowercased()
            switch chars {
            case "a", UIKeyCommand.inputLeftArrow.lowercased(), "s", UIKeyCommand.inputDownArrow.lowercased():
                keyboardBackHeld = true
                handled = true
            case "d", UIKeyCommand.inputRightArrow.lowercased():
                keyboardForwardHeld = true
                handled = true
            case "w", " ", UIKeyCommand.inputUpArrow.lowercased():
                keyboardPedalHeld = true
                handled = true
            case "r":
                resetRun(showIntro: false)
                startRun()
                handled = true
            case "m":
                toggleMapMode()
                return
            default:
                break
            }
        }
        if handled {
            if runState != .riding {
                startRun()
            }
            updateControls()
        } else {
            super.pressesBegan(presses, with: event)
        }
    }

    private func selectMapMode(_ mode: TerrainStreamController.GameMapMode) {
        guard mapMode != mode else { return }
        mapMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "MountainBike.mapMode")
        terrainStream.mapMode = mode
        bestDistance = UserDefaults.standard.integer(forKey: bestDistanceKey)
        updateMapSelectorVisuals()
        lightHaptic.impactOccurred()
        lightHaptic.prepare()
        resetRun(showIntro: true)
        toast("MAP: \(mode.rawValue)")
    }

    private func toggleMapMode() {
        let nextMode: TerrainStreamController.GameMapMode = (mapMode == .trailRush) ? .megaJump : .trailRush
        selectMapMode(nextMode)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let chars = key.charactersIgnoringModifiers.lowercased()
            switch chars {
            case "a", UIKeyCommand.inputLeftArrow.lowercased(), "s", UIKeyCommand.inputDownArrow.lowercased():
                keyboardBackHeld = false
                handled = true
            case "d", UIKeyCommand.inputRightArrow.lowercased():
                keyboardForwardHeld = false
                handled = true
            case "w", " ", UIKeyCommand.inputUpArrow.lowercased():
                keyboardPedalHeld = false
                handled = true
            default:
                break
            }
        }
        if handled {
            updateControls()
        } else {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressesEnded(presses, with: event)
    }

    private func updateControls() {
        let laneWidth = size.width / 3
        let backHeld = keyboardBackHeld || activeTouches.values.contains { $0.x < -laneWidth / 2 }
        pedalHeld = keyboardPedalHeld || activeTouches.values.contains { abs($0.x) <= laneWidth / 2 }
        let forwardHeld = keyboardForwardHeld || activeTouches.values.contains { $0.x > laneWidth / 2 }
        switch (backHeld, forwardHeld) {
        case (true, false): leanInput = 1
        case (false, true): leanInput = -1
        default: leanInput = 0
        }
        backControl.setScale(backHeld ? 1.08 : 1)
        pedalControl.setScale(pedalHeld ? 1.08 : 1)
        forwardControl.setScale(forwardHeld ? 1.08 : 1)
    }

    // MARK: - Particle effects

    private func emitPedalRoost(at point: CGPoint) {
        let roost = SKEmitterNode()
        roost.particleTexture = dustTexture
        roost.particleBirthRate = 50
        roost.numParticlesToEmit = 3
        roost.particleLifetime = 0.35
        roost.particleLifetimeRange = 0.1
        roost.particlePosition = point
        roost.particleSpeed = 38
        roost.particleSpeedRange = 15
        roost.emissionAngle = .pi * 0.85
        roost.emissionAngleRange = .pi * 0.35
        roost.particleAlpha = 0.45
        roost.particleAlphaSpeed = -1.2
        roost.particleScale = 0.35
        roost.particleScaleSpeed = 0.25
        roost.particleColor = SKColor(red: 0.58, green: 0.46, blue: 0.34, alpha: 1.0)
        roost.particleColorBlendFactor = 1.0
        effectsLayer.addChild(roost)
        roost.run(.sequence([
            .wait(forDuration: 0.5),
            .removeFromParent()
        ]))
    }

    private func emitLandingDust(at point: CGPoint) {
        let burst = SKEmitterNode()
        burst.particleTexture = dustTexture
        burst.particleBirthRate = 70
        burst.numParticlesToEmit = 10
        burst.particleLifetime = 0.42
        burst.particleLifetimeRange = 0.12
        burst.particlePosition = point
        burst.particleSpeed = 45
        burst.particleSpeedRange = 20
        burst.emissionAngle = .pi * 0.5
        burst.emissionAngleRange = .pi * 0.75
        burst.particleAlpha = 0.55
        burst.particleAlphaSpeed = -1.2
        burst.particleScale = 0.45
        burst.particleScaleSpeed = 0.3
        burst.particleColor = SKColor(red: 0.62, green: 0.50, blue: 0.38, alpha: 1.0)
        burst.particleColorBlendFactor = 1.0
        effectsLayer.addChild(burst)
        burst.run(.sequence([
            .wait(forDuration: 0.6),
            .removeFromParent()
        ]))
    }

    private func emitCrashDust(at point: CGPoint) {
        let blast = SKEmitterNode()
        blast.particleTexture = dustTexture
        blast.particleBirthRate = 120
        blast.numParticlesToEmit = 24
        blast.particleLifetime = 0.65
        blast.particleLifetimeRange = 0.2
        blast.particlePosition = point
        blast.particleSpeed = 75
        blast.particleSpeedRange = 40
        blast.emissionAngle = .pi * 0.5
        blast.emissionAngleRange = .pi * 2.0
        blast.particleAlpha = 0.7
        blast.particleAlphaSpeed = -1.0
        blast.particleScale = 0.6
        blast.particleScaleSpeed = 0.4
        blast.particleColor = SKColor(red: 0.55, green: 0.44, blue: 0.35, alpha: 1.0)
        blast.particleColorBlendFactor = 1.0
        effectsLayer.addChild(blast)
        blast.run(.sequence([
            .wait(forDuration: 0.9),
            .removeFromParent()
        ]))
    }

    // MARK: - Scene construction

    private func configureScene() {
        skyLayer.zPosition = -100
        treeLayer.zPosition = -5
        terrainLayer.zPosition = 0
        effectsLayer.zPosition = 4
        bike.zPosition = 6
        cameraNode.zPosition = 50
        [treeLayer, terrainLayer, effectsLayer, bike, cameraNode].forEach(addChild)
        camera = cameraNode
        cameraNode.addChild(skyLayer)
        cameraNode.addChild(hudLayer)
        cameraNode.addChild(overlay)
        buildBackdrop()
        configureHUD()
    }

    private func buildBackdrop() {
        skyLayer.removeAllChildren()
        let backdropWidth = max(size.width * 3, 1_200)
        let backdropHeight = max(size.height * 3, 1_000)
        let texture = SKTexture(imageNamed: "mountain-background.jpg")
        let textureSize = texture.size()
        let scale = max(backdropWidth / textureSize.width, backdropHeight / textureSize.height)
        let photo = SKSpriteNode(texture: texture)
        photo.size = CGSize(width: textureSize.width * scale, height: textureSize.height * scale)
        skyLayer.addChild(photo)

        alpineAtmosphere.size = CGSize(width: backdropWidth, height: backdropHeight)
        alpineAtmosphere.blendMode = .screen
        alpineAtmosphere.zPosition = 1
        alpineAtmosphere.alpha = alpineBiomeBlend * 0.62
        skyLayer.addChild(alpineAtmosphere)
    }

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

        hudMapButton.path = CGPath(
            roundedRect: CGRect(x: -58, y: -11, width: 116, height: 22),
            cornerWidth: 11,
            cornerHeight: 11,
            transform: nil
        )
        hudMapButton.fillColor = SKColor(red: 0.05, green: 0.12, blue: 0.18, alpha: 0.70)
        hudMapButton.strokeColor = SKColor(white: 1, alpha: 0.35)
        hudMapButton.lineWidth = 1
        hudMapLabel.fontSize = 10
        hudMapLabel.fontColor = SKColor(white: 1, alpha: 0.90)
        hudMapLabel.horizontalAlignmentMode = .center
        hudMapLabel.verticalAlignmentMode = .center
        hudMapLabel.text = "MAP: \(mapMode.rawValue)"
        hudMapButton.addChild(hudMapLabel)
        hudLayer.addChild(hudMapButton)

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
        overlayCard.fillColor = SKColor(red: 0.03, green: 0.08, blue: 0.14, alpha: 0.82)
        overlayCard.strokeColor = SKColor(white: 1, alpha: 0.28)
        overlayCard.lineWidth = 1
        overlay.addChild(overlayCard)
        overlayTitle.fontSize = 30
        overlayTitle.fontColor = .white
        overlayTitle.horizontalAlignmentMode = .center
        overlayTitle.verticalAlignmentMode = .center
        overlaySubtitle.fontSize = 11
        overlaySubtitle.fontColor = SKColor(red: 0.65, green: 0.94, blue: 0.86, alpha: 1)
        overlaySubtitle.horizontalAlignmentMode = .center
        overlaySubtitle.verticalAlignmentMode = .center
        overlayPrompt.fontSize = 13
        overlayPrompt.fontColor = SKColor(red: 1, green: 0.86, blue: 0.32, alpha: 1)
        overlayPrompt.horizontalAlignmentMode = .center
        overlayPrompt.verticalAlignmentMode = .center
        [overlayTitle, overlaySubtitle, overlayPrompt].forEach(overlay.addChild)

        configureMapButton(trailRushButton, titleLabel: trailRushTitle, subtitleLabel: trailRushSubtitle, title: "TRAIL RUSH", subtitle: "ENDLESS DOWNHILL")
        configureMapButton(megaJumpButton, titleLabel: megaJumpTitle, subtitleLabel: megaJumpSubtitle, title: "MEGA JUMP", subtitle: "MASSIVE AIR RAMP")
        mapSelector.addChild(trailRushButton)
        mapSelector.addChild(megaJumpButton)
        overlay.addChild(mapSelector)
        updateMapSelectorVisuals()
    }

    private func configureMapButton(_ button: SKShapeNode, titleLabel: SKLabelNode, subtitleLabel: SKLabelNode, title: String, subtitle: String) {
        let btnWidth: CGFloat = 136
        let btnHeight: CGFloat = 38
        button.path = CGPath(
            roundedRect: CGRect(x: -btnWidth / 2, y: -btnHeight / 2, width: btnWidth, height: btnHeight),
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        button.lineWidth = 1.5

        titleLabel.text = title
        titleLabel.fontSize = 11
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: 5)
        button.addChild(titleLabel)

        subtitleLabel.text = subtitle
        subtitleLabel.fontSize = 8
        subtitleLabel.horizontalAlignmentMode = .center
        subtitleLabel.verticalAlignmentMode = .center
        subtitleLabel.position = CGPoint(x: 0, y: -8)
        button.addChild(subtitleLabel)
    }

    private func updateMapSelectorVisuals() {
        let activeBg = SKColor(red: 0.16, green: 0.44, blue: 0.72, alpha: 0.90)
        let activeStroke = SKColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1.0)
        let inactiveBg = SKColor(red: 0.06, green: 0.12, blue: 0.18, alpha: 0.65)
        let inactiveStroke = SKColor(white: 1, alpha: 0.25)

        let isTrail = (mapMode == .trailRush)
        trailRushButton.fillColor = isTrail ? activeBg : inactiveBg
        trailRushButton.strokeColor = isTrail ? activeStroke : inactiveStroke
        trailRushTitle.fontColor = isTrail ? .white : SKColor(white: 1, alpha: 0.65)
        trailRushSubtitle.fontColor = isTrail ? SKColor(red: 0.70, green: 0.92, blue: 1.0, alpha: 1.0) : SKColor(white: 1, alpha: 0.45)

        megaJumpButton.fillColor = !isTrail ? activeBg : inactiveBg
        megaJumpButton.strokeColor = !isTrail ? activeStroke : inactiveStroke
        megaJumpTitle.fontColor = !isTrail ? .white : SKColor(white: 1, alpha: 0.65)
        megaJumpSubtitle.fontColor = !isTrail ? SKColor(red: 0.70, green: 0.92, blue: 1.0, alpha: 1.0) : SKColor(white: 1, alpha: 0.45)

        hudMapLabel.text = "MAP: \(mapMode.rawValue)"
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
        distanceLabel.position = CGPoint(x: -halfWidth + 22, y: halfHeight - 28)
        speedLabel.position = CGPoint(x: halfWidth - 22, y: halfHeight - 28)
        surfaceLabel.position = CGPoint(x: 0, y: halfHeight - 24)
        hudMapButton.position = CGPoint(x: 0, y: halfHeight - 50)
        toastLabel.position = CGPoint(x: 0, y: halfHeight * 0.24)
        backControl.position = CGPoint(x: -halfWidth + 66, y: -halfHeight + 58)
        pedalControl.position = CGPoint(x: 0, y: -halfHeight + 58)
        forwardControl.position = CGPoint(x: halfWidth - 66, y: -halfHeight + 58)

        let cardWidth = min(size.width - 44, 460)
        let cardHeight: CGFloat = 194
        overlayCard.path = CGPath(
            roundedRect: CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight),
            cornerWidth: 20,
            cornerHeight: 20,
            transform: nil
        )
        overlayTitle.position = CGPoint(x: 0, y: 56)
        overlaySubtitle.position = CGPoint(x: 0, y: 30)
        mapSelector.position = CGPoint(x: 0, y: -9)
        trailRushButton.position = CGPoint(x: -74, y: 0)
        megaJumpButton.position = CGPoint(x: 74, y: 0)
        overlayPrompt.position = CGPoint(x: 0, y: -64)
    }

    // MARK: - Presentation

    private func updateHUD() {
        distanceLabel.text = "\(currentDistance)m"
        speedLabel.text = "\(currentSpeed) km/h"
        if isGrounded {
            surfaceLabel.text = "GRIP"
        } else {
            surfaceLabel.text = airborneTime >= 0.2 ? String(format: "AIR %.1fs", airborneTime) : "AIR"
        }
    }

    private func updateCamera(immediately: Bool = false) {
        guard terrainStream.levelEndX > terrainStream.levelStartX else { return }
        let lookAhead = clamp(
            GameTuning.Camera.baseLookAhead + bike.velocity.dx * GameTuning.Camera.velocityLookAheadFactor,
            GameTuning.Camera.minimumLookAhead,
            GameTuning.Camera.maximumLookAhead
        )
        let target = CGPoint(
            x: max(bike.chassisPosition.x + lookAhead, terrainStream.levelStartX + size.width * 0.44),
            y: bike.chassisPosition.y + GameTuning.Camera.verticalBias
        )
        let amount: CGFloat = immediately ? 1 : min(CGFloat(frameDelta) * GameTuning.Camera.followResponsiveness, 1)
        cameraNode.position.x += (target.x - cameraNode.position.x) * amount
        cameraNode.position.y += (target.y - cameraNode.position.y) * amount
        alpineAtmosphere.alpha = alpineBiomeBlend * 0.62
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
        overlayTitle.text = mapMode.rawValue
        overlaySubtitle.text = mapMode == .megaJump
            ? "ONE BIG DOWNHILL LEADUP & HUGE AIR JUMP"
            : "COMPOUND BIKE PHYSICS • PROCEDURAL TRAIL"
        overlayPrompt.text = "HOLD PEDAL TO RIDE  •  LEAN LEFT / RIGHT"
        updateMapSelectorVisuals()
    }

    private func showCrashOverlay(reason: CrashReason) {
        overlay.isHidden = false
        overlay.alpha = 0
        overlayTitle.text = "WIPEOUT"
        overlaySubtitle.text = "\(reason.rawValue)  •  \(currentDistance)m  •  BEST \(bestDistance)m"
        overlayPrompt.text = "TAP TO RIDE AGAIN"
        updateMapSelectorVisuals()
        overlay.run(.fadeIn(withDuration: 0.18))
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
