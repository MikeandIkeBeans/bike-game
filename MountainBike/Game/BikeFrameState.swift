import SpriteKit

/// A snapshot of all physics-relevant state computed once at the top of each
/// frame. Every downstream physics method reads from this instead of
/// recomputing contact and terrain queries multiple times per step.
struct BikeFrameState {

    // MARK: - Bike pose

    let chassisPosition: CGPoint
    let chassisRotation: CGFloat
    let velocity: CGVector
    let speed: CGFloat
    let rearAxlePosition: CGPoint
    let frontAxlePosition: CGPoint

    // MARK: - Ground contact

    let isRearWheelGrounded: Bool
    let isFrontWheelGrounded: Bool
    var isGrounded: Bool { isRearWheelGrounded || isFrontWheelGrounded }
    var areBothWheelsGrounded: Bool { isRearWheelGrounded && isFrontWheelGrounded }

    // MARK: - Flight classification

    /// True when the bike is airborne and that flight is expected: over a void,
    /// inside an authored launch zone, or performing a manual bunnyhop.
    let isEarnedJumpFlight: Bool

    // MARK: - Terrain queries (cached for this frame)

    /// Surface height at the chassis x-position, or nil if over a gap.
    let surfaceHeightAtChassis: CGFloat?
    /// Surface slope at the chassis x-position, or nil if unavailable.
    let surfaceSlopeAtChassis: CGFloat?
    /// The terrain support angle at the chassis x-position.
    let supportAngle: CGFloat
    /// Best-available terrain tangent sampled from rear axle, front axle, or
    /// chassis — the same priority order used by pedal drive and braking.
    let terrainTangent: CGVector?

    // MARK: - Timing

    let deltaTime: TimeInterval
    let elapsedRunTime: TimeInterval

    // MARK: - Chassis contact with terrain (for frame-strike detection)

    let isChassisContactingTerrain: Bool
}
