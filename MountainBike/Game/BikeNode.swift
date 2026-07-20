import SpriteKit

final class BikeNode: SKNode {
    private let rearWheel = SKShapeNode(circleOfRadius: GameTuning.Bike.visualWheelRadius)
    private let frontWheel = SKShapeNode(circleOfRadius: GameTuning.Bike.visualWheelRadius)
    private let rider = SKNode()

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

    func prepareForSpawn() {
        guard let body = physicsBody else { return }
        body.isDynamic = false
        body.velocity = .zero
        body.angularVelocity = 0
    }

    func freezePhysics() {
        guard let body = physicsBody else { return }
        body.velocity = .zero
        body.angularVelocity = 0
        body.isDynamic = false
    }

    func spin(by horizontalDistance: CGFloat) {
        let rotation = horizontalDistance / GameTuning.Bike.visualWheelRadius
        rearWheel.zRotation -= rotation
        frontWheel.zRotation -= rotation
    }

    func resetAppearance() {
        removeAllActions()
        rider.removeAllActions()
        rider.position = .zero
        rider.zRotation = 0
        alpha = 1
        rider.alpha = 1
        setScale(1)
    }

    func crash() {
        run(.sequence([
            .group([
                .rotate(byAngle: 0.72, duration: 0.18),
                .fadeAlpha(to: 0.86, duration: 0.18)
            ]),
            .wait(forDuration: 0.10)
        ]))
        rider.run(.sequence([
            .rotate(byAngle: -0.72, duration: 0.16),
            .moveBy(x: 7, y: 12, duration: 0.16)
        ]))
    }

    private func configurePhysics() {
        // Two rounded tire contacts share one compound rigid body. Unlike a
        // capsule, this lets the bike pivot around one tire and lift the other.
        let rearTire = SKPhysicsBody(
            circleOfRadius: GameTuning.Bike.collisionWheelRadius,
            center: CGPoint(x: -GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY)
        )
        let frontTire = SKPhysicsBody(
            circleOfRadius: GameTuning.Bike.collisionWheelRadius,
            center: CGPoint(x: GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY)
        )
        // This small, high guard only protects the tire gap during a deep
        // landing. Keeping it above the tire contact envelope means a slow
        // approach meets a rollable lip with a tire instead of hooking the
        // middle of the chassis on the edge.
        let frameGuard = SKPhysicsBody(
            circleOfRadius: GameTuning.Bike.frameGuardRadius,
            center: CGPoint(x: 0, y: GameTuning.Bike.frameGuardOffsetY)
        )
        let body = SKPhysicsBody(bodies: [rearTire, frontTire, frameGuard])
        body.mass = GameTuning.Bike.mass
        body.linearDamping = GameTuning.Bike.groundLinearDamping
        body.angularDamping = GameTuning.Handling.groundAngularDamping
        body.friction = GameTuning.Bike.friction
        body.restitution = GameTuning.Bike.restitution
        body.allowsRotation = true
        body.affectedByGravity = true
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = PhysicsCategory.bike
        body.collisionBitMask = PhysicsCategory.terrain
        body.contactTestBitMask = PhysicsCategory.terrain
        physicsBody = body
    }

    private func buildBike() {
        let wheelColor = SKColor(red: 0.05, green: 0.09, blue: 0.12, alpha: 1)
        let rimColor = SKColor(red: 0.74, green: 0.86, blue: 0.86, alpha: 1)
        let rearPosition = CGPoint(x: -GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY)
        let frontPosition = CGPoint(x: GameTuning.Bike.wheelOffsetX, y: GameTuning.Bike.wheelOffsetY)

        configureWheel(rearWheel, at: rearPosition, wheelColor: wheelColor, rimColor: rimColor)
        configureWheel(frontWheel, at: frontPosition, wheelColor: wheelColor, rimColor: rimColor)
        addChild(rearWheel)
        addChild(frontWheel)

        let framePath = CGMutablePath()
        framePath.move(to: rearPosition)
        framePath.addLine(to: CGPoint(x: -5, y: 18))
        framePath.addLine(to: CGPoint(x: 12, y: GameTuning.Bike.wheelOffsetY))
        framePath.addLine(to: rearPosition)
        framePath.move(to: CGPoint(x: -5, y: 18))
        framePath.addLine(to: CGPoint(x: 20, y: 20))
        framePath.addLine(to: frontPosition)
        framePath.move(to: CGPoint(x: -7, y: 18))
        framePath.addLine(to: CGPoint(x: -14, y: 26))

        let frame = SKShapeNode(path: framePath)
        frame.strokeColor = SKColor(red: 0.10, green: 0.88, blue: 0.66, alpha: 1)
        frame.lineWidth = 4
        frame.lineCap = .round
        frame.lineJoin = .round
        addChild(frame)

        let handlebar = SKShapeNode(rectOf: CGSize(width: 14, height: 3), cornerRadius: 1.5)
        handlebar.fillColor = rimColor
        handlebar.strokeColor = .clear
        handlebar.position = CGPoint(x: 21, y: 22)
        handlebar.zRotation = 0.18
        addChild(handlebar)

        let body = SKShapeNode(rectOf: CGSize(width: 9, height: 22), cornerRadius: 4.5)
        body.fillColor = SKColor(red: 0.96, green: 0.31, blue: 0.21, alpha: 1)
        body.strokeColor = .clear
        body.position = CGPoint(x: -8, y: 39)
        body.zRotation = -0.36
        rider.addChild(body)

        let head = SKShapeNode(circleOfRadius: 7)
        head.fillColor = SKColor(red: 1.0, green: 0.75, blue: 0.52, alpha: 1)
        head.strokeColor = .clear
        head.position = CGPoint(x: 1, y: 52)
        rider.addChild(head)

        let helmet = SKShapeNode(circleOfRadius: 8)
        helmet.fillColor = SKColor(red: 0.16, green: 0.25, blue: 0.42, alpha: 1)
        helmet.strokeColor = .clear
        helmet.position = CGPoint(x: 1, y: 55)
        helmet.yScale = 0.58
        rider.addChild(helmet)

        let armPath = CGMutablePath()
        armPath.move(to: CGPoint(x: -3, y: 43))
        armPath.addLine(to: CGPoint(x: 15, y: 25))
        let arm = SKShapeNode(path: armPath)
        arm.strokeColor = SKColor(red: 0.96, green: 0.31, blue: 0.21, alpha: 1)
        arm.lineWidth = 5
        arm.lineCap = .round
        rider.addChild(arm)

        addChild(rider)
    }

    private func configureWheel(_ wheel: SKShapeNode, at position: CGPoint, wheelColor: SKColor, rimColor: SKColor) {
        wheel.fillColor = wheelColor
        wheel.strokeColor = rimColor
        wheel.lineWidth = 2.5
        wheel.position = position

        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 3) {
            let spoke = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(
                x: CGFloat(cos(angle)) * (GameTuning.Bike.visualWheelRadius - 3),
                y: CGFloat(sin(angle)) * (GameTuning.Bike.visualWheelRadius - 3)
            ))
            spoke.path = path
            spoke.strokeColor = SKColor(white: 0.76, alpha: 0.64)
            spoke.lineWidth = 1
            wheel.addChild(spoke)
        }
    }
}
