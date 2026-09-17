import SpriteKit

/// A multi-body articulated bike whose frame (chassis), swingarm, rear wheel,
/// and front wheel have independent physics bodies connected by pin joints,
/// spring shocks, and travel limit constraints.
final class BikeNode: SKNode {
    private let chassis = SKNode()
    private let swingarm = SKNode()
    private let frontFork = SKNode()
    private let rearWheel = SKShapeNode(circleOfRadius: GameTuning.Bike.visualWheelRadius)
    private let frontWheel = SKShapeNode(circleOfRadius: GameTuning.Bike.visualWheelRadius)
    private let shock = SKShapeNode()
    private let forkStanchion = SKShapeNode()
    private let bikeArtwork = SKNode()
    private let swingarmArtwork = SKNode()
    private let frontForkArtwork = SKNode()
    private let rider = SKNode()

    private var joints: [SKPhysicsJoint] = []
    private var pivotJoint: SKPhysicsJointPin?
    private var rearAxleJoint: SKPhysicsJointPin?
    private var frontAxleJoint: SKPhysicsJointPin?
    private var topOutJoint: SKPhysicsJointLimit?
    private var frontForkSlidingJoint: SKPhysicsJointSliding?
    private var frontForkSpringJoint: SKPhysicsJointSpring?

    var chassisBody: SKPhysicsBody {
        guard let body = chassis.physicsBody else {
            preconditionFailure("BikeNode must always own its chassis physics body.")
        }
        return body
    }

    var swingarmBody: SKPhysicsBody {
        guard let body = swingarm.physicsBody else {
            preconditionFailure("BikeNode must always own its swingarm physics body.")
        }
        return body
    }

    var frontForkBody: SKPhysicsBody {
        guard let body = frontFork.physicsBody else {
            preconditionFailure("BikeNode must always own its front fork physics body.")
        }
        return body
    }

    var rearWheelBody: SKPhysicsBody {
        guard let body = rearWheel.physicsBody else {
            preconditionFailure("BikeNode must always own its rear wheel physics body.")
        }
        return body
    }

    var frontWheelBody: SKPhysicsBody {
        guard let body = frontWheel.physicsBody else {
            preconditionFailure("BikeNode must always own its front wheel physics body.")
        }
        return body
    }

    var allBodies: [SKPhysicsBody] { [chassisBody, swingarmBody, frontForkBody, rearWheelBody, frontWheelBody] }
    var chassisPosition: CGPoint { chassis.position }
    var chassisRotation: CGFloat { chassis.zRotation }
    var velocity: CGVector { chassisBody.velocity }
    var rearAxlePosition: CGPoint { rearWheel.position }
    var frontAxlePosition: CGPoint { frontWheel.position }

    override init() {
        super.init()
        buildBike()
        configurePhysics()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        buildBike()
        configurePhysics()
    }

    func reset(at position: CGPoint, attitude: CGFloat) {
        removeJoints()
        self.position = .zero
        self.zRotation = 0

        let cosA = cos(attitude)
        let sinA = sin(attitude)
        func worldPoint(for offset: CGPoint) -> CGPoint {
            CGPoint(
                x: position.x + offset.x * cosA - offset.y * sinA,
                y: position.y + offset.x * sinA + offset.y * cosA
            )
        }

        chassis.position = worldPoint(for: .zero)
        chassis.zRotation = attitude
        swingarm.position = worldPoint(for: GameTuning.Bike.chassisPivotOffset)
        swingarm.zRotation = attitude
        frontFork.position = worldPoint(for: GameTuning.Bike.frontAxleOffset)
        frontFork.zRotation = attitude
        rearWheel.position = worldPoint(for: GameTuning.Bike.rearAxleOffset)
        rearWheel.zRotation = attitude
        frontWheel.position = worldPoint(for: GameTuning.Bike.frontAxleOffset)
        frontWheel.zRotation = attitude

        if rider.parent != bikeArtwork {
            rider.physicsBody = nil
            rider.removeFromParent()
            bikeArtwork.addChild(rider)
        }
        rider.removeAllActions()
        rider.position = .zero
        rider.zRotation = 0
        rider.alpha = 1

        [chassis, swingarm, frontFork, rearWheel, frontWheel].forEach { node in
            guard let body = node.physicsBody else { return }
            body.isDynamic = false
            body.velocity = .zero
            body.angularVelocity = 0
            body.isResting = false
            body.allowsRotation = true
        }

        updateShockVisual()
        updateForkVisual()
    }

    /// Places both tire fixtures just above a straight supporting rail at the
    /// requested attitude. A fixed vertical offset only works on level ground.
    func spawnClearance(for attitude: CGFloat) -> CGFloat {
        let safeCosine = max(
            cos(attitude),
            GameTuning.Bike.minimumSpawnCosine
        )
        return (
            GameTuning.Bike.collisionWheelRadius
                + GameTuning.Bike.spawnContactPadding
                - GameTuning.Bike.rearAxleOffset.y
        ) / safeCosine
    }

    func prepareForSpawn() {
        removeJoints()
        [chassis, swingarm, frontFork, rearWheel, frontWheel].forEach { node in
            guard let body = node.physicsBody else { return }
            body.isDynamic = false
            body.velocity = .zero
            body.angularVelocity = 0
        }
    }

    func activatePhysics(lockPitch: Bool = false) {
        [chassis, swingarm, frontFork, rearWheel, frontWheel].forEach { node in
            guard let body = node.physicsBody else { return }
            body.isDynamic = true
            body.velocity = .zero
            body.angularVelocity = 0
            body.isResting = false
        }
        chassisBody.allowsRotation = !lockPitch
        installJoints()
    }

    func unlockPitch() {
        chassisBody.allowsRotation = true
        chassisBody.angularVelocity = 0
    }

    func freezePhysics() {
        removeJoints()
        [chassis, swingarm, frontFork, rearWheel, frontWheel].forEach { node in
            guard let body = node.physicsBody else { return }
            body.velocity = .zero
            body.angularVelocity = 0
            body.isDynamic = false
        }
    }

    func resetAppearance() {
        if rider.parent != bikeArtwork {
            rider.physicsBody = nil
            rider.removeFromParent()
            bikeArtwork.addChild(rider)
        }
        removeAllActions()
        chassis.removeAllActions()
        rider.removeAllActions()
        rider.position = .zero
        rider.zRotation = 0
        alpha = 1
        chassis.alpha = 1
        bikeArtwork.alpha = 1
        swingarmArtwork.alpha = 1
        frontForkArtwork.alpha = 1
        rider.alpha = 1
    }

    func crash() {
        chassis.run(.group([
            .rotate(byAngle: 0.32, duration: 0.14),
            .fadeAlpha(to: 0.86, duration: 0.14)
        ]))
        
        guard let scene = scene else { return }
        let worldPos = scene.convert(rider.position, from: bikeArtwork)
        let worldRot = chassis.zRotation + rider.zRotation
        let currentVel = chassisBody.velocity
        let currentAngVel = chassisBody.angularVelocity

        rider.removeAllActions()
        if rider.parent != scene {
            rider.removeFromParent()
            scene.addChild(rider)
        }
        rider.position = worldPos
        rider.zRotation = worldRot

        let rBody = SKPhysicsBody(circleOfRadius: 16)
        rBody.usesPreciseCollisionDetection = true
        rBody.categoryBitMask = 0
        rBody.collisionBitMask = 0
        rBody.contactTestBitMask = 0
        rBody.velocity = CGVector(dx: currentVel.dx + 60, dy: currentVel.dy + 90)
        rBody.angularVelocity = currentAngVel - 6.0
        rider.physicsBody = rBody
    }

    /// A hard impact can occasionally push the joint solver past what it can
    /// fully resolve in a single step. The joint never technically breaks,
    /// but a light body like a wheel can end up rendering implausibly far
    /// from the chassis for a frame or more — what reads as a wheel flying
    /// off — or, worse, with a non-finite position or velocity that can
    /// crash rendering or the physics solver outright. Rather than trying to
    /// out-guess the solver, this snaps the whole rig back to its resting
    /// layout around the chassis's current position and attitude, exactly
    /// like a fresh spawn. Returns whether a repair happened.
    @discardableResult
    private func repairIfBroken() -> Bool {
        let rigNodes: [SKNode] = [swingarm, frontFork, rearWheel, frontWheel]
        let chassisPosition = chassis.position

        let chassisIsBroken = !chassisPosition.x.isFinite || !chassisPosition.y.isFinite || !chassis.zRotation.isFinite
        let anyBodyNonFinite = allBodies.contains { body in
            !body.velocity.dx.isFinite || !body.velocity.dy.isFinite || !body.angularVelocity.isFinite
        }
        let anyNodeDetached = rigNodes.contains { node in
            guard node.position.x.isFinite, node.position.y.isFinite else { return true }
            let drift = hypot(node.position.x - chassisPosition.x, node.position.y - chassisPosition.y)
            return drift > GameTuning.Bike.maximumJointDriftBeforeRepair
        }

        guard chassisIsBroken || anyBodyNonFinite || anyNodeDetached else { return false }

        let recoveryPosition = chassisIsBroken ? .zero : chassisPosition
        let recoveryAttitude = chassis.zRotation.isFinite ? chassis.zRotation : 0
        let wasDynamic = chassis.physicsBody?.isDynamic ?? false
        reset(at: recoveryPosition, attitude: recoveryAttitude)
        if wasDynamic {
            activatePhysics()
        }
        return true
    }

    /// Safeguards against Box2D edge tunneling at high speeds and hard landings.
    /// Clamps wheel and chassis positions to always remain above the terrain surface,
    /// cancelling downward penetration momentum and preventing the bike from falling
    /// through the map.
    func recoverTerrainPenetration(terrainHeightAt: (CGFloat) -> CGFloat) {
        let wheelRadius = GameTuning.Bike.collisionWheelRadius
        let recoveryClearance = GameTuning.Terrain.wheelPenetrationRecoveryClearance

        let trigger = GameTuning.Terrain.wheelPenetrationRecoveryTrigger

        // 1. Recover rear wheel
        let rearTerrainY = terrainHeightAt(rearWheel.position.x)
        let idealRearY = rearTerrainY + wheelRadius
        if rearWheel.position.y <= idealRearY - trigger {
            rearWheel.position.y = idealRearY + recoveryClearance
            if let body = rearWheel.physicsBody, body.velocity.dy < 0 {
                body.velocity.dy = 0
            }
        }

        // 2. Recover front wheel
        let frontTerrainY = terrainHeightAt(frontWheel.position.x)
        let idealFrontY = frontTerrainY + wheelRadius
        if frontWheel.position.y <= idealFrontY - trigger {
            frontWheel.position.y = idealFrontY + recoveryClearance
            if let body = frontWheel.physicsBody, body.velocity.dy < 0 {
                body.velocity.dy = 0
            }
        }

        // 3. Recover chassis frame
        let chassisTerrainY = terrainHeightAt(chassis.position.x)
        let minChassisY = chassisTerrainY + GameTuning.Bike.frameGuardRadius
        if chassis.position.y <= minChassisY - trigger {
            chassis.position.y = minChassisY + recoveryClearance
            if let body = chassis.physicsBody, body.velocity.dy < 0 {
                body.velocity.dy = 0
            }
        }
    }

    /// The visual wheels rotate naturally from friction with the ground in the
    /// physics engine. Here we update the live shock visual, rider posture,
    /// and cap excessive spin, speed, and non-finite values a hard impact can produce.
    func updateVisuals(deltaTime: TimeInterval, leanInput: CGFloat = 0, pedalHeld: Bool = false) {
        guard !repairIfBroken() else { return }
        updateShockVisual()
        updateForkVisual()
        updateRiderPose(deltaTime: deltaTime, leanInput: leanInput, pedalHeld: pedalHeld)
        for body in allBodies {
            // A stiff joint solved across a large frame-hitch timestep, or a
            // hard multi-body impact, can occasionally push a body's velocity
            // to a non-finite value. Catching that here stops it from
            // propagating into a render or physics crash next frame.
            if !body.velocity.dx.isFinite || !body.velocity.dy.isFinite || !body.angularVelocity.isFinite {
                body.velocity = .zero
                body.angularVelocity = 0
                continue
            }
            if abs(body.angularVelocity) > 35.0 {
                body.angularVelocity = min(35.0, max(-35.0, body.angularVelocity))
            }
            let speed = hypot(body.velocity.dx, body.velocity.dy)
            if speed > GameTuning.Bike.maximumSpeed {
                let scale = GameTuning.Bike.maximumSpeed / speed
                body.velocity = CGVector(dx: body.velocity.dx * scale, dy: body.velocity.dy * scale)
            }
        }
    }

    func installJoints() {
        guard let physicsWorld = scene?.physicsWorld,
              let scene = scene,
              let cBody = chassis.physicsBody,
              let sBody = swingarm.physicsBody,
              let ffBody = frontFork.physicsBody,
              let rwBody = rearWheel.physicsBody,
              let fwBody = frontWheel.physicsBody else {
            return
        }
        removeJoints()

        let pivotAnchor = scene.convert(GameTuning.Bike.chassisPivotOffset, from: chassis)
        let pivot = SKPhysicsJointPin.joint(
            withBodyA: cBody,
            bodyB: sBody,
            anchor: pivotAnchor
        )
        pivot.shouldEnableLimits = true
        pivot.lowerAngleLimit = GameTuning.Bike.lowerTravelAngle
        pivot.upperAngleLimit = GameTuning.Bike.upperTravelAngle
        pivot.frictionTorque = GameTuning.Bike.pivotFrictionTorque

        let rearAxleAnchor = scene.convert(CGPoint.zero, from: rearWheel)
        let rearAxle = SKPhysicsJointPin.joint(
            withBodyA: sBody,
            bodyB: rwBody,
            anchor: rearAxleAnchor
        )

        let forkAnchor = scene.convert(CGPoint.zero, from: frontFork)
        let axis = GameTuning.Bike.frontForkAxis
        let angle = chassis.zRotation
        let sceneAxis = CGVector(
            dx: axis.dx * cos(angle) - axis.dy * sin(angle),
            dy: axis.dx * sin(angle) + axis.dy * cos(angle)
        )
        let forkSliding = SKPhysicsJointSliding.joint(
            withBodyA: cBody,
            bodyB: ffBody,
            anchor: forkAnchor,
            axis: sceneAxis
        )
        forkSliding.shouldEnableLimits = true
        forkSliding.lowerDistanceLimit = GameTuning.Bike.frontLowerTravelLimit
        forkSliding.upperDistanceLimit = GameTuning.Bike.frontUpperTravelLimit

        let headTubeAnchor = scene.convert(BikeGeometry.headTubeBottom, from: chassis)
        let forkSpring = SKPhysicsJointSpring.joint(
            withBodyA: cBody,
            bodyB: ffBody,
            anchorA: headTubeAnchor,
            anchorB: forkAnchor
        )
        forkSpring.frequency = GameTuning.Bike.frontSpringFrequency
        forkSpring.damping = GameTuning.Bike.frontSpringDamping

        let frontAxleAnchor = scene.convert(CGPoint.zero, from: frontWheel)
        let frontAxle = SKPhysicsJointPin.joint(
            withBodyA: ffBody,
            bodyB: fwBody,
            anchor: frontAxleAnchor
        )

        let upperAnchor = scene.convert(GameTuning.Bike.chassisShockMountOffset, from: chassis)
        let lowerAnchor = scene.convert(GameTuning.Bike.swingarmShockMountLocal, from: swingarm)
        let spring = SKPhysicsJointSpring.joint(
            withBodyA: cBody,
            bodyB: sBody,
            anchorA: upperAnchor,
            anchorB: lowerAnchor
        )
        spring.frequency = GameTuning.Bike.springFrequency
        spring.damping = GameTuning.Bike.springDamping

        let shockLen = hypot(lowerAnchor.x - upperAnchor.x, lowerAnchor.y - upperAnchor.y)
        let topOut = SKPhysicsJointLimit.joint(
            withBodyA: cBody,
            bodyB: sBody,
            anchorA: upperAnchor,
            anchorB: lowerAnchor
        )
        topOut.maxLength = shockLen + GameTuning.Bike.topOutStrapExtraLength

        pivotJoint = pivot
        rearAxleJoint = rearAxle
        frontAxleJoint = frontAxle
        topOutJoint = topOut
        frontForkSlidingJoint = forkSliding
        frontForkSpringJoint = forkSpring
        joints = [pivot, rearAxle, forkSliding, forkSpring, frontAxle, spring, topOut]
        joints.forEach { physicsWorld.add($0) }
    }

    func removeJoints() {
        if let physicsWorld = scene?.physicsWorld {
            joints.forEach { physicsWorld.remove($0) }
        }
        joints.removeAll(keepingCapacity: true)
        pivotJoint = nil
        rearAxleJoint = nil
        frontAxleJoint = nil
        topOutJoint = nil
        frontForkSlidingJoint = nil
        frontForkSpringJoint = nil
    }

    private func updateShockVisual() {
        let upper = convert(GameTuning.Bike.chassisShockMountOffset, from: chassis)
        let lower = convert(GameTuning.Bike.swingarmShockMountLocal, from: swingarm)
        let dx = lower.x - upper.x
        let dy = lower.y - upper.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return }

        let axis = CGVector(dx: dx / length, dy: dy / length)
        let normal = CGVector(dx: -axis.dy, dy: axis.dx)
        let leadLength = min(CGFloat(4), length / 4)
        let coilStart = CGPoint(x: upper.x + axis.dx * leadLength, y: upper.y + axis.dy * leadLength)
        let coilEnd = CGPoint(x: lower.x - axis.dx * leadLength, y: lower.y - axis.dy * leadLength)
        let coilLength = hypot(coilEnd.x - coilStart.x, coilEnd.y - coilStart.y)

        let path = CGMutablePath()
        path.move(to: upper)
        path.addLine(to: coilStart)
        for index in 1...5 {
            let fraction = CGFloat(index) / 6.0
            let offset = index.isMultiple(of: 2) ? CGFloat(-4) : CGFloat(4)
            path.addLine(to: CGPoint(
                x: coilStart.x + axis.dx * coilLength * fraction + normal.dx * offset,
                y: coilStart.y + axis.dy * coilLength * fraction + normal.dy * offset
            ))
        }
        path.addLine(to: coilEnd)
        path.addLine(to: lower)

        shock.path = path
        shock.strokeColor = SKColor(red: 0.85, green: 0.88, blue: 0.90, alpha: 1)
        shock.lineWidth = 2.5
        shock.lineCap = .round
    }

    private func updateForkVisual() {
        let headTube = convert(BikeGeometry.headTubeBottom, from: chassis)
        let forkDrop = convert(CGPoint(x: -18, y: 38), from: frontFork)
        let path = CGMutablePath()
        path.move(to: headTube)
        path.addLine(to: forkDrop)
        forkStanchion.path = path
        forkStanchion.strokeColor = SKColor(red: 0.88, green: 0.74, blue: 0.44, alpha: 1)
        forkStanchion.lineWidth = 3.5
        forkStanchion.lineCap = .round
    }

    private func updateRiderPose(deltaTime: TimeInterval, leanInput: CGFloat, pedalHeld: Bool) {
        guard rider.parent == bikeArtwork else { return }
        let targetX: CGFloat = leanInput * -8.0
        let targetY: CGFloat = (abs(leanInput) > 0 || pedalHeld) ? -3.0 : 0.0
        let targetRot: CGFloat = leanInput * 0.12
        let lerpRate = min(CGFloat(deltaTime) * 12.0, 1.0)
        rider.position.x += (targetX - rider.position.x) * lerpRate
        rider.position.y += (targetY - rider.position.y) * lerpRate
        rider.zRotation += (targetRot - rider.zRotation) * lerpRate
    }

    private func configurePhysics() {
        let framePath = CGMutablePath()
        guard let firstVertex = GameTuning.Bike.frameCollisionVertices.first else {
            preconditionFailure("Bike frame collider needs vertices.")
        }
        framePath.move(to: firstVertex)
        GameTuning.Bike.frameCollisionVertices.dropFirst().forEach {
            framePath.addLine(to: $0)
        }
        framePath.closeSubpath()

        let cBody = SKPhysicsBody(polygonFrom: framePath)
        cBody.mass = GameTuning.Bike.chassisMass
        cBody.linearDamping = GameTuning.Bike.chassisLinearDamping
        cBody.angularDamping = GameTuning.Bike.chassisAngularDamping
        cBody.friction = GameTuning.Bike.tireFriction
        cBody.restitution = GameTuning.Bike.restitution
        cBody.affectedByGravity = true
        cBody.allowsRotation = true
        cBody.usesPreciseCollisionDetection = true
        cBody.categoryBitMask = PhysicsCategory.bike | PhysicsCategory.bikeChassis
        cBody.collisionBitMask = PhysicsCategory.terrain
        cBody.contactTestBitMask = PhysicsCategory.terrain
        chassis.physicsBody = cBody

        let swingarmPath = CGMutablePath()
        swingarmPath.move(to: .zero)
        swingarmPath.addLine(to: GameTuning.Bike.rearAxleLocal)
        swingarmPath.addLine(to: GameTuning.Bike.swingarmShockMountLocal)
        swingarmPath.closeSubpath()

        let sBody = SKPhysicsBody(polygonFrom: swingarmPath)
        sBody.mass = GameTuning.Bike.swingarmMass
        sBody.linearDamping = GameTuning.Bike.componentLinearDamping
        sBody.angularDamping = GameTuning.Bike.swingarmAngularDamping
        sBody.friction = GameTuning.Bike.tireFriction
        sBody.restitution = GameTuning.Bike.restitution
        sBody.affectedByGravity = true
        sBody.allowsRotation = true
        sBody.usesPreciseCollisionDetection = true
        sBody.categoryBitMask = PhysicsCategory.bike | PhysicsCategory.bikeSwingarm
        sBody.collisionBitMask = PhysicsCategory.terrain
        sBody.contactTestBitMask = PhysicsCategory.terrain
        swingarm.physicsBody = sBody

        let rwBody = SKPhysicsBody(circleOfRadius: GameTuning.Bike.collisionWheelRadius)
        rwBody.mass = GameTuning.Bike.rearWheelMass
        rwBody.linearDamping = GameTuning.Bike.componentLinearDamping
        rwBody.angularDamping = GameTuning.Bike.wheelAngularDamping
        rwBody.friction = GameTuning.Bike.tireFriction
        rwBody.restitution = GameTuning.Bike.restitution
        rwBody.affectedByGravity = true
        rwBody.allowsRotation = true
        rwBody.usesPreciseCollisionDetection = true
        rwBody.categoryBitMask = PhysicsCategory.bike | PhysicsCategory.bikeWheel
        rwBody.collisionBitMask = PhysicsCategory.terrain
        rwBody.contactTestBitMask = PhysicsCategory.terrain
        rearWheel.physicsBody = rwBody

        let fwBody = SKPhysicsBody(circleOfRadius: GameTuning.Bike.collisionWheelRadius)
        fwBody.mass = GameTuning.Bike.frontWheelMass
        fwBody.linearDamping = GameTuning.Bike.componentLinearDamping
        fwBody.angularDamping = GameTuning.Bike.wheelAngularDamping
        fwBody.friction = GameTuning.Bike.tireFriction
        fwBody.restitution = GameTuning.Bike.restitution
        fwBody.affectedByGravity = true
        fwBody.allowsRotation = true
        fwBody.usesPreciseCollisionDetection = true
        fwBody.categoryBitMask = PhysicsCategory.bike | PhysicsCategory.bikeWheel
        fwBody.collisionBitMask = PhysicsCategory.terrain
        fwBody.contactTestBitMask = PhysicsCategory.terrain
        frontWheel.physicsBody = fwBody

        let forkPath = CGMutablePath()
        forkPath.move(to: .zero)
        forkPath.addLine(to: CGPoint(x: -12, y: 26))
        forkPath.addLine(to: CGPoint(x: -8, y: 28))
        forkPath.addLine(to: CGPoint(x: 4, y: 1))
        forkPath.closeSubpath()

        let ffBody = SKPhysicsBody(polygonFrom: forkPath)
        ffBody.mass = GameTuning.Bike.frontForkMass
        ffBody.linearDamping = GameTuning.Bike.componentLinearDamping
        ffBody.angularDamping = GameTuning.Bike.frontForkAngularDamping
        ffBody.friction = GameTuning.Bike.tireFriction
        ffBody.restitution = GameTuning.Bike.restitution
        ffBody.affectedByGravity = true
        ffBody.allowsRotation = true
        ffBody.usesPreciseCollisionDetection = true
        ffBody.categoryBitMask = PhysicsCategory.bike | PhysicsCategory.bikeFrontFork
        ffBody.collisionBitMask = PhysicsCategory.terrain
        ffBody.contactTestBitMask = PhysicsCategory.terrain
        frontFork.physicsBody = ffBody
    }

    private func buildBike() {
        let frameColor = SKColor(red: 0.96, green: 0.43, blue: 0.12, alpha: 1)
        let frameShade = SKColor(red: 0.43, green: 0.14, blue: 0.07, alpha: 1)
        let forkColor = SKColor(red: 0.15, green: 0.24, blue: 0.30, alpha: 1)
        let tireColor = SKColor(red: 0.035, green: 0.06, blue: 0.08, alpha: 1)
        let rimColor = SKColor(red: 0.78, green: 0.88, blue: 0.90, alpha: 1)

        configureWheelVisual(rearWheel, tireColor: tireColor, rimColor: rimColor)
        configureWheelVisual(frontWheel, tireColor: tireColor, rimColor: rimColor)
        rearWheel.position = GameTuning.Bike.rearAxleOffset
        frontWheel.position = GameTuning.Bike.frontAxleOffset
        swingarm.position = GameTuning.Bike.chassisPivotOffset
        frontFork.position = GameTuning.Bike.frontAxleOffset

        // A readable hardtail-silhouette front triangle, seat post, and fork stanchions.
        bikeArtwork.addChild(tube(
            from: BikeGeometry.bottomBracket,
            to: BikeGeometry.seatCluster,
            color: frameColor,
            width: 7
        ))
        bikeArtwork.addChild(tube(
            from: BikeGeometry.seatCluster,
            to: BikeGeometry.headTubeTop,
            color: frameColor,
            width: 7
        ))
        bikeArtwork.addChild(tube(
            from: BikeGeometry.headTubeBottom,
            to: BikeGeometry.bottomBracket,
            color: frameColor,
            width: 8
        ))
        bikeArtwork.addChild(tube(
            from: BikeGeometry.headTubeBottom,
            to: BikeGeometry.headTubeTop,
            color: frameShade,
            width: 8
        ))
        bikeArtwork.addChild(tube(
            from: BikeGeometry.headTubeTop,
            to: CGPoint(x: 21, y: -5),
            color: forkColor,
            width: 7
        ))
        bikeArtwork.addChild(tube(
            from: BikeGeometry.seatCluster,
            to: BikeGeometry.seatPostTop,
            color: frameShade,
            width: 5
        ))
        bikeArtwork.addChild(tube(
            from: BikeGeometry.headTubeTop,
            to: BikeGeometry.stemEnd,
            color: forkColor,
            width: 4
        ))
        bikeArtwork.addChild(tube(
            from: BikeGeometry.handlebarLeft,
            to: BikeGeometry.handlebarRight,
            color: rimColor,
            width: 4
        ))

        let saddle = SKShapeNode(rectOf: CGSize(width: 18, height: 5), cornerRadius: 2.5)
        saddle.fillColor = tireColor
        saddle.strokeColor = .clear
        saddle.position = BikeGeometry.seatPostTop
        saddle.zRotation = 0.08
        bikeArtwork.addChild(saddle)

        let crank = SKShapeNode(circleOfRadius: 4)
        crank.fillColor = rimColor
        crank.strokeColor = .clear
        crank.position = BikeGeometry.bottomBracket
        bikeArtwork.addChild(crank)
        bikeArtwork.addChild(tube(
            from: BikeGeometry.bottomBracket,
            to: BikeGeometry.pedal,
            color: rimColor,
            width: 2
        ))

        buildRider()

        // Rear triangle on swingarm
        swingarmArtwork.addChild(tube(
            from: .zero,
            to: GameTuning.Bike.rearAxleLocal,
            color: frameShade,
            width: 6
        ))
        swingarmArtwork.addChild(tube(
            from: GameTuning.Bike.rearAxleLocal,
            to: GameTuning.Bike.swingarmShockMountLocal,
            color: frameShade,
            width: 5
        ))
        swingarmArtwork.addChild(tube(
            from: .zero,
            to: GameTuning.Bike.swingarmShockMountLocal,
            color: frameColor,
            width: 5
        ))
        swingarm.addChild(swingarmArtwork)

        // Front fork lower legs (lowers) sliding over stanchions
        frontForkArtwork.addChild(tube(
            from: CGPoint(x: -18, y: 38),
            to: .zero,
            color: forkColor,
            width: 7
        ))
        frontFork.addChild(frontForkArtwork)
        chassis.addChild(bikeArtwork)
        addChild(swingarm)
        addChild(frontFork)
        addChild(chassis)
        addChild(rearWheel)
        addChild(frontWheel)
        addChild(shock)
        addChild(forkStanchion)
    }

    private func buildRider() {
        let jersey = SKColor(red: 0.10, green: 0.46, blue: 0.82, alpha: 1)
        let pants = SKColor(red: 0.10, green: 0.16, blue: 0.25, alpha: 1)
        let skin = SKColor(red: 0.96, green: 0.69, blue: 0.48, alpha: 1)

        rider.addChild(tube(
            from: BikeGeometry.riderHip,
            to: BikeGeometry.riderShoulder,
            color: jersey,
            width: 10
        ))
        rider.addChild(tube(
            from: BikeGeometry.riderShoulder,
            to: BikeGeometry.riderElbow,
            color: jersey,
            width: 5
        ))
        rider.addChild(tube(
            from: BikeGeometry.riderElbow,
            to: BikeGeometry.handlebarRight,
            color: skin,
            width: 4
        ))
        rider.addChild(tube(
            from: BikeGeometry.riderHip,
            to: BikeGeometry.rearKnee,
            color: pants,
            width: 7
        ))
        rider.addChild(tube(
            from: BikeGeometry.rearKnee,
            to: BikeGeometry.pedal,
            color: pants,
            width: 6
        ))
        rider.addChild(tube(
            from: BikeGeometry.riderHip,
            to: BikeGeometry.frontKnee,
            color: pants,
            width: 7
        ))
        rider.addChild(tube(
            from: BikeGeometry.frontKnee,
            to: BikeGeometry.frontPedal,
            color: pants,
            width: 6
        ))

        let head = SKShapeNode(circleOfRadius: 7)
        head.fillColor = skin
        head.strokeColor = .clear
        head.position = BikeGeometry.riderHead
        rider.addChild(head)

        let helmet = SKShapeNode(circleOfRadius: 8)
        helmet.fillColor = SKColor(red: 0.08, green: 0.15, blue: 0.24, alpha: 1)
        helmet.strokeColor = .clear
        helmet.position = CGPoint(x: BikeGeometry.riderHead.x - 1, y: BikeGeometry.riderHead.y + 4)
        helmet.yScale = 0.58
        rider.addChild(helmet)

        rider.zPosition = 3
        bikeArtwork.addChild(rider)
    }

    private func configureWheelVisual(
        _ wheel: SKShapeNode,
        tireColor: SKColor,
        rimColor: SKColor
    ) {
        wheel.fillColor = tireColor
        wheel.strokeColor = SKColor(white: 0.01, alpha: 1)
        wheel.lineWidth = 2

        let rim = SKShapeNode(circleOfRadius: GameTuning.Bike.visualWheelRadius - 4)
        rim.fillColor = .clear
        rim.strokeColor = rimColor
        rim.lineWidth = 1.7
        wheel.addChild(rim)

        let hub = SKShapeNode(circleOfRadius: 2.5)
        hub.fillColor = rimColor
        hub.strokeColor = .clear
        wheel.addChild(hub)

        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 5) {
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(
                x: CGFloat(cos(angle)) * (GameTuning.Bike.visualWheelRadius - 5),
                y: CGFloat(sin(angle)) * (GameTuning.Bike.visualWheelRadius - 5)
            ))
            let spoke = SKShapeNode(path: path)
            spoke.strokeColor = SKColor(white: 0.82, alpha: 0.70)
            spoke.lineWidth = 0.9
            wheel.addChild(spoke)
        }
    }

    private func tube(from start: CGPoint, to end: CGPoint, color: SKColor, width: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.lineWidth = width
        node.lineCap = .round
        return node
    }

    private enum BikeGeometry {
        static let frontAxle = GameTuning.Bike.frontAxleOffset
        static let rearAxle = GameTuning.Bike.rearAxleOffset
        static let bottomBracket = CGPoint(x: -5, y: -13)
        static let seatCluster = CGPoint(x: -18, y: 12)
        static let seatPostTop = CGPoint(x: -20, y: 23)
        static let headTubeBottom = CGPoint(x: 15, y: 6)
        static let headTubeTop = CGPoint(x: 12, y: 17)
        static let stemEnd = CGPoint(x: 17, y: 22)
        static let handlebarLeft = CGPoint(x: 15, y: 22)
        static let handlebarRight = CGPoint(x: 22, y: 21)
        static let pedal = CGPoint(x: -10, y: -16)
        static let frontPedal = CGPoint(x: 0, y: -10)
        static let riderHip = CGPoint(x: -18, y: 27)
        static let riderShoulder = CGPoint(x: -6, y: 43)
        static let riderElbow = CGPoint(x: 8, y: 33)
        static let riderHead = CGPoint(x: -1, y: 51)
        static let rearKnee = CGPoint(x: -21, y: 5)
        static let frontKnee = CGPoint(x: -2, y: 4)
    }
}
