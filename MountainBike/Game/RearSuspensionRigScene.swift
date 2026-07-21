import Foundation
import SpriteKit
import UIKit

/// A self-contained quarter-bike durability lab. It deliberately keeps the
/// hill, front wheel, rider input, and crash handling out of the experiment:
/// a fixed chassis pivot, swingarm, axle, spring/damper, and flat-ground
/// rear wheel are all that can respond to the automated load program.
final class RearSuspensionRigScene: SKScene, SKPhysicsContactDelegate {
    private enum StressState {
        case settling
        case running
        case coasting
        case passed
        case failed
    }

    /// Tracks body relationships by identity, so a wheel-ground state stays
    /// correct if the lab later grows more than one flat-ground segment.
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
    private let testStand = SKNode()
    private let chassis = SKNode()
    private let swingarm = SKNode()
    private let rearWheel = SKNode()
    private let shock = SKShapeNode()
    private let bumpActuator = SKShapeNode()

    private let phaseLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let metricsLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let resultLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let travelTrack = SKShapeNode()
    private let travelIndicator = SKShapeNode(circleOfRadius: 5)

    private var contacts = ContactBook()
    private var isConfigured = false
    private var suspensionJoints: [SKPhysicsJoint] = []
    private var pivotJoint: SKPhysicsJointPin?
    private var topOutJoint: SKPhysicsJointLimit?

    private var lastUpdateTime: TimeInterval = 0
    private var frameDelta: TimeInterval = 0
    private var stressElapsed: TimeInterval = 0
    private var coastingStartedAt: TimeInterval?
    private var stableSince: TimeInterval?
    private var stressState: StressState = .settling
    private var baselineArmAngle: CGFloat?
    private var baselineShockLength: CGFloat?
    private var activePhase = "SETTLING"
    private var activeAxleForce = CGVector.zero
    private var failureReason: String?

    private var maximumPivotError: CGFloat = 0
    private var maximumAxleError: CGFloat = 0
    private var maximumPivotReaction: CGFloat = 0
    private var maximumTopOutReaction: CGFloat = 0
    private var maximumBodySpeed: CGFloat = 0
    private var maximumGroundTransitions = 0
    private var groundTransitionTimes: [TimeInterval] = []
    private var lastGroundedState = false
    private var armStopReached = false
    private var hudElapsed: TimeInterval = 0

    private var groundY: CGFloat { GameTuning.SuspensionRig.groundY }
    private var chassisPivot: CGPoint {
        CGPoint(
            x: size.width * GameTuning.SuspensionRig.chassisHorizontalPlacement,
            y: groundY
                + GameTuning.SuspensionRig.wheelRadius
                + GameTuning.SuspensionRig.initialWheelClearance
                - sin(GameTuning.SuspensionRig.neutralSwingarmAngle)
                    * GameTuning.SuspensionRig.swingarmLength
        )
    }
    private var chassisCenter: CGPoint {
        chassisPivot - GameTuning.SuspensionRig.chassisPivotOffset
    }
    private var swingarmAxis: CGVector {
        CGVector(
            dx: cos(GameTuning.SuspensionRig.neutralSwingarmAngle),
            dy: sin(GameTuning.SuspensionRig.neutralSwingarmAngle)
        )
    }
    private var swingarmNormal: CGVector {
        CGVector(dx: -swingarmAxis.dy, dy: swingarmAxis.dx)
    }
    private var axleLocal: CGPoint {
        point(along: swingarmAxis, distance: GameTuning.SuspensionRig.swingarmLength)
    }
    private var swingarmShockMountLocal: CGPoint {
        point(
            along: swingarmAxis,
            distance: GameTuning.SuspensionRig.swingarmShockMountDistance
        )
    }
    private var shockLength: CGFloat {
        let upper = chassis.convert(GameTuning.SuspensionRig.chassisShockMountOffset, to: self)
        let lower = swingarm.convert(swingarmShockMountLocal, to: self)
        return hypot(lower.x - upper.x, lower.y - upper.y)
    }
    private var groundBodyIDs: Set<ObjectIdentifier> {
        guard let groundBody = ground.physicsBody else { return [] }
        return [ObjectIdentifier(groundBody)]
    }
    private var isRearWheelGrounded: Bool {
        guard let wheelBody = rearWheel.physicsBody else { return false }
        return contacts.touches(wheelBody, anyOf: groundBodyIDs)
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

        view.preferredFramesPerSecond = GameTuning.Simulation.targetFramesPerSecond
        physicsWorld.gravity = GameTuning.Simulation.gravity
        physicsWorld.speed = 1
        physicsWorld.contactDelegate = self

        configureScene()
        restartStressTest()
    }

    // update(_:) runs before the next physics step, so force envelopes enter
    // SpriteKit's solver rather than moving any body or joint by hand.
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
        stressElapsed += frameDelta
        hudElapsed += frameDelta
        advanceStressProgram()
    }

    // This is after SpriteKit has resolved contacts and joints for the frame.
    override func didSimulatePhysics() {
        guard isConfigured else { return }

        sampleRigMetricsBeforeSafeguards()
        capMotion(
            of: swingarm.physicsBody,
            maximumLinearSpeed: GameTuning.SuspensionRig.maximumComponentLinearSpeed,
            maximumAngularVelocity: GameTuning.SuspensionRig.maximumSwingarmAngularVelocity
        )
        capMotion(
            of: rearWheel.physicsBody,
            maximumLinearSpeed: GameTuning.SuspensionRig.maximumComponentLinearSpeed,
            maximumAngularVelocity: GameTuning.SuspensionRig.maximumWheelAngularVelocity
        )
        updateShockVisual()
        updateActuatorVisual()

        if hudElapsed >= GameTuning.SuspensionRig.hudRefreshInterval || isTerminalStressState {
            hudElapsed = 0
            updateHUD()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isTerminalStressState else { return }
        restartStressTest()
    }

    func didBegin(_ contact: SKPhysicsContact) {
        if matches(contact, first: PhysicsCategory.suspensionRigWheel, second: PhysicsCategory.suspensionRigGround) {
            contacts.began(contact.bodyA, contact.bodyB)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        if matches(contact, first: PhysicsCategory.suspensionRigWheel, second: PhysicsCategory.suspensionRigGround) {
            contacts.ended(contact.bodyA, contact.bodyB)
        }
    }

    private func configureScene() {
        buildGround()
        buildTestStand()
        buildChassis()
        buildTravelArc()
        buildSwingarm()
        buildRearWheel()
        buildBumpActuator()

        [ground, testStand, bumpActuator, chassis, swingarm, rearWheel, shock].forEach(addChild)
        installSuspensionJoints()
        updateShockVisual()
        addHUD()
    }

    private func buildGround() {
        let start = CGPoint(x: -GameTuning.SuspensionRig.groundOverhang, y: groundY)
        let end = CGPoint(
            x: size.width + GameTuning.SuspensionRig.groundOverhang,
            y: groundY
        )
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
        body.friction = GameTuning.SuspensionRig.wheelFriction
        body.restitution = GameTuning.SuspensionRig.wheelRestitution
        body.categoryBitMask = PhysicsCategory.suspensionRigGround
        body.collisionBitMask = PhysicsCategory.suspensionRigWheel
        body.contactTestBitMask = PhysicsCategory.suspensionRigWheel
        ground.physicsBody = body
    }

    private func buildTestStand() {
        testStand.position = chassisCenter
        testStand.zPosition = 0

        let lower: CGFloat = -92
        let upper: CGFloat = 98
        let railHalfWidth: CGFloat = 28
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -railHalfWidth, y: lower))
        path.addLine(to: CGPoint(x: -railHalfWidth, y: upper))
        path.move(to: CGPoint(x: railHalfWidth, y: lower))
        path.addLine(to: CGPoint(x: railHalfWidth, y: upper))
        path.move(to: CGPoint(x: -railHalfWidth - 12, y: -56))
        path.addLine(to: CGPoint(x: railHalfWidth + 12, y: -56))
        path.move(to: CGPoint(x: -railHalfWidth - 12, y: 62))
        path.addLine(to: CGPoint(x: railHalfWidth + 12, y: 62))

        let rails = SKShapeNode(path: path)
        rails.strokeColor = SKColor(red: 0.31, green: 0.46, blue: 0.54, alpha: 0.82)
        rails.lineWidth = 4
        rails.lineCap = .round
        testStand.addChild(rails)

        let baseY = groundY - chassisCenter.y
        let basePath = CGMutablePath()
        basePath.move(to: CGPoint(x: -58, y: baseY))
        basePath.addLine(to: CGPoint(x: 58, y: baseY))
        basePath.move(to: CGPoint(x: -railHalfWidth, y: lower))
        basePath.addLine(to: CGPoint(x: -44, y: baseY))
        basePath.move(to: CGPoint(x: railHalfWidth, y: lower))
        basePath.addLine(to: CGPoint(x: 44, y: baseY))
        let base = SKShapeNode(path: basePath)
        base.strokeColor = SKColor(red: 0.22, green: 0.33, blue: 0.40, alpha: 1)
        base.lineWidth = 3
        base.lineCap = .round
        testStand.addChild(base)

        let body = SKPhysicsBody(rectangleOf: CGSize(width: 82, height: upper - lower + 40))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.suspensionRigStand
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        testStand.physicsBody = body
    }

    private func buildChassis() {
        chassis.position = chassisCenter
        chassis.zPosition = 4

        let size = GameTuning.SuspensionRig.chassisSize
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -halfWidth, y: -halfHeight))
        path.addLine(to: CGPoint(x: halfWidth, y: -halfHeight + 10))
        path.addLine(to: CGPoint(x: halfWidth - 24, y: halfHeight))
        path.addLine(to: CGPoint(x: -halfWidth + 28, y: halfHeight))
        path.closeSubpath()

        let chassisShell = SKShapeNode(path: path)
        chassisShell.fillColor = SKColor(red: 0.13, green: 0.22, blue: 0.30, alpha: 1)
        chassisShell.strokeColor = SKColor(red: 0.42, green: 0.72, blue: 0.79, alpha: 1)
        chassisShell.lineWidth = 3
        chassis.addChild(chassisShell)

        let ballast = SKShapeNode(rectOf: CGSize(width: 82, height: 20), cornerRadius: 4)
        ballast.fillColor = SKColor(red: 0.17, green: 0.34, blue: 0.42, alpha: 1)
        ballast.strokeColor = SKColor(red: 0.63, green: 0.91, blue: 0.88, alpha: 0.82)
        ballast.lineWidth = 2
        ballast.position = CGPoint(x: 20, y: 12)
        chassis.addChild(ballast)

        for x in [-36 as CGFloat, 36] {
            let fixtureClamp = SKShapeNode(rectOf: CGSize(width: 14, height: 24), cornerRadius: 3)
            fixtureClamp.fillColor = SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
            fixtureClamp.strokeColor = SKColor(white: 0.92, alpha: 1)
            fixtureClamp.lineWidth = 1
            fixtureClamp.position = CGPoint(x: x, y: 0)
            chassis.addChild(fixtureClamp)
        }

        let body = SKPhysicsBody(polygonFrom: path)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.suspensionRigChassis
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        chassis.physicsBody = body

        let pivotMarker = SKShapeNode(circleOfRadius: 8)
        pivotMarker.fillColor = SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
        pivotMarker.strokeColor = SKColor(white: 0.92, alpha: 1)
        pivotMarker.lineWidth = 2
        pivotMarker.position = GameTuning.SuspensionRig.chassisPivotOffset
        chassis.addChild(pivotMarker)

        let shockMarker = SKShapeNode(circleOfRadius: 5)
        shockMarker.fillColor = SKColor(white: 0.88, alpha: 1)
        shockMarker.strokeColor = .clear
        shockMarker.position = GameTuning.SuspensionRig.chassisShockMountOffset
        chassis.addChild(shockMarker)
    }

    private func buildTravelArc() {
        let pivot = GameTuning.SuspensionRig.chassisPivotOffset
        let path = CGMutablePath()
        path.addArc(
            center: pivot,
            radius: GameTuning.SuspensionRig.swingarmLength + 20,
            startAngle: GameTuning.SuspensionRig.neutralSwingarmAngle
                + GameTuning.SuspensionRig.lowerTravelAngle,
            endAngle: GameTuning.SuspensionRig.neutralSwingarmAngle
                + GameTuning.SuspensionRig.upperTravelAngle,
            clockwise: false
        )

        let arc = SKShapeNode(path: path)
        arc.strokeColor = SKColor(white: 0.60, alpha: 0.32)
        arc.lineWidth = 2
        arc.lineCap = .round
        arc.zPosition = -1
        chassis.addChild(arc)

        for relativeAngle in [
            GameTuning.SuspensionRig.lowerTravelAngle,
            GameTuning.SuspensionRig.upperTravelAngle
        ] {
            let absoluteAngle = GameTuning.SuspensionRig.neutralSwingarmAngle + relativeAngle
            let marker = SKShapeNode(circleOfRadius: 5)
            marker.fillColor = SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
            marker.strokeColor = .clear
            marker.position = pivot + CGVector(
                dx: cos(absoluteAngle) * (GameTuning.SuspensionRig.swingarmLength + 20),
                dy: sin(absoluteAngle) * (GameTuning.SuspensionRig.swingarmLength + 20)
            )
            marker.zPosition = -1
            chassis.addChild(marker)
        }
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
        axlePlate.position = axleLocal
        swingarm.addChild(axlePlate)

        let body = SKPhysicsBody(polygonFrom: path)
        body.mass = GameTuning.SuspensionRig.swingarmMass
        body.linearDamping = GameTuning.SuspensionRig.componentLinearDamping
        body.angularDamping = GameTuning.SuspensionRig.swingarmAngularDamping
        body.affectedByGravity = true
        body.allowsRotation = true
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = PhysicsCategory.suspensionRigSwingarm
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        swingarm.physicsBody = body
    }

    private func buildRearWheel() {
        rearWheel.position = swingarm.convert(axleLocal, to: self)
        rearWheel.zPosition = 6

        let tire = SKShapeNode(circleOfRadius: GameTuning.SuspensionRig.wheelRadius)
        tire.fillColor = SKColor(red: 0.025, green: 0.040, blue: 0.055, alpha: 1)
        tire.strokeColor = SKColor(red: 0.79, green: 0.88, blue: 0.88, alpha: 1)
        tire.lineWidth = 3
        rearWheel.addChild(tire)

        let hub = SKShapeNode(circleOfRadius: 7)
        hub.fillColor = SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
        hub.strokeColor = .clear
        rearWheel.addChild(hub)

        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 4) {
            let spokePath = CGMutablePath()
            spokePath.move(to: .zero)
            spokePath.addLine(to: CGPoint(
                x: cos(angle) * (GameTuning.SuspensionRig.wheelRadius - 5),
                y: sin(angle) * (GameTuning.SuspensionRig.wheelRadius - 5)
            ))
            let spoke = SKShapeNode(path: spokePath)
            spoke.strokeColor = SKColor(white: 0.80, alpha: 0.54)
            spoke.lineWidth = 1
            rearWheel.addChild(spoke)
        }

        let body = SKPhysicsBody(circleOfRadius: GameTuning.SuspensionRig.wheelRadius)
        body.mass = GameTuning.SuspensionRig.rearWheelMass
        body.linearDamping = GameTuning.SuspensionRig.componentLinearDamping
        body.angularDamping = GameTuning.SuspensionRig.wheelAngularDamping
        body.friction = GameTuning.SuspensionRig.wheelFriction
        body.restitution = GameTuning.SuspensionRig.wheelRestitution
        body.affectedByGravity = true
        body.allowsRotation = true
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = PhysicsCategory.suspensionRigWheel
        body.collisionBitMask = PhysicsCategory.suspensionRigGround
        body.contactTestBitMask = PhysicsCategory.suspensionRigGround
        rearWheel.physicsBody = body
    }

    private func buildBumpActuator() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -28))
        path.addLine(to: CGPoint(x: 0, y: 26))
        path.move(to: CGPoint(x: -8, y: 16))
        path.addLine(to: CGPoint(x: 0, y: 26))
        path.addLine(to: CGPoint(x: 8, y: 16))
        bumpActuator.path = path
        bumpActuator.strokeColor = SKColor(red: 0.42, green: 0.56, blue: 0.60, alpha: 0.42)
        bumpActuator.lineWidth = 3
        bumpActuator.lineCap = .round
        bumpActuator.lineJoin = .round
        bumpActuator.position = CGPoint(x: rearWheel.position.x, y: groundY)
        bumpActuator.zPosition = 2
    }

    private func installSuspensionJoints() {
        guard let chassisBody = chassis.physicsBody,
              let swingarmBody = swingarm.physicsBody,
              let rearWheelBody = rearWheel.physicsBody else {
            assertionFailure("Rear-suspension rig needs chassis, swingarm, and wheel bodies before adding joints.")
            return
        }

        let pivot = SKPhysicsJointPin.joint(
            withBodyA: chassisBody,
            bodyB: swingarmBody,
            anchor: chassis.convert(GameTuning.SuspensionRig.chassisPivotOffset, to: self)
        )
        pivot.shouldEnableLimits = true
        pivot.lowerAngleLimit = GameTuning.SuspensionRig.lowerTravelAngle
        pivot.upperAngleLimit = GameTuning.SuspensionRig.upperTravelAngle
        pivot.frictionTorque = GameTuning.SuspensionRig.pivotFrictionTorque

        let axle = SKPhysicsJointPin.joint(
            withBodyA: swingarmBody,
            bodyB: rearWheelBody,
            anchor: swingarm.convert(axleLocal, to: self)
        )

        let upperAnchor = chassis.convert(GameTuning.SuspensionRig.chassisShockMountOffset, to: self)
        let lowerAnchor = swingarm.convert(swingarmShockMountLocal, to: self)
        let spring = SKPhysicsJointSpring.joint(
            withBodyA: chassisBody,
            bodyB: swingarmBody,
            anchorA: upperAnchor,
            anchorB: lowerAnchor
        )
        spring.frequency = GameTuning.SuspensionRig.springFrequency
        spring.damping = GameTuning.SuspensionRig.springDamping

        let topOut = SKPhysicsJointLimit.joint(
            withBodyA: chassisBody,
            bodyB: swingarmBody,
            anchorA: upperAnchor,
            anchorB: lowerAnchor
        )
        topOut.maxLength = shockLength + GameTuning.SuspensionRig.topOutStrapExtraLength

        pivotJoint = pivot
        topOutJoint = topOut
        suspensionJoints = [pivot, axle, spring, topOut]
        suspensionJoints.forEach { physicsWorld.add($0) }
    }

    private func advanceStressProgram() {
        guard !isTerminalStressState else {
            activeAxleForce = .zero
            return
        }

        activeAxleForce = .zero
        switch stressState {
        case .settling:
            activePhase = "SETTLING BASELINE"
            if stressElapsed >= GameTuning.SuspensionRig.initialSettleDuration {
                captureBaseline()
                stressState = .running
            }

        case .running:
            let programTime = stressElapsed - GameTuning.SuspensionRig.initialSettleDuration
            activePhase = "BETWEEN LOADS"
            for pulse in GameTuning.SuspensionRig.stressPulses {
                guard let envelope = smoothPulseEnvelope(for: pulse, at: programTime) else { continue }
                activePhase = pulse.label
                apply(pulse: pulse, envelope: envelope)
            }
            if programTime >= GameTuning.SuspensionRig.stressProgramDuration {
                stressState = .coasting
                coastingStartedAt = stressElapsed
                stableSince = nil
                activePhase = "FINAL SETTLE"
            }

        case .coasting:
            activePhase = "VERIFYING SETTLE"
            evaluateFinalSettle()

        case .passed, .failed:
            break
        }
    }

    private func apply(pulse: SuspensionRigStressPulse, envelope: CGFloat) {
        guard let swingarmBody = swingarm.physicsBody else { return }

        let axleForce = pulse.axleForce * envelope
        if axleForce != .zero {
            swingarmBody.isResting = false
            swingarmBody.applyForce(axleForce, at: swingarm.convert(axleLocal, to: self))
            activeAxleForce = activeAxleForce + axleForce
        }
    }

    private func smoothPulseEnvelope(
        for pulse: SuspensionRigStressPulse,
        at programTime: TimeInterval
    ) -> CGFloat? {
        let progress = (programTime - pulse.startTime) / pulse.duration
        guard progress >= 0, progress <= 1 else { return nil }
        return sin(CGFloat.pi * CGFloat(progress))
    }

    private func captureBaseline() {
        baselineArmAngle = swingarm.zRotation
        baselineShockLength = shockLength
    }

    private func evaluateFinalSettle() {
        guard let coastingStartedAt else { return }

        if rigHasSettled {
            if stableSince == nil {
                stableSince = stressElapsed
            }
            if let stableSince,
               stressElapsed - stableSince >= GameTuning.SuspensionRig.finalSettleWindow {
                stressState = .passed
                activePhase = "STRESS TEST COMPLETE"
            }
        } else {
            stableSince = nil
        }

        if stressElapsed - coastingStartedAt >= GameTuning.SuspensionRig.finalSettleTimeout,
           stressState == .coasting {
            recordFailure("DID NOT RE-SETTLE")
        }
    }

    private var rigHasSettled: Bool {
        guard let swingarmBody = swingarm.physicsBody,
              let rearWheelBody = rearWheel.physicsBody,
              let baselineArmAngle,
              let baselineShockLength else { return false }

        let maximumSpeed = GameTuning.SuspensionRig.finalSettleMaximumSpeed
        let maximumAngularSpeed = GameTuning.SuspensionRig.finalSettleMaximumAngularSpeed
        let bodiesAreSlow = [swingarmBody, rearWheelBody].allSatisfy {
            vectorLength($0.velocity) <= maximumSpeed
        }
        let armIsSlow = abs(swingarmBody.angularVelocity) <= maximumAngularSpeed
        let returnedNearBaseline = abs(swingarm.zRotation - baselineArmAngle)
            <= GameTuning.SuspensionRig.finalSettleAngleTolerance
            || abs(shockLength - baselineShockLength)
                <= GameTuning.SuspensionRig.finalSettleShockLengthTolerance
        return bodiesAreSlow && armIsSlow && returnedNearBaseline
    }

    private func sampleRigMetricsBeforeSafeguards() {
        let pivotError = distance(
            chassis.convert(GameTuning.SuspensionRig.chassisPivotOffset, to: self),
            swingarm.convert(.zero, to: self)
        )
        let axleError = distance(
            swingarm.convert(axleLocal, to: self),
            rearWheel.convert(.zero, to: self)
        )
        maximumPivotError = max(maximumPivotError, pivotError)
        maximumAxleError = max(maximumAxleError, axleError)
        maximumPivotReaction = max(maximumPivotReaction, reactionMagnitude(of: pivotJoint))
        maximumTopOutReaction = max(maximumTopOutReaction, reactionMagnitude(of: topOutJoint))
        maximumBodySpeed = max(
            maximumBodySpeed,
            vectorLength(chassis.physicsBody?.velocity ?? .zero),
            vectorLength(swingarm.physicsBody?.velocity ?? .zero),
            vectorLength(rearWheel.physicsBody?.velocity ?? .zero)
        )

        let angle = swingarm.zRotation
        if angle <= GameTuning.SuspensionRig.lowerTravelAngle
            + GameTuning.SuspensionRig.travelLimitTolerance
            || angle >= GameTuning.SuspensionRig.upperTravelAngle
                - GameTuning.SuspensionRig.travelLimitTolerance {
            armStopReached = true
        }
        recordGroundTransitions()

        guard bodiesAreFinite else {
            recordFailure("NON-FINITE STATE")
            return
        }
        if pivotError > GameTuning.SuspensionRig.maximumPivotAnchorError {
            recordFailure("PIVOT ERROR")
        }
        if axleError > GameTuning.SuspensionRig.maximumAxleAnchorError {
            recordFailure("AXLE ERROR")
        }
        if angle < GameTuning.SuspensionRig.lowerTravelAngle
            - GameTuning.SuspensionRig.travelLimitTolerance
            || angle > GameTuning.SuspensionRig.upperTravelAngle
                + GameTuning.SuspensionRig.travelLimitTolerance {
            recordFailure("TRAVEL LIMIT")
        }
        if rearWheel.position.y - GameTuning.SuspensionRig.wheelRadius
            < groundY - GameTuning.SuspensionRig.maximumWheelPenetration {
            recordFailure("GROUND PENETRATION")
        }
    }

    private func recordGroundTransitions() {
        let grounded = isRearWheelGrounded
        guard grounded != lastGroundedState else { return }

        lastGroundedState = grounded
        groundTransitionTimes.append(stressElapsed)
        let windowStart = stressElapsed - 0.5
        groundTransitionTimes.removeAll { $0 < windowStart }
        maximumGroundTransitions = max(maximumGroundTransitions, groundTransitionTimes.count)
        if groundTransitionTimes.count
            > GameTuning.SuspensionRig.maximumGroundTransitionsPerHalfSecond {
            recordFailure("GROUND CHATTER")
        }
    }

    private var bodiesAreFinite: Bool {
        [chassis, swingarm, rearWheel].allSatisfy { node in
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
            recordFailure("NON-FINITE MOTION")
            return
        }

        if speed > maximumLinearSpeed {
            recordFailure("LINEAR SAFETY CAP")
            let scale = maximumLinearSpeed / speed
            body.velocity = CGVector(dx: body.velocity.dx * scale, dy: body.velocity.dy * scale)
        }
        if abs(body.angularVelocity) > maximumAngularVelocity {
            recordFailure("ANGULAR SAFETY CAP")
            body.angularVelocity = min(
                maximumAngularVelocity,
                max(-maximumAngularVelocity, body.angularVelocity)
            )
        }
    }

    private func recordFailure(_ reason: String) {
        guard stressState != .passed, failureReason == nil else { return }
        failureReason = reason
        stressState = .failed
        activePhase = "CHECK REQUIRED"
    }

    private var isTerminalStressState: Bool {
        stressState == .passed || stressState == .failed
    }

    private func restartStressTest() {
        stressElapsed = 0
        coastingStartedAt = nil
        stableSince = nil
        stressState = .settling
        baselineArmAngle = nil
        baselineShockLength = nil
        activePhase = "SETTLING BASELINE"
        activeAxleForce = .zero
        failureReason = nil
        maximumPivotError = 0
        maximumAxleError = 0
        maximumPivotReaction = 0
        maximumTopOutReaction = 0
        maximumBodySpeed = 0
        maximumGroundTransitions = 0
        groundTransitionTimes.removeAll(keepingCapacity: true)
        lastGroundedState = isRearWheelGrounded
        armStopReached = false
        hudElapsed = GameTuning.SuspensionRig.hudRefreshInterval
        updateHUD()
    }

    private func updateShockVisual() {
        let upper = chassis.convert(GameTuning.SuspensionRig.chassisShockMountOffset, to: self)
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
        let coilLength = hypot(coilEnd.x - coilStart.x, coilEnd.y - coilStart.y)

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

    private func updateActuatorVisual() {
        bumpActuator.position.x = rearWheel.position.x
        let forceScale = min(
            1,
            vectorLength(activeAxleForce) / GameTuning.SuspensionRig.maximumActuatorForce
        )
        bumpActuator.strokeColor = forceScale > 0.01
            ? SKColor(red: 0.98, green: 0.48, blue: 0.20, alpha: 0.45 + 0.55 * forceScale)
            : SKColor(red: 0.42, green: 0.56, blue: 0.60, alpha: 0.42)
        bumpActuator.lineWidth = 3 + 2 * forceScale
    }

    private func addHUD() {
        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "REAR SUSPENSION LAB"
        title.fontSize = 20
        title.fontColor = SKColor(white: 0.91, alpha: 1)
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: 28, y: size.height - 42)
        title.zPosition = 10
        addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        subtitle.text = "fixed pivot fixture  •  flat ground  •  bounded load-path sweep"
        subtitle.fontSize = 12
        subtitle.fontColor = SKColor(white: 0.68, alpha: 1)
        subtitle.horizontalAlignmentMode = .left
        subtitle.position = CGPoint(x: 29, y: size.height - 64)
        subtitle.zPosition = 10
        addChild(subtitle)

        phaseLabel.fontSize = 13
        phaseLabel.fontColor = SKColor(red: 0.63, green: 0.91, blue: 0.87, alpha: 1)
        phaseLabel.horizontalAlignmentMode = .left
        phaseLabel.position = CGPoint(x: 28, y: size.height - 92)
        phaseLabel.zPosition = 10
        addChild(phaseLabel)

        metricsLabel.fontSize = 11
        metricsLabel.fontColor = SKColor(white: 0.76, alpha: 1)
        metricsLabel.horizontalAlignmentMode = .left
        metricsLabel.position = CGPoint(x: 28, y: size.height - 112)
        metricsLabel.zPosition = 10
        addChild(metricsLabel)

        resultLabel.fontSize = 12
        resultLabel.horizontalAlignmentMode = .left
        resultLabel.position = CGPoint(x: 28, y: 28)
        resultLabel.zPosition = 10
        addChild(resultLabel)

        let trackX = size.width - 30
        let trackBottom: CGFloat = 86
        let trackTop: CGFloat = 190
        let trackPath = CGMutablePath()
        trackPath.move(to: CGPoint(x: trackX, y: trackBottom))
        trackPath.addLine(to: CGPoint(x: trackX, y: trackTop))
        travelTrack.path = trackPath
        travelTrack.strokeColor = SKColor(white: 0.70, alpha: 0.44)
        travelTrack.lineWidth = 4
        travelTrack.lineCap = .round
        travelTrack.zPosition = 10
        addChild(travelTrack)

        travelIndicator.fillColor = SKColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
        travelIndicator.strokeColor = SKColor(white: 0.94, alpha: 1)
        travelIndicator.lineWidth = 1
        travelIndicator.zPosition = 11
        addChild(travelIndicator)
    }

    private func updateHUD() {
        let terminalSuffix = isTerminalStressState ? "  •  TAP TO RE-RUN" : ""
        phaseLabel.text = activePhase + terminalSuffix
        metricsLabel.text = String(
            format: "arm %+0.3f  shock %3.0f  joint err P %.1f / A %.1f  %@",
            Double(swingarm.zRotation),
            Double(shockLength),
            Double(maximumPivotError),
            Double(maximumAxleError),
            isRearWheelGrounded ? "GROUND" : "AIR"
        )

        switch stressState {
        case .settling, .running, .coasting:
            let stops = [
                armStopReached ? "ARM STOP" : nil
            ].compactMap { $0 }.joined(separator: " • ")
            resultLabel.text = stops.isEmpty
                ? String(
                    format: "RUNNING  •  max speed %.1f  •  pivot reaction %.1f",
                    Double(maximumBodySpeed),
                    Double(maximumPivotReaction)
                )
                : "RUNNING  •  \(stops)"
            resultLabel.fontColor = SKColor(red: 0.80, green: 0.88, blue: 0.86, alpha: 1)

        case .passed:
            resultLabel.text = "PASS  •  bounded loads held, fixed pivot stayed true"
            resultLabel.fontColor = SKColor(red: 0.54, green: 0.96, blue: 0.72, alpha: 1)

        case .failed:
            resultLabel.text = "CHECK  •  \(failureReason ?? "UNKNOWN")"
            resultLabel.fontColor = SKColor(red: 1.0, green: 0.50, blue: 0.42, alpha: 1)
        }

        let trackBottom: CGFloat = 86
        let trackTop: CGFloat = 190
        let range = GameTuning.SuspensionRig.upperTravelAngle
            - GameTuning.SuspensionRig.lowerTravelAngle
        let fraction = min(
            1,
            max(0, (swingarm.zRotation - GameTuning.SuspensionRig.lowerTravelAngle) / range)
        )
        travelIndicator.position = CGPoint(
            x: size.width - 30,
            y: trackBottom + (trackTop - trackBottom) * fraction
        )
    }

    private func matches(_ contact: SKPhysicsContact, first: UInt32, second: UInt32) -> Bool {
        let firstMatchesA = contact.bodyA.categoryBitMask & first != 0
        let secondMatchesB = contact.bodyB.categoryBitMask & second != 0
        let secondMatchesA = contact.bodyA.categoryBitMask & second != 0
        let firstMatchesB = contact.bodyB.categoryBitMask & first != 0
        return (firstMatchesA && secondMatchesB) || (secondMatchesA && firstMatchesB)
    }

    private func swingarmPath() -> CGPath {
        let halfThickness = GameTuning.SuspensionRig.swingarmThickness / 2
        let offset = swingarmNormal * halfThickness
        let end = point(along: swingarmAxis, distance: GameTuning.SuspensionRig.swingarmLength)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: offset.dx, y: offset.dy))
        path.addLine(to: end + offset)
        path.addLine(to: end - offset)
        path.addLine(to: CGPoint(x: -offset.dx, y: -offset.dy))
        path.closeSubpath()
        return path
    }

    private func vectorLength(_ vector: CGVector) -> CGFloat {
        hypot(vector.dx, vector.dy)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func reactionMagnitude(of joint: SKPhysicsJoint?) -> CGFloat {
        guard let joint else { return 0 }
        return vectorLength(joint.reactionForce)
    }

    private func point(along vector: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: vector.dx * distance, y: vector.dy * distance)
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
    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }
}
