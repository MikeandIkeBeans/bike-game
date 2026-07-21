import SpriteKit
import UIKit

/// A deliberately small, flat-ground riding sandbox for the rear-suspension
/// topology. It shares no terrain, camera, crash, or control code with Trail
/// Ride: the only dynamic parts are the chassis, swingarm, and two wheels.
final class PlayableRearSuspensionScene: SKScene, SKPhysicsContactDelegate {
    /// Per-body relationship tracking remains correct if the flat test lane is
    /// later split into several support segments.
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

    private let ground = SKShapeNode()
    private let track = SKNode()
    private let leftEndStop = SKShapeNode()
    private let rightEndStop = SKShapeNode()
    private let chassis = SKNode()
    private let swingarm = SKNode()
    private let rearWheel = SKNode()
    private let frontWheel = SKNode()
    private let shock = SKShapeNode()

    private let titleLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let subtitleLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let metricsLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let statusLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let resetControl = SKNode()
    private let backLeanControl = SKNode()
    private let brakeControl = SKNode()
    private let pedalControl = SKNode()
    private let forwardLeanControl = SKNode()
    private let travelTrack = SKShapeNode()
    private let travelIndicator = SKShapeNode(circleOfRadius: 4)

    private var contacts = ContactBook()
    private var joints: [SKPhysicsJoint] = []
    private var pivotJoint: SKPhysicsJointPin?
    private var rearAxleJoint: SKPhysicsJointPin?
    private var frontAxleJoint: SKPhysicsJointPin?
    private var topOutJoint: SKPhysicsJointLimit?

    private var isConfigured = false
    private var lastUpdateTime: TimeInterval = 0
    private var frameDelta: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0
    private var hudElapsed: TimeInterval = 0
    private var activeTouches: [ObjectIdentifier: CGPoint] = [:]
    private var leanInput: CGFloat = 0
    private var pedalHeld = false
    private var brakeHeld = false
    private var safetyIssue: String?

    private var maximumPivotError: CGFloat = 0
    private var maximumRearAxleError: CGFloat = 0
    private var maximumFrontAxleError: CGFloat = 0
    private var maximumBodySpeed: CGFloat = 0
    private var maximumPivotReaction: CGFloat = 0
    private var maximumGroundTransitions = 0
    private var groundTransitionTimes: [TimeInterval] = []
    private var lastGroundedState = false

    private var groundY: CGFloat { GameTuning.SuspensionRide.groundY }
    private var chassisPivot: CGPoint {
        CGPoint(
            x: size.width * GameTuning.SuspensionRide.chassisHorizontalPlacement,
            y: groundY
                + GameTuning.SuspensionRide.wheelRadius
                + GameTuning.SuspensionRide.initialWheelClearance
                - sin(GameTuning.SuspensionRide.neutralSwingarmAngle)
                    * GameTuning.SuspensionRide.swingarmLength
        )
    }
    private var chassisCenter: CGPoint {
        chassisPivot - GameTuning.SuspensionRide.chassisPivotOffset
    }
    private var swingarmAxis: CGVector {
        CGVector(
            dx: cos(GameTuning.SuspensionRide.neutralSwingarmAngle),
            dy: sin(GameTuning.SuspensionRide.neutralSwingarmAngle)
        )
    }
    private var swingarmNormal: CGVector {
        CGVector(dx: -swingarmAxis.dy, dy: swingarmAxis.dx)
    }
    private var rearAxleLocal: CGPoint {
        point(along: swingarmAxis, distance: GameTuning.SuspensionRide.swingarmLength)
    }
    private var swingarmShockMountLocal: CGPoint {
        point(
            along: swingarmAxis,
            distance: GameTuning.SuspensionRide.swingarmShockMountDistance
        )
    }
    private var rearWheelSpawn: CGPoint {
        chassisPivot + CGVector(
            dx: swingarmAxis.dx * GameTuning.SuspensionRide.swingarmLength,
            dy: swingarmAxis.dy * GameTuning.SuspensionRide.swingarmLength
        )
    }
    private var frontWheelSpawn: CGPoint {
        CGPoint(
            x: chassisCenter.x + GameTuning.SuspensionRide.frontAxleOffset.x,
            y: chassisCenter.y + GameTuning.SuspensionRide.frontAxleOffset.y
        )
    }
    private var shockLength: CGFloat {
        let upper = chassis.convert(GameTuning.SuspensionRide.chassisShockMountOffset, to: self)
        let lower = swingarm.convert(swingarmShockMountLocal, to: self)
        return distance(upper, lower)
    }
    private var suspensionTravel: CGFloat {
        normalizedAngle(swingarm.zRotation - chassis.zRotation)
    }
    private var groundBodyIDs: Set<ObjectIdentifier> {
        [ground, leftEndStop, rightEndStop].compactMap { node in
            node.physicsBody.map(ObjectIdentifier.init)
        }.reduce(into: Set<ObjectIdentifier>()) { ids, id in
            ids.insert(id)
        }
    }
    private var isRearWheelGrounded: Bool {
        guard let body = rearWheel.physicsBody else { return false }
        return contacts.touches(body, anyOf: groundBodyIDs)
    }
    private var isFrontWheelGrounded: Bool {
        guard let body = frontWheel.physicsBody else { return false }
        return contacts.touches(body, anyOf: groundBodyIDs)
    }
    private var isGrounded: Bool {
        isRearWheelGrounded || isFrontWheelGrounded
    }
    private var isRideSafe: Bool {
        safetyIssue == nil
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
        backgroundColor = SKColor(red: 0.035, green: 0.055, blue: 0.075, alpha: 1)
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
        physicsWorld.contactDelegate = self

        configureScene()
        resetRide()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard isConfigured else { return }
        layoutHUD()
    }

    // update(_:) is pre-physics, so rider torque enters SpriteKit's normal
    // solver along with gravity, wheel contacts, and the suspension joints.
    override func update(_ currentTime: TimeInterval) {
        guard isConfigured else { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }

        frameDelta = min(
            max(currentTime - lastUpdateTime, 0),
            GameTuning.Simulation.maximumFrameDelta
        )
        lastUpdateTime = currentTime
        elapsedTime += frameDelta
        hudElapsed += frameDelta
        applyPlayerControls()
    }

    // Safety evaluation belongs after the solver has produced its contacts and
    // constraint state. Contact callbacks only record relationship facts.
    override func didSimulatePhysics() {
        guard isConfigured else { return }

        samplePhysicsState()
        capMotion(
            of: chassis.physicsBody,
            maximumLinearSpeed: GameTuning.SuspensionRide.maximumChassisLinearSpeed,
            maximumAngularVelocity: GameTuning.SuspensionRide.maximumChassisAngularVelocity
        )
        capMotion(
            of: swingarm.physicsBody,
            maximumLinearSpeed: GameTuning.SuspensionRide.maximumComponentLinearSpeed,
            maximumAngularVelocity: GameTuning.SuspensionRide.maximumSwingarmAngularVelocity
        )
        capMotion(
            of: rearWheel.physicsBody,
            maximumLinearSpeed: GameTuning.SuspensionRide.maximumComponentLinearSpeed,
            maximumAngularVelocity: GameTuning.SuspensionRide.maximumWheelAngularVelocity
        )
        capMotion(
            of: frontWheel.physicsBody,
            maximumLinearSpeed: GameTuning.SuspensionRide.maximumComponentLinearSpeed,
            maximumAngularVelocity: GameTuning.SuspensionRide.maximumWheelAngularVelocity
        )
        updateShockVisual()

        if hudElapsed >= GameTuning.SuspensionRide.hudRefreshInterval || !isRideSafe {
            hudElapsed = 0
            updateHUD()
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard isWheelGroundContact(contact) else { return }
        contacts.began(contact.bodyA, contact.bodyB)
    }

    func didEnd(_ contact: SKPhysicsContact) {
        guard isWheelGroundContact(contact) else { return }
        contacts.ended(contact.bodyA, contact.bodyB)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            if resetControl.calculateAccumulatedFrame().insetBy(dx: -10, dy: -10).contains(location) {
                resetRide()
                continue
            }
            guard isRideSafe else { continue }
            activeTouches[ObjectIdentifier(touch)] = location
        }
        updateControls()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRideSafe else { return }
        for touch in touches where activeTouches[ObjectIdentifier(touch)] != nil {
            activeTouches[ObjectIdentifier(touch)] = touch.location(in: self)
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
        let laneWidth = size.width / 4
        let backHeld = activeTouches.values.contains { $0.x < laneWidth }
        brakeHeld = activeTouches.values.contains { $0.x >= laneWidth && $0.x < laneWidth * 2 }
        pedalHeld = activeTouches.values.contains { $0.x >= laneWidth * 2 && $0.x < laneWidth * 3 }
        let forwardHeld = activeTouches.values.contains { $0.x >= laneWidth * 3 }

        // SpriteKit is y-up and the bike faces +x: positive torque pitches the
        // front up (back lean), while negative torque pitches it forward.
        switch (backHeld, forwardHeld) {
        case (true, false): leanInput = 1
        case (false, true): leanInput = -1
        default: leanInput = 0
        }

        backLeanControl.setScale(backHeld ? 1.08 : 1)
        brakeControl.setScale(brakeHeld ? 1.08 : 1)
        pedalControl.setScale(pedalHeld && !brakeHeld ? 1.08 : 1)
        forwardLeanControl.setScale(forwardHeld ? 1.08 : 1)
    }

    private func applyPlayerControls() {
        guard isRideSafe,
              let chassisBody = chassis.physicsBody,
              let rearWheelBody = rearWheel.physicsBody else { return }

        if isGrounded, !pedalHeld {
            chassisBody.applyForce(CGVector(
                dx: -chassisBody.velocity.dx
                    * GameTuning.SuspensionRide.coastingDragForcePerSpeed,
                dy: 0
            ))
        }

        if isRearWheelGrounded {
            if brakeHeld {
                let direction: CGFloat = chassisBody.velocity.dx >= 0 ? -1 : 1
                rearWheelBody.applyForce(CGVector(
                    dx: direction * GameTuning.SuspensionRide.brakeForce,
                    dy: 0
                ))
            } else if pedalHeld {
                let forwardSpeed = max(chassisBody.velocity.dx, 0)
                let assist = clamp(
                    1 - forwardSpeed / GameTuning.SuspensionRide.pedalAssistSpeed,
                    0,
                    1
                )
                let availableRun = rightEndStop.position.x
                    - (frontWheel.position.x + GameTuning.SuspensionRide.wheelRadius)
                let boundaryFraction = clamp(
                    availableRun / GameTuning.SuspensionRide.driveBoundaryFadeDistance,
                    0,
                    1
                )
                rearWheelBody.applyForce(CGVector(
                    dx: GameTuning.SuspensionRide.pedalDriveForce * assist * boundaryFraction,
                    dy: 0
                ))
                rearWheelBody.isResting = false
            }
        }

        let speed = abs(chassisBody.velocity.dx)
        let leanFraction = clamp(
            (speed - GameTuning.SuspensionRide.leanMinimumSpeed)
                / (GameTuning.SuspensionRide.leanFullSpeed
                    - GameTuning.SuspensionRide.leanMinimumSpeed),
            0,
            1
        )
        let targetAngle = leanInput
            * GameTuning.SuspensionRide.leanMaximumOffset
            * leanFraction
        let response = leanInput == 0
            ? GameTuning.SuspensionRide.uprightResponseTorque
            : GameTuning.SuspensionRide.leanResponseTorque * max(leanFraction, 0.25)
        let damping = leanInput == 0
            ? GameTuning.SuspensionRide.uprightDampingTorque
            : GameTuning.SuspensionRide.leanDampingTorque
        let desiredTorque = normalizedAngle(targetAngle - chassis.zRotation) * response
            - chassisBody.angularVelocity * damping
        chassisBody.applyTorque(clamp(
            desiredTorque,
            -GameTuning.SuspensionRide.maximumLeanTorque,
            GameTuning.SuspensionRide.maximumLeanTorque
        ))
    }

    // MARK: - Construction

    private func configureScene() {
        buildGround()
        buildTrack()
        buildEndStops()
        buildChassis()
        buildSwingarm()
        buildRearWheel()
        buildFrontWheel()

        [ground, track, leftEndStop, rightEndStop, chassis, swingarm, rearWheel, frontWheel, shock]
            .forEach(addChild)
        installJoints()
        updateShockVisual()
        addHUD()
    }

    private func buildGround() {
        let start = CGPoint(x: -GameTuning.SuspensionRide.groundOverhang, y: groundY)
        let end = CGPoint(x: size.width + GameTuning.SuspensionRide.groundOverhang, y: groundY)
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        ground.path = path
        ground.strokeColor = SKColor(red: 0.56, green: 0.72, blue: 0.70, alpha: 1)
        ground.lineWidth = 4
        ground.lineCap = .round
        ground.zPosition = 1

        let body = SKPhysicsBody(edgeFrom: start, to: end)
        body.isDynamic = false
        body.friction = GameTuning.SuspensionRide.wheelFriction
        body.restitution = GameTuning.SuspensionRide.wheelRestitution
        body.categoryBitMask = PhysicsCategory.suspensionRigGround
        body.collisionBitMask = PhysicsCategory.suspensionRigWheel
            | PhysicsCategory.suspensionRigFrontWheel
        body.contactTestBitMask = PhysicsCategory.suspensionRigWheel
            | PhysicsCategory.suspensionRigFrontWheel
        ground.physicsBody = body
    }

    private func buildTrack() {
        track.zPosition = 0

        let guideY = groundY + GameTuning.SuspensionRide.wheelRadius + 18
        let guide = SKShapeNode()
        let guidePath = CGMutablePath()
        guidePath.move(to: CGPoint(x: 22, y: guideY))
        guidePath.addLine(to: CGPoint(x: size.width - 22, y: guideY))
        guide.path = guidePath
        guide.strokeColor = SKColor(red: 0.24, green: 0.40, blue: 0.46, alpha: 0.34)
        guide.lineWidth = 1.5
        track.addChild(guide)

        for x in stride(from: CGFloat(30), through: size.width - 30, by: 60) {
            let marker = SKShapeNode()
            let markerPath = CGMutablePath()
            markerPath.move(to: CGPoint(x: x, y: groundY - 8))
            markerPath.addLine(to: CGPoint(x: x, y: groundY + 8))
            marker.path = markerPath
            marker.strokeColor = SKColor(red: 0.26, green: 0.42, blue: 0.47, alpha: 0.46)
            marker.lineWidth = 1
            track.addChild(marker)
        }
    }

    private func buildEndStops() {
        configureEndStop(
            leftEndStop,
            x: GameTuning.SuspensionRide.endStopInset
        )
        configureEndStop(
            rightEndStop,
            x: size.width - GameTuning.SuspensionRide.endStopInset
        )
    }

    private func configureEndStop(_ endStop: SKShapeNode, x: CGFloat) {
        let height = GameTuning.SuspensionRide.endStopHeight
        let path = CGPath(
            roundedRect: CGRect(x: -4, y: 0, width: 8, height: height),
            cornerWidth: 4,
            cornerHeight: 4,
            transform: nil
        )
        endStop.path = path
        endStop.position = CGPoint(x: x, y: groundY)
        endStop.fillColor = SKColor(red: 0.20, green: 0.38, blue: 0.44, alpha: 0.88)
        endStop.strokeColor = SKColor(red: 0.63, green: 0.91, blue: 0.88, alpha: 0.70)
        endStop.lineWidth = 1
        endStop.zPosition = 1

        let body = SKPhysicsBody(
            rectangleOf: CGSize(width: 8, height: height),
            center: CGPoint(x: 0, y: height / 2)
        )
        body.isDynamic = false
        body.friction = GameTuning.SuspensionRide.wheelFriction
        body.restitution = GameTuning.SuspensionRide.wheelRestitution
        body.categoryBitMask = PhysicsCategory.suspensionRigGround
        body.collisionBitMask = PhysicsCategory.suspensionRigWheel
            | PhysicsCategory.suspensionRigFrontWheel
        body.contactTestBitMask = PhysicsCategory.suspensionRigWheel
            | PhysicsCategory.suspensionRigFrontWheel
        endStop.physicsBody = body
    }

    private func buildChassis() {
        chassis.position = chassisCenter
        chassis.zPosition = 4

        let size = GameTuning.SuspensionRide.chassisSize
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let shellPath = CGMutablePath()
        shellPath.move(to: CGPoint(x: -halfWidth, y: -halfHeight))
        shellPath.addLine(to: CGPoint(x: halfWidth, y: -halfHeight + 10))
        shellPath.addLine(to: CGPoint(x: halfWidth - 24, y: halfHeight))
        shellPath.addLine(to: CGPoint(x: -halfWidth + 28, y: halfHeight))
        shellPath.closeSubpath()

        let shell = SKShapeNode(path: shellPath)
        shell.fillColor = SKColor(red: 0.13, green: 0.22, blue: 0.30, alpha: 1)
        shell.strokeColor = SKColor(red: 0.42, green: 0.72, blue: 0.79, alpha: 1)
        shell.lineWidth = 3
        chassis.addChild(shell)

        let battery = SKShapeNode(rectOf: CGSize(width: 82, height: 20), cornerRadius: 4)
        battery.fillColor = SKColor(red: 0.17, green: 0.34, blue: 0.42, alpha: 1)
        battery.strokeColor = SKColor(red: 0.63, green: 0.91, blue: 0.88, alpha: 0.82)
        battery.lineWidth = 2
        battery.position = CGPoint(x: 6, y: 8)
        chassis.addChild(battery)

        let pivotMarker = SKShapeNode(circleOfRadius: 8)
        pivotMarker.fillColor = SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
        pivotMarker.strokeColor = SKColor(white: 0.92, alpha: 1)
        pivotMarker.lineWidth = 2
        pivotMarker.position = GameTuning.SuspensionRide.chassisPivotOffset
        chassis.addChild(pivotMarker)

        let shockMarker = SKShapeNode(circleOfRadius: 5)
        shockMarker.fillColor = SKColor(white: 0.88, alpha: 1)
        shockMarker.strokeColor = .clear
        shockMarker.position = GameTuning.SuspensionRide.chassisShockMountOffset
        chassis.addChild(shockMarker)

        let forkCrown = CGPoint(x: 62, y: 23)
        let forkPath = CGMutablePath()
        forkPath.move(to: forkCrown)
        forkPath.addLine(to: GameTuning.SuspensionRide.frontAxleOffset)
        forkPath.move(to: CGPoint(x: forkCrown.x - 10, y: forkCrown.y + 4))
        forkPath.addLine(to: CGPoint(
            x: GameTuning.SuspensionRide.frontAxleOffset.x - 10,
            y: GameTuning.SuspensionRide.frontAxleOffset.y + 4
        ))
        let fork = SKShapeNode(path: forkPath)
        fork.strokeColor = SKColor(red: 0.63, green: 0.91, blue: 0.88, alpha: 1)
        fork.lineWidth = 5
        fork.lineCap = .round
        chassis.addChild(fork)

        let handlebar = SKShapeNode(rectOf: CGSize(width: 26, height: 4), cornerRadius: 2)
        handlebar.fillColor = SKColor(white: 0.88, alpha: 1)
        handlebar.strokeColor = .clear
        handlebar.position = CGPoint(x: 72, y: 36)
        handlebar.zRotation = 0.16
        chassis.addChild(handlebar)

        let rider = SKNode()
        let torso = SKShapeNode(rectOf: CGSize(width: 15, height: 38), cornerRadius: 7)
        torso.fillColor = SKColor(red: 0.96, green: 0.31, blue: 0.21, alpha: 1)
        torso.strokeColor = .clear
        torso.position = CGPoint(x: -3, y: 63)
        torso.zRotation = -0.28
        rider.addChild(torso)
        let head = SKShapeNode(circleOfRadius: 10)
        head.fillColor = SKColor(red: 1.0, green: 0.75, blue: 0.52, alpha: 1)
        head.strokeColor = .clear
        head.position = CGPoint(x: 7, y: 89)
        rider.addChild(head)
        let helmet = SKShapeNode(circleOfRadius: 11)
        helmet.fillColor = SKColor(red: 0.16, green: 0.25, blue: 0.42, alpha: 1)
        helmet.strokeColor = .clear
        helmet.position = CGPoint(x: 7, y: 94)
        helmet.yScale = 0.60
        rider.addChild(helmet)
        let armPath = CGMutablePath()
        armPath.move(to: CGPoint(x: 1, y: 70))
        armPath.addLine(to: CGPoint(x: 66, y: 39))
        let arm = SKShapeNode(path: armPath)
        arm.strokeColor = SKColor(red: 0.96, green: 0.31, blue: 0.21, alpha: 1)
        arm.lineWidth = 6
        arm.lineCap = .round
        rider.addChild(arm)
        chassis.addChild(rider)

        let body = SKPhysicsBody(polygonFrom: shellPath)
        body.mass = GameTuning.SuspensionRide.chassisMass
        body.linearDamping = GameTuning.SuspensionRide.chassisLinearDamping
        body.angularDamping = GameTuning.SuspensionRide.chassisAngularDamping
        body.affectedByGravity = true
        body.allowsRotation = true
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = PhysicsCategory.suspensionRigChassis
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        chassis.physicsBody = body
    }

    private func buildSwingarm() {
        swingarm.position = chassisPivot
        swingarm.zPosition = 5

        let path = swingarmPath()
        let arm = SKShapeNode(path: path)
        arm.fillColor = SKColor(red: 0.19, green: 0.49, blue: 0.54, alpha: 1)
        arm.strokeColor = SKColor(red: 0.63, green: 0.91, blue: 0.88, alpha: 1)
        arm.lineWidth = 2
        swingarm.addChild(arm)

        let lowerShockMarker = SKShapeNode(circleOfRadius: 5)
        lowerShockMarker.fillColor = SKColor(white: 0.88, alpha: 1)
        lowerShockMarker.strokeColor = .clear
        lowerShockMarker.position = swingarmShockMountLocal
        swingarm.addChild(lowerShockMarker)

        let axlePlate = SKShapeNode(circleOfRadius: 11)
        axlePlate.fillColor = SKColor(red: 0.12, green: 0.24, blue: 0.29, alpha: 1)
        axlePlate.strokeColor = SKColor(red: 0.63, green: 0.91, blue: 0.88, alpha: 1)
        axlePlate.lineWidth = 2
        axlePlate.position = rearAxleLocal
        swingarm.addChild(axlePlate)

        let body = SKPhysicsBody(polygonFrom: path)
        body.mass = GameTuning.SuspensionRide.swingarmMass
        body.linearDamping = GameTuning.SuspensionRide.componentLinearDamping
        body.angularDamping = GameTuning.SuspensionRide.swingarmAngularDamping
        body.affectedByGravity = true
        body.allowsRotation = true
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = PhysicsCategory.suspensionRigSwingarm
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        swingarm.physicsBody = body
    }

    private func buildRearWheel() {
        configureWheel(
            rearWheel,
            at: rearWheelSpawn,
            mass: GameTuning.SuspensionRide.rearWheelMass,
            category: PhysicsCategory.suspensionRigWheel,
            accent: SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
        )
    }

    private func buildFrontWheel() {
        configureWheel(
            frontWheel,
            at: frontWheelSpawn,
            mass: GameTuning.SuspensionRide.frontWheelMass,
            category: PhysicsCategory.suspensionRigFrontWheel,
            accent: SKColor(red: 0.42, green: 0.72, blue: 0.96, alpha: 1)
        )
    }

    private func configureWheel(
        _ wheel: SKNode,
        at position: CGPoint,
        mass: CGFloat,
        category: UInt32,
        accent: SKColor
    ) {
        wheel.position = position
        wheel.zPosition = 6

        let tire = SKShapeNode(circleOfRadius: GameTuning.SuspensionRide.wheelRadius)
        tire.fillColor = SKColor(red: 0.025, green: 0.040, blue: 0.055, alpha: 1)
        tire.strokeColor = SKColor(red: 0.79, green: 0.88, blue: 0.88, alpha: 1)
        tire.lineWidth = 3
        wheel.addChild(tire)

        let hub = SKShapeNode(circleOfRadius: 7)
        hub.fillColor = accent
        hub.strokeColor = .clear
        wheel.addChild(hub)

        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 4) {
            let spokePath = CGMutablePath()
            spokePath.move(to: .zero)
            spokePath.addLine(to: CGPoint(
                x: cos(angle) * (GameTuning.SuspensionRide.wheelRadius - 5),
                y: sin(angle) * (GameTuning.SuspensionRide.wheelRadius - 5)
            ))
            let spoke = SKShapeNode(path: spokePath)
            spoke.strokeColor = SKColor(white: 0.80, alpha: 0.54)
            spoke.lineWidth = 1
            wheel.addChild(spoke)
        }

        let body = SKPhysicsBody(circleOfRadius: GameTuning.SuspensionRide.wheelRadius)
        body.mass = mass
        body.linearDamping = GameTuning.SuspensionRide.componentLinearDamping
        body.angularDamping = GameTuning.SuspensionRide.wheelAngularDamping
        body.friction = GameTuning.SuspensionRide.wheelFriction
        body.restitution = GameTuning.SuspensionRide.wheelRestitution
        body.affectedByGravity = true
        body.allowsRotation = true
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = category
        body.collisionBitMask = PhysicsCategory.suspensionRigGround
        body.contactTestBitMask = PhysicsCategory.suspensionRigGround
        wheel.physicsBody = body
    }

    private func installJoints() {
        guard let chassisBody = chassis.physicsBody,
              let swingarmBody = swingarm.physicsBody,
              let rearWheelBody = rearWheel.physicsBody,
              let frontWheelBody = frontWheel.physicsBody else {
            assertionFailure("Playable suspension bike needs all four bodies before adding joints.")
            return
        }

        let pivot = SKPhysicsJointPin.joint(
            withBodyA: chassisBody,
            bodyB: swingarmBody,
            anchor: chassis.convert(GameTuning.SuspensionRide.chassisPivotOffset, to: self)
        )
        pivot.shouldEnableLimits = true
        pivot.lowerAngleLimit = GameTuning.SuspensionRide.lowerTravelAngle
        pivot.upperAngleLimit = GameTuning.SuspensionRide.upperTravelAngle
        pivot.frictionTorque = GameTuning.SuspensionRide.pivotFrictionTorque

        let rearAxle = SKPhysicsJointPin.joint(
            withBodyA: swingarmBody,
            bodyB: rearWheelBody,
            anchor: swingarm.convert(rearAxleLocal, to: self)
        )

        let frontAxle = SKPhysicsJointPin.joint(
            withBodyA: chassisBody,
            bodyB: frontWheelBody,
            anchor: chassis.convert(GameTuning.SuspensionRide.frontAxleOffset, to: self)
        )

        let upperAnchor = chassis.convert(GameTuning.SuspensionRide.chassisShockMountOffset, to: self)
        let lowerAnchor = swingarm.convert(swingarmShockMountLocal, to: self)
        let spring = SKPhysicsJointSpring.joint(
            withBodyA: chassisBody,
            bodyB: swingarmBody,
            anchorA: upperAnchor,
            anchorB: lowerAnchor
        )
        spring.frequency = GameTuning.SuspensionRide.springFrequency
        spring.damping = GameTuning.SuspensionRide.springDamping

        let topOut = SKPhysicsJointLimit.joint(
            withBodyA: chassisBody,
            bodyB: swingarmBody,
            anchorA: upperAnchor,
            anchorB: lowerAnchor
        )
        topOut.maxLength = shockLength + GameTuning.SuspensionRide.topOutStrapExtraLength

        pivotJoint = pivot
        rearAxleJoint = rearAxle
        frontAxleJoint = frontAxle
        topOutJoint = topOut
        joints = [pivot, rearAxle, frontAxle, spring, topOut]
        joints.forEach { physicsWorld.add($0) }
    }

    // MARK: - Physics safety and reset

    private func samplePhysicsState() {
        let pivotError = distance(
            chassis.convert(GameTuning.SuspensionRide.chassisPivotOffset, to: self),
            swingarm.convert(.zero, to: self)
        )
        let rearAxleError = distance(
            swingarm.convert(rearAxleLocal, to: self),
            rearWheel.convert(.zero, to: self)
        )
        let frontAxleError = distance(
            chassis.convert(GameTuning.SuspensionRide.frontAxleOffset, to: self),
            frontWheel.convert(.zero, to: self)
        )
        maximumPivotError = max(maximumPivotError, pivotError)
        maximumRearAxleError = max(maximumRearAxleError, rearAxleError)
        maximumFrontAxleError = max(maximumFrontAxleError, frontAxleError)
        maximumPivotReaction = max(maximumPivotReaction, reactionMagnitude(of: pivotJoint))
        maximumBodySpeed = max(
            maximumBodySpeed,
            vectorLength(chassis.physicsBody?.velocity ?? .zero),
            vectorLength(swingarm.physicsBody?.velocity ?? .zero),
            vectorLength(rearWheel.physicsBody?.velocity ?? .zero),
            vectorLength(frontWheel.physicsBody?.velocity ?? .zero)
        )
        recordGroundTransitions()

        guard bodiesAreFinite else {
            recordSafetyIssue("NON-FINITE STATE")
            return
        }
        if pivotError > GameTuning.SuspensionRide.maximumPivotAnchorError {
            recordSafetyIssue("PIVOT ERROR")
        }
        if rearAxleError > GameTuning.SuspensionRide.maximumRearAxleAnchorError {
            recordSafetyIssue("REAR AXLE ERROR")
        }
        if frontAxleError > GameTuning.SuspensionRide.maximumFrontAxleAnchorError {
            recordSafetyIssue("FRONT AXLE ERROR")
        }
        if [rearWheel, frontWheel].contains(where: {
            $0.position.y - GameTuning.SuspensionRide.wheelRadius
                < groundY - GameTuning.SuspensionRide.maximumWheelPenetration
        }) {
            recordSafetyIssue("GROUND PENETRATION")
        }

        let leftmost = min(chassis.position.x, swingarm.position.x, rearWheel.position.x, frontWheel.position.x)
        let rightmost = max(chassis.position.x, swingarm.position.x, rearWheel.position.x, frontWheel.position.x)
        if rightmost < -GameTuning.SuspensionRide.visibleLaneMargin
            || leftmost > size.width + GameTuning.SuspensionRide.visibleLaneMargin {
            recordSafetyIssue("LEFT TEST LANE")
        }
    }

    private func recordGroundTransitions() {
        let grounded = isGrounded
        guard grounded != lastGroundedState else { return }

        lastGroundedState = grounded
        groundTransitionTimes.append(elapsedTime)
        let windowStart = elapsedTime - 0.5
        groundTransitionTimes.removeAll { $0 < windowStart }
        maximumGroundTransitions = max(maximumGroundTransitions, groundTransitionTimes.count)
        if groundTransitionTimes.count
            > GameTuning.SuspensionRide.maximumGroundTransitionsPerHalfSecond {
            recordSafetyIssue("GROUND CHATTER")
        }
    }

    private var bodiesAreFinite: Bool {
        [chassis, swingarm, rearWheel, frontWheel].allSatisfy { node in
            guard let body = node.physicsBody else { return false }
            return node.position.x.isFinite
                && node.position.y.isFinite
                && node.zRotation.isFinite
                && body.velocity.dx.isFinite
                && body.velocity.dy.isFinite
                && body.angularVelocity.isFinite
        }
    }

    private func capMotion(
        of body: SKPhysicsBody?,
        maximumLinearSpeed: CGFloat,
        maximumAngularVelocity: CGFloat
    ) {
        guard let body else { return }
        let speed = vectorLength(body.velocity)
        guard speed.isFinite, body.angularVelocity.isFinite else {
            recordSafetyIssue("NON-FINITE MOTION")
            return
        }

        if speed > maximumLinearSpeed {
            recordSafetyIssue("LINEAR SAFETY CAP")
            let scale = maximumLinearSpeed / speed
            body.velocity = CGVector(dx: body.velocity.dx * scale, dy: body.velocity.dy * scale)
        }
        if abs(body.angularVelocity) > maximumAngularVelocity {
            recordSafetyIssue("ANGULAR SAFETY CAP")
            body.angularVelocity = min(
                maximumAngularVelocity,
                max(-maximumAngularVelocity, body.angularVelocity)
            )
        }
    }

    private func recordSafetyIssue(_ reason: String) {
        guard safetyIssue == nil else { return }
        safetyIssue = reason
        activeTouches.removeAll(keepingCapacity: true)
        leanInput = 0
        pedalHeld = false
        brakeHeld = false
    }

    private func resetRide() {
        contacts.removeAll()
        activeTouches.removeAll(keepingCapacity: true)
        leanInput = 0
        pedalHeld = false
        brakeHeld = false
        safetyIssue = nil
        elapsedTime = 0
        hudElapsed = GameTuning.SuspensionRide.hudRefreshInterval
        maximumPivotError = 0
        maximumRearAxleError = 0
        maximumFrontAxleError = 0
        maximumBodySpeed = 0
        maximumPivotReaction = 0
        maximumGroundTransitions = 0
        groundTransitionTimes.removeAll(keepingCapacity: true)
        lastGroundedState = false

        chassis.position = chassisCenter
        chassis.zRotation = 0
        swingarm.position = chassisPivot
        swingarm.zRotation = 0
        rearWheel.position = rearWheelSpawn
        rearWheel.zRotation = 0
        frontWheel.position = frontWheelSpawn
        frontWheel.zRotation = 0

        [chassis, swingarm, rearWheel, frontWheel].forEach { node in
            guard let body = node.physicsBody else { return }
            body.isDynamic = true
            body.velocity = .zero
            body.angularVelocity = 0
            body.isResting = false
        }
        updateControls()
        updateShockVisual()
        updateHUD()
    }

    // MARK: - HUD

    private func addHUD() {
        titleLabel.text = "REAR SUSPENSION RIDE"
        titleLabel.fontSize = 20
        titleLabel.fontColor = SKColor(white: 0.91, alpha: 1)
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.zPosition = 10
        addChild(titleLabel)

        subtitleLabel.text = "flat ground  •  live rear suspension  •  no hill or camera"
        subtitleLabel.fontSize = 12
        subtitleLabel.fontColor = SKColor(white: 0.68, alpha: 1)
        subtitleLabel.horizontalAlignmentMode = .left
        subtitleLabel.zPosition = 10
        addChild(subtitleLabel)

        metricsLabel.fontSize = 11
        metricsLabel.fontColor = SKColor(white: 0.76, alpha: 1)
        metricsLabel.horizontalAlignmentMode = .left
        metricsLabel.zPosition = 10
        addChild(metricsLabel)

        statusLabel.fontSize = 12
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.zPosition = 10
        addChild(statusLabel)

        configureSmallControl(resetControl, title: "RESET", subtitle: "RIDE")
        resetControl.zPosition = 11
        addChild(resetControl)

        configureControl(backLeanControl, title: "LEAN", subtitle: "BACK")
        configureControl(brakeControl, title: "BRAKE", subtitle: "REAR")
        configureControl(pedalControl, title: "PEDAL", subtitle: "DRIVE")
        configureControl(forwardLeanControl, title: "LEAN", subtitle: "FORWARD")
        [backLeanControl, brakeControl, pedalControl, forwardLeanControl].forEach {
            $0.zPosition = 11
            addChild($0)
        }

        let trackX = size.width - 24
        let trackPath = CGMutablePath()
        trackPath.move(to: CGPoint(x: trackX, y: 112))
        trackPath.addLine(to: CGPoint(x: trackX, y: 186))
        travelTrack.path = trackPath
        travelTrack.strokeColor = SKColor(white: 0.70, alpha: 0.44)
        travelTrack.lineWidth = 3
        travelTrack.lineCap = .round
        travelTrack.zPosition = 10
        addChild(travelTrack)

        travelIndicator.fillColor = SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
        travelIndicator.strokeColor = SKColor(white: 0.94, alpha: 1)
        travelIndicator.lineWidth = 1
        travelIndicator.zPosition = 11
        addChild(travelIndicator)

        layoutHUD()
    }

    private func configureControl(_ control: SKNode, title: String, subtitle: String) {
        let circle = SKShapeNode(circleOfRadius: 24)
        circle.fillColor = SKColor(red: 0.05, green: 0.12, blue: 0.17, alpha: 0.72)
        circle.strokeColor = SKColor(white: 1, alpha: 0.25)
        circle.lineWidth = 1.2
        control.addChild(circle)

        let titleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        titleLabel.text = title
        titleLabel.fontSize = 7.5
        titleLabel.fontColor = SKColor(white: 1, alpha: 0.92)
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position.y = 4
        control.addChild(titleLabel)

        let subtitleLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        subtitleLabel.text = subtitle
        subtitleLabel.fontSize = 6.5
        subtitleLabel.fontColor = SKColor(white: 1, alpha: 0.66)
        subtitleLabel.horizontalAlignmentMode = .center
        subtitleLabel.verticalAlignmentMode = .center
        subtitleLabel.position.y = -8
        control.addChild(subtitleLabel)
    }

    private func configureSmallControl(_ control: SKNode, title: String, subtitle: String) {
        let background = SKShapeNode(rectOf: CGSize(width: 56, height: 32), cornerRadius: 8)
        background.fillColor = SKColor(red: 0.13, green: 0.26, blue: 0.31, alpha: 0.88)
        background.strokeColor = SKColor(white: 1, alpha: 0.25)
        background.lineWidth = 1
        control.addChild(background)

        let titleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        titleLabel.text = title
        titleLabel.fontSize = 8
        titleLabel.fontColor = .white
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position.y = 5
        control.addChild(titleLabel)

        let subtitleLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        subtitleLabel.text = subtitle
        subtitleLabel.fontSize = 6.5
        subtitleLabel.fontColor = SKColor(white: 1, alpha: 0.66)
        subtitleLabel.horizontalAlignmentMode = .center
        subtitleLabel.verticalAlignmentMode = .center
        subtitleLabel.position.y = -7
        control.addChild(subtitleLabel)
    }

    private func layoutHUD() {
        titleLabel.position = CGPoint(x: 24, y: size.height - 36)
        subtitleLabel.position = CGPoint(x: 25, y: size.height - 57)
        metricsLabel.position = CGPoint(x: 24, y: size.height - 82)
        statusLabel.position = CGPoint(x: 24, y: size.height - 105)
        resetControl.position = CGPoint(x: size.width - 58, y: size.height - 46)

        let controlY: CGFloat = 31
        backLeanControl.position = CGPoint(x: size.width * 0.125, y: controlY)
        brakeControl.position = CGPoint(x: size.width * 0.375, y: controlY)
        pedalControl.position = CGPoint(x: size.width * 0.625, y: controlY)
        forwardLeanControl.position = CGPoint(x: size.width * 0.875, y: controlY)
    }

    private func updateHUD() {
        let speed = chassis.physicsBody.map { vectorLength($0.velocity) } ?? 0
        metricsLabel.text = String(
            format: "speed %3.0f  travel %+0.3f  shock %3.0f  joint P %.1f / R %.1f / F %.1f  %@",
            Double(speed),
            Double(suspensionTravel),
            Double(shockLength),
            Double(maximumPivotError),
            Double(maximumRearAxleError),
            Double(maximumFrontAxleError),
            isRearWheelGrounded && isFrontWheelGrounded ? "BOTH" : isGrounded ? "ONE" : "AIR"
        )

        if let safetyIssue {
            statusLabel.text = "RESET REQUIRED  •  \(safetyIssue)"
            statusLabel.fontColor = SKColor(red: 1.0, green: 0.50, blue: 0.42, alpha: 1)
        } else {
            statusLabel.text = "RIDE  •  LEAN BACK / BRAKE / PEDAL / LEAN FORWARD"
            statusLabel.fontColor = SKColor(red: 0.63, green: 0.91, blue: 0.87, alpha: 1)
        }

        let range = GameTuning.SuspensionRide.upperTravelAngle
            - GameTuning.SuspensionRide.lowerTravelAngle
        let fraction = min(
            1,
            max(0, (suspensionTravel - GameTuning.SuspensionRide.lowerTravelAngle) / range)
        )
        travelIndicator.position = CGPoint(
            x: size.width - 24,
            y: 112 + (186 - 112) * fraction
        )
    }

    // MARK: - Visual suspension

    private func updateShockVisual() {
        let upper = chassis.convert(GameTuning.SuspensionRide.chassisShockMountOffset, to: self)
        let lower = swingarm.convert(swingarmShockMountLocal, to: self)
        let dx = lower.x - upper.x
        let dy = lower.y - upper.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return }

        let axis = CGVector(dx: dx / length, dy: dy / length)
        let normal = CGVector(dx: -axis.dy, dy: axis.dx)
        let leadLength = min(CGFloat(10), length / 4)
        let coilStart = upper + axis * leadLength
        let coilEnd = lower - axis * leadLength
        let coilLength = distance(coilStart, coilEnd)

        let path = CGMutablePath()
        path.move(to: upper)
        path.addLine(to: coilStart)
        for index in 1...7 {
            let fraction = CGFloat(index) / 8
            let offset = index.isMultiple(of: 2) ? CGFloat(-7) : CGFloat(7)
            path.addLine(to: CGPoint(
                x: coilStart.x + axis.dx * coilLength * fraction + normal.dx * offset,
                y: coilStart.y + axis.dy * coilLength * fraction + normal.dy * offset
            ))
        }
        path.addLine(to: coilEnd)
        path.addLine(to: lower)

        shock.path = path
        shock.strokeColor = SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
        shock.lineWidth = 3
        shock.lineCap = .round
        shock.lineJoin = .round
        shock.zPosition = 7
    }

    private func swingarmPath() -> CGPath {
        let halfThickness = GameTuning.SuspensionRide.swingarmThickness / 2
        let offset = swingarmNormal * halfThickness
        let end = point(along: swingarmAxis, distance: GameTuning.SuspensionRide.swingarmLength)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: offset.dx, y: offset.dy))
        path.addLine(to: end + offset)
        path.addLine(to: end - offset)
        path.addLine(to: CGPoint(x: -offset.dx, y: -offset.dy))
        path.closeSubpath()
        return path
    }

    // MARK: - Helpers

    private func isWheelGroundContact(_ contact: SKPhysicsContact) -> Bool {
        matches(contact, first: PhysicsCategory.suspensionRigWheel, second: PhysicsCategory.suspensionRigGround)
            || matches(
                contact,
                first: PhysicsCategory.suspensionRigFrontWheel,
                second: PhysicsCategory.suspensionRigGround
            )
    }

    private func matches(_ contact: SKPhysicsContact, first: UInt32, second: UInt32) -> Bool {
        let firstMatchesA = contact.bodyA.categoryBitMask & first != 0
        let secondMatchesB = contact.bodyB.categoryBitMask & second != 0
        let secondMatchesA = contact.bodyA.categoryBitMask & second != 0
        let firstMatchesB = contact.bodyB.categoryBitMask & first != 0
        return (firstMatchesA && secondMatchesB) || (secondMatchesA && firstMatchesB)
    }

    private func reactionMagnitude(of joint: SKPhysicsJoint?) -> CGFloat {
        guard let joint else { return 0 }
        return vectorLength(joint.reactionForce)
    }

    private func vectorLength(_ vector: CGVector) -> CGFloat {
        hypot(vector.dx, vector.dy)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func point(along vector: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: vector.dx * distance, y: vector.dy * distance)
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(upper, max(lower, value))
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var result = angle
        while result > .pi { result -= .pi * 2 }
        while result < -.pi { result += .pi * 2 }
        return result
    }
}

private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x - rhs.dx, y: lhs.y - rhs.dy)
    }
}

private extension CGVector {
    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }
}
