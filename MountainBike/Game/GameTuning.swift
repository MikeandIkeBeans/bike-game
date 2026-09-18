import Foundation
import SpriteKit

struct DownhillFeatureProfile {
    let length: ClosedRange<CGFloat>
    let drop: ClosedRange<CGFloat>
    let firstControlFraction: ClosedRange<CGFloat>
    let secondControlFraction: ClosedRange<CGFloat>
    let firstDropFraction: ClosedRange<CGFloat>
    let secondDropFraction: ClosedRange<CGFloat>
    let entrySlope: ClosedRange<CGFloat>
    let middleSlope: ClosedRange<CGFloat>
}

struct DownhillRollerProfile {
    let length: ClosedRange<CGFloat>
    let drop: ClosedRange<CGFloat>
    let firstControlFraction: ClosedRange<CGFloat>
    let secondControlFraction: ClosedRange<CGFloat>
    let thirdControlFraction: ClosedRange<CGFloat>
    let firstDropFraction: ClosedRange<CGFloat>
    let secondDropFraction: ClosedRange<CGFloat>
    let thirdDropFraction: ClosedRange<CGFloat>
    let entrySlope: ClosedRange<CGFloat>
    let firstSlope: ClosedRange<CGFloat>
    let secondSlope: ClosedRange<CGFloat>
}

struct DownhillLipProfile {
    let length: ClosedRange<CGFloat>
    let drop: ClosedRange<CGFloat>
    let approachControlFraction: ClosedRange<CGFloat>
    let crestOffsetFraction: ClosedRange<CGFloat>
    let approachDropFraction: ClosedRange<CGFloat>
    let approachLengthDropFraction: ClosedRange<CGFloat>
    let climb: ClosedRange<CGFloat>
    let lipDrop: ClosedRange<CGFloat>
    let troughSlope: ClosedRange<CGFloat>
    let crestSlope: ClosedRange<CGFloat>
}

struct DownhillChuteProfile {
    let length: ClosedRange<CGFloat>
    let drop: ClosedRange<CGFloat>
    let entryControlFraction: ClosedRange<CGFloat>
    let plungeControlFraction: ClosedRange<CGFloat>
    let compressionControlFraction: ClosedRange<CGFloat>
    let entryDropFraction: ClosedRange<CGFloat>
    let plungeDropFraction: ClosedRange<CGFloat>
    let compressionTailDrop: ClosedRange<CGFloat>
    let entrySlope: ClosedRange<CGFloat>
    let plungeSlope: ClosedRange<CGFloat>
    let compressionSlope: ClosedRange<CGFloat>
    let exitSlope: ClosedRange<CGFloat>
}

struct DownhillStepDownProfile {
    let length: ClosedRange<CGFloat>
    let drop: ClosedRange<CGFloat>
    let approachControlFraction: ClosedRange<CGFloat>
    let crestControlFraction: ClosedRange<CGFloat>
    let cliffLengthFraction: ClosedRange<CGFloat>
    let landingLengthFraction: ClosedRange<CGFloat>
    let approachDropFraction: ClosedRange<CGFloat>
    let climb: ClosedRange<CGFloat>
    let cliffDropFraction: ClosedRange<CGFloat>
    let landingDropFraction: ClosedRange<CGFloat>
    let troughSlope: ClosedRange<CGFloat>
    let crestSlope: ClosedRange<CGFloat>
    let cliffSlope: ClosedRange<CGFloat>
    let landingSlope: ClosedRange<CGFloat>
    let exitSlope: ClosedRange<CGFloat>
}

/// One broad terrain phrase. The grammar chooses the relative frequency of
/// terrain forms while the individual feature profiles keep every instance
/// physically varied.
struct TerrainGrammarProfile {
    let minimumFeatureCount: Int
    let jumpBaseProbability: CGFloat
    let jumpProbabilityIncreasePerNonJump: CGFloat
    let maximumJumpProbability: CGFloat
    let stepDownShareOfJumps: CGFloat
    let flowWeight: CGFloat
    let swoopWeight: CGFloat
    let chuteWeight: CGFloat
    let rollerWeight: CGFloat
    let benchWeight: CGFloat
}

/// The only place to tune Bike Game's gameplay feel and physics behaviour.
/// Keep visual styling and layout constants out of this file.
enum GameTuning {
    enum Simulation {
        static let targetFramesPerSecond = 60
        static let maximumFrameDelta: TimeInterval = 1.0 / 20.0
        /// SpriteKit's coordinates are visual units, so this converts a
        /// familiar Earth gravity into the scale used by the moving terrain.
        /// Gravity stays constant on ground and in the air; no launch-specific
        /// multiplier is ever applied.
        static let worldUnitsPerPhysicsMeter: CGFloat = 6.0
        static let earthGravityMetersPerSecondSquared: CGFloat = 9.81
        static let gravity = CGVector(
            dx: 0,
            dy: -earthGravityMetersPerSecondSquared * worldUnitsPerPhysicsMeter
        )
    }

    enum Bike {
        static let visualWheelRadius: CGFloat = 17
        /// Wheelbase stays visible to terrain-support queries while the tire
        /// fixtures remain part of the one compound bike body.
        static let wheelOffsetX: CGFloat = 30
        static let wheelOffsetY: CGFloat = -27
        static let collisionWheelRadius: CGFloat = 16
        static let spawnX: CGFloat = 0
        /// Start exactly at the slope-aware tire clearance so the first
        /// physics frame does not turn a drop onto one tire into a launch.
        static let spawnContactPadding: CGFloat = 0
        static let spawnPitchLockDuration: TimeInterval = 0
        /// Guards the spawn calculation if an authored rail ever approaches a
        /// vertical tangent. Normal course slopes stay well above this value.
        static let minimumSpawnCosine: CGFloat = 0.35
        static let startVelocity = CGVector.zero
        static let frameGuardRadius: CGFloat = 10
        static let frameGuardOffsetY: CGFloat = 0

        /// Mass and damping for the multi-body suspension bike chassis.
        static let chassisMass: CGFloat = 3.4
        static let chassisLinearDamping: CGFloat = 0.002
        static let chassisAngularDamping: CGFloat = 3.50
        /// Multi-body live rear suspension masses and damping.
        static let swingarmMass: CGFloat = 1.00
        static let rearWheelMass: CGFloat = 1.00
        static let frontWheelMass: CGFloat = 0.70
        static let componentLinearDamping: CGFloat = 0.002
        static let swingarmAngularDamping: CGFloat = 1.50
        static let wheelAngularDamping: CGFloat = 0.25
        /// Live suspension linkage geometry matching the classic hardtail silhouette.
        static let chassisPivotOffset = CGPoint(x: -5, y: -13)
        static let chassisShockMountOffset = CGPoint(x: -14, y: 3)
        static let swingarmShockMountLocal = CGPoint(x: -12, y: -4)
        static let rearAxleLocal = CGPoint(x: -25, y: -14)
        /// Travel stops, joint friction, and spring rates for the rear shock.
        static let lowerTravelAngle: CGFloat = -0.02
        static let upperTravelAngle: CGFloat = 0.05
        static let pivotFrictionTorque: CGFloat = 1.50
        static let springFrequency: CGFloat = 15.0
        static let springDamping: CGFloat = 0.97
        static let topOutStrapExtraLength: CGFloat = 0.2
        /// Live telescoping front fork suspension masses, damping, and travel limits.
        static let frontForkMass: CGFloat = 0.50
        static let frontForkAngularDamping: CGFloat = 1.20
        static let frontForkAxis = CGVector(dx: -0.414, dy: 0.910)
        static let frontSpringFrequency: CGFloat = 16.0
        static let frontSpringDamping: CGFloat = 0.97
        static let frontLowerTravelLimit: CGFloat = -4.0
        static let frontUpperTravelLimit: CGFloat = 0.0
        /// Visual-only wheels cannot spin their own bodies to overcome static
        /// friction. Low friction lets the compound body slide smoothly while
        /// the visual wheels roll from real travel.
        static let tireFriction: CGFloat = 1.10
        static let restitution: CGFloat = 0.08
        static let maximumSpeed: CGFloat = 4_000
        static let maximumChassisAngularVelocity: CGFloat = 4.0
        static let groundedTolerance: CGFloat = 8
        /// A generous multiple of the bike's own resting size (wheels sit
        /// ~40 units from the chassis at rest). Past this, a body has not
        /// just compressed its suspension hard — the joint solver failed to
        /// resolve the impact, and the rig gets snapped back together
        /// instead of rendering the drifted position.
        static let maximumJointDriftBeforeRepair: CGFloat = 250

        static let rearAxleOffset = CGPoint(x: -wheelOffsetX, y: wheelOffsetY)
        static let frontAxleOffset = CGPoint(x: wheelOffsetX, y: wheelOffsetY)
        /// A compact, convex fixture for the visible frame. It is combined
        /// with both tire fixtures into one rigid body; it is never a
        /// separate chassis or suspension body.
        static let frameCollisionVertices: [CGPoint] = [
            CGPoint(x: -20, y: -8),
            CGPoint(x: 22, y: -8),
            CGPoint(x: 22, y: 16),
            CGPoint(x: -16, y: 22)
        ]
    }

    enum Terrain {
        /// Finer rails follow the visual curve closely, avoiding sharp normal
        /// changes that bleed a downhill run's stored velocity.
        static let maximumColliderSegmentLength: CGFloat = 5
        static let friction: CGFloat = 1.10
        static let restitution: CGFloat = 0.08
        /// SpriteKit's edge rails can rarely leave a tire just across the
        /// wrong side of a landing. Only this shallow overlap is nudged back;
        /// a deep miss must never become a free ride to the top of a jump.
        static let wheelPenetrationRecoveryTrigger: CGFloat = 6
        static let wheelPenetrationRecoveryClearance: CGFloat = 1
        static let wheelPenetrationMaximumPivot: CGFloat = 0.42
        /// A landing face gets enough horizontal run for its vertical drop.
        /// This prevents a nominally smooth lip from sampling into a narrow,
        /// skewer-like downslope that can swallow a tire.
        static let maximumLandingApproachSlope: CGFloat = 0.56
        /// Big launch features descend through a real, continuous cliff face.
        /// This is deliberately steep, but never a vertical collision rail.
        static let maximumContinuousCliffSlope: CGFloat = 0.82
        /// Generated trough exits must have enough horizontal room for a bike
        /// to roll out instead of becoming a divot with a near-vertical wall.
        static let minimumRollableRampLength: CGFloat = 78
        static let maximumRollableUphillSlope: CGFloat = 0.54
        static let maximumUphillSlopeSwingPerLength: CGFloat = 0.02
        /// The final part of each takeoff is a smooth, rising arc rather than
        /// a pointed endpoint. Its physical tangent is the only launch source.
        /// It is steeper than an ordinary rollable ramp only at the release,
        /// giving a fast rider real vertical velocity without a fake impulse.
        static let roundedTakeoffLength: CGFloat = 100
        static let roundedTakeoffRise: CGFloat = 47
        static let roundedTakeoffEndSlope: CGFloat = 0.72
        /// This short, smooth fall-away makes a lip physically release a fast
        /// bike through curvature, then continues into a real landing surface.
        static let roundedReleaseLength: CGFloat = 64
        static let roundedReleaseDrop: CGFloat = 38
        static let roundedReleaseEndSlope: CGFloat = -0.80
        /// Ordinary lips land back onto a long rounded hill rather than a
        /// mandatory gap. A fast rider can still get air over the convex crest.
        static let roundedLipLandingLength: ClosedRange<CGFloat> = 145...185
        /// Step-downs remain the large-air features, but their launch is a
        /// rollable arc: the bike can bring chute momentum into the descent.
        static let stepDownTakeoffLength: CGFloat = 112
        static let stepDownTakeoffRise: CGFloat = 54
        static let stepDownTakeoffEndSlope: CGFloat = 0.78
        static let stepDownReleaseLength: CGFloat = 76
        static let stepDownReleaseDrop: CGFloat = 56
        static let stepDownReleaseEndSlope: CGFloat = -0.96
        static let lipLandingEntrySlope: CGFloat = -0.28
        /// Long downhill catch surfaces let a fast, natural launch rejoin the
        /// trail instead of sailing past a short landing strip.
        static let lipLandingRunout: CGFloat = 360
        static let lipLandingRunoutSlope: CGFloat = -0.18
        static let stepDownLandingRunout: CGFloat = 500

        /// The stream is composed of immutable, world-space chunks. Keeping a
        /// generous live window means chunks are never rebuilt beneath the bike.
        static let streamStartX: CGFloat = -480
        static let streamStartY: CGFloat = 540
        static let streamAheadDistance: CGFloat = 1_800
        static let streamRetirementDistance: CGFloat = 1_200
        static let terrainFillDepth: CGFloat = 900
        static let generatedFeaturesPerChunk = 3
        static let proceduralCourseSeed: UInt64 = 0x5452_4149_4C52_5553
        /// The run starts high in the alpine and descends below the snowline
        /// at the same distance shown in the HUD.
        static let alpineBiomeEndDistanceMeters: CGFloat = 10_000
        /// A visual-only fade keeps the mountain photo from changing abruptly.
        static let alpineBiomeBlendDistanceMeters: CGFloat = 850
        /// One complete 20-biome descent spans 32 km before the stream begins
        /// a new randomized pass through the same named regions.
        static let biomeZoneLengthMeters: CGFloat = 700

        /// The rider spawns part-way down this committed alpine drop, rather
        /// than on a long flat, so gravity immediately makes control matter.
        static let openingFirstFlatLength: CGFloat = 250
        static let openingSecondFlatLength: CGFloat = 45
        static let openingGentleDropLength: CGFloat = 300
        static let openingExitLength: CGFloat = 130
        static let openingGentleDrop: CGFloat = 145
        static let openingExitDrop: CGFloat = 90
        static let openingGentleExitSlope: CGFloat = -0.46
        static let openingExitSlope: CGFloat = -0.56

        /// Grammars transition between phrases rather than randomising every
        /// feature in isolation. Individual grammar profiles choose how long
        /// their phrases must hold before they may transition.
        static let grammarTransitionChance: CGFloat = 0.85
        /// The opening still keeps its runway so the very first jump of a
        /// run is never a surprise. Once the rider has cleared that first
        /// jump, airs are allowed to chain back-to-back — each jump feature
        /// already ends on its own safely-landed exit point, so a jump right
        /// after a jump is a fast, wild gauntlet rather than an unfair one.
        static let openingMinimumNonJumpFeaturesBeforeFirstJump = 1
        static let minimumNonJumpFeaturesBetweenJumps = 0
        static let repeatedFeatureWeightMultiplier: CGFloat = 0.15

        /// Gentle, linking terrain with occasional low-consequence airs.
        static let flowGrammar = TerrainGrammarProfile(
            minimumFeatureCount: 1,
            jumpBaseProbability: 0.30,
            jumpProbabilityIncreasePerNonJump: 0.13,
            maximumJumpProbability: 0.64,
            stepDownShareOfJumps: 0.40,
            flowWeight: 0.18,
            swoopWeight: 0.25,
            chuteWeight: 0.26,
            rollerWeight: 0.23,
            benchWeight: 0.08
        )
        /// A pumping sequence of rollers and sweeping transitions.
        static let rollerGrammar = TerrainGrammarProfile(
            minimumFeatureCount: 1,
            jumpBaseProbability: 0.34,
            jumpProbabilityIncreasePerNonJump: 0.15,
            maximumJumpProbability: 0.70,
            stepDownShareOfJumps: 0.34,
            flowWeight: 0.10,
            swoopWeight: 0.25,
            chuteWeight: 0.16,
            rollerWeight: 0.42,
            benchWeight: 0.07
        )
        /// Faster, more technical downhill terrain with regular drops.
        static let technicalGrammar = TerrainGrammarProfile(
            minimumFeatureCount: 1,
            jumpBaseProbability: 0.48,
            jumpProbabilityIncreasePerNonJump: 0.16,
            maximumJumpProbability: 0.82,
            stepDownShareOfJumps: 0.68,
            flowWeight: 0.08,
            swoopWeight: 0.16,
            chuteWeight: 0.56,
            rollerWeight: 0.13,
            benchWeight: 0.07
        )
        /// A committed jump line, separated by enough terrain to set up each
        /// takeoff rather than placing air features back-to-back.
        static let dropGrammar = TerrainGrammarProfile(
            minimumFeatureCount: 1,
            jumpBaseProbability: 0.56,
            jumpProbabilityIncreasePerNonJump: 0.15,
            maximumJumpProbability: 0.88,
            stepDownShareOfJumps: 0.86,
            flowWeight: 0.05,
            swoopWeight: 0.14,
            chuteWeight: 0.54,
            rollerWeight: 0.19,
            benchWeight: 0.08
        )
        /// Long ridgelines break up the existing downhill and jump-focused
        /// phrases with broad swoops, rollers, and a few technical chutes.
        static let ridgeGrammar = TerrainGrammarProfile(
            minimumFeatureCount: 1,
            jumpBaseProbability: 0.40,
            jumpProbabilityIncreasePerNonJump: 0.17,
            maximumJumpProbability: 0.76,
            stepDownShareOfJumps: 0.52,
            flowWeight: 0.08,
            swoopWeight: 0.34,
            chuteWeight: 0.32,
            rollerWeight: 0.20,
            benchWeight: 0.06
        )
        /// Above the snowline, broad chutes and rollers create a distinct
        /// alpine rhythm while retaining enough launch features for the speed
        /// earned on the preceding descent to matter.
        static let alpineGrammar = TerrainGrammarProfile(
            minimumFeatureCount: 1,
            jumpBaseProbability: 0.44,
            jumpProbabilityIncreasePerNonJump: 0.14,
            maximumJumpProbability: 0.80,
            stepDownShareOfJumps: 0.60,
            flowWeight: 0.07,
            swoopWeight: 0.28,
            chuteWeight: 0.38,
            rollerWeight: 0.21,
            benchWeight: 0.06
        )
        /// A committed fall-line: several intense gravity-fed chutes chain
        /// together before the grammar may switch, with large launch features
        /// inserted once the bike has earned speed.
        static let intenseDescentGrammar = TerrainGrammarProfile(
            minimumFeatureCount: 4,
            jumpBaseProbability: 0.62,
            jumpProbabilityIncreasePerNonJump: 0.17,
            maximumJumpProbability: 0.92,
            stepDownShareOfJumps: 0.94,
            flowWeight: 0.02,
            swoopWeight: 0.08,
            chuteWeight: 0.74,
            rollerWeight: 0.11,
            benchWeight: 0.05
        )

        private static func grammar(
            minimum: Int,
            jump: CGFloat,
            increase: CGFloat,
            maximum: CGFloat,
            stepDown: CGFloat,
            flow: CGFloat,
            swoop: CGFloat,
            chute: CGFloat,
            roller: CGFloat,
            bench: CGFloat
        ) -> TerrainGrammarProfile {
            TerrainGrammarProfile(
                minimumFeatureCount: minimum,
                jumpBaseProbability: jump,
                jumpProbabilityIncreasePerNonJump: increase,
                maximumJumpProbability: maximum,
                stepDownShareOfJumps: stepDown,
                flowWeight: flow,
                swoopWeight: swoop,
                chuteWeight: chute,
                rollerWeight: roller,
                benchWeight: bench
            )
        }

        // MARK: - 20 biome grammars

        static let summitSpineGrammar = grammar(minimum: 1, jump: 0.65, increase: 0.21, maximum: 0.91, stepDown: 0.66, flow: 0.02, swoop: 0.23, chute: 0.75, roller: 0.18, bench: 0.03)
        static let corniceRunGrammar = grammar(minimum: 1, jump: 0.71, increase: 0.22, maximum: 0.95, stepDown: 0.76, flow: 0.01, swoop: 0.25, chute: 0.80, roller: 0.14, bench: 0.03)
        static let icefallGrammar = grammar(minimum: 1, jump: 0.79, increase: 0.23, maximum: 0.99, stepDown: 0.88, flow: 0.01, swoop: 0.15, chute: 0.97, roller: 0.12, bench: 0.03)
        static let frostPinesGrammar = grammar(minimum: 1, jump: 0.57, increase: 0.21, maximum: 0.85, stepDown: 0.52, flow: 0.05, swoop: 0.31, chute: 0.34, roller: 0.29, bench: 0.03)
        static let moraineGrammar = grammar(minimum: 1, jump: 0.73, increase: 0.22, maximum: 0.97, stepDown: 0.80, flow: 0.02, swoop: 0.24, chute: 0.79, roller: 0.16, bench: 0.02)
        static let slateRidgeGrammar = grammar(minimum: 1, jump: 0.61, increase: 0.21, maximum: 0.89, stepDown: 0.56, flow: 0.02, swoop: 0.44, chute: 0.45, roller: 0.19, bench: 0.03)
        static let gravelChuteGrammar = grammar(minimum: 2, jump: 0.83, increase: 0.24, maximum: 0.99, stepDown: 0.95, flow: 0.01, swoop: 0.15, chute: 1.01, roller: 0.11, bench: 0.02)
        static let fernFlowGrammar = grammar(minimum: 1, jump: 0.53, increase: 0.19, maximum: 0.79, stepDown: 0.42, flow: 0.07, swoop: 0.34, chute: 0.23, roller: 0.25, bench: 0.03)
        static let canopyRollerGrammar = grammar(minimum: 1, jump: 0.59, increase: 0.20, maximum: 0.83, stepDown: 0.46, flow: 0.03, swoop: 0.28, chute: 0.21, roller: 0.47, bench: 0.03)
        static let redClayGrammar = grammar(minimum: 1, jump: 0.69, increase: 0.22, maximum: 0.95, stepDown: 0.74, flow: 0.02, swoop: 0.23, chute: 0.79, roller: 0.14, bench: 0.03)
        static let sandstoneGrammar = grammar(minimum: 1, jump: 0.76, increase: 0.23, maximum: 0.99, stepDown: 0.88, flow: 0.01, swoop: 0.28, chute: 0.75, roller: 0.16, bench: 0.03)
        static let canyonDropGrammar = grammar(minimum: 2, jump: 0.87, increase: 0.25, maximum: 0.99, stepDown: 0.99, flow: 0.01, swoop: 0.12, chute: 1.08, roller: 0.08, bench: 0.02)
        static let badlandsGrammar = grammar(minimum: 1, jump: 0.73, increase: 0.23, maximum: 0.99, stepDown: 0.84, flow: 0.02, swoop: 0.20, chute: 0.83, roller: 0.15, bench: 0.03)
        static let shaleRunGrammar = grammar(minimum: 1, jump: 0.63, increase: 0.21, maximum: 0.91, stepDown: 0.64, flow: 0.02, swoop: 0.34, chute: 0.61, roller: 0.17, bench: 0.03)
        static let volcanicGrammar = grammar(minimum: 2, jump: 0.81, increase: 0.24, maximum: 0.99, stepDown: 0.98, flow: 0.01, swoop: 0.14, chute: 1.02, roller: 0.10, bench: 0.02)
        static let ashFlowGrammar = grammar(minimum: 1, jump: 0.55, increase: 0.20, maximum: 0.81, stepDown: 0.48, flow: 0.06, swoop: 0.36, chute: 0.28, roller: 0.27, bench: 0.03)
        static let meadowGrammar = grammar(minimum: 1, jump: 0.50, increase: 0.18, maximum: 0.73, stepDown: 0.38, flow: 0.08, swoop: 0.32, chute: 0.18, roller: 0.28, bench: 0.03)
        static let riverRockGrammar = grammar(minimum: 1, jump: 0.67, increase: 0.22, maximum: 0.93, stepDown: 0.70, flow: 0.02, swoop: 0.26, chute: 0.69, roller: 0.18, bench: 0.03)
        static let coastalBluffGrammar = grammar(minimum: 2, jump: 0.85, increase: 0.24, maximum: 0.99, stepDown: 0.99, flow: 0.01, swoop: 0.18, chute: 0.98, roller: 0.10, bench: 0.02)
        static let sunsetGullyGrammar = grammar(minimum: 1, jump: 0.72, increase: 0.23, maximum: 0.98, stepDown: 0.80, flow: 0.02, swoop: 0.25, chute: 0.79, roller: 0.14, bench: 0.02)

        static let flowProfile = DownhillFeatureProfile(
            length: 220...350,
            drop: 95...155,
            firstControlFraction: 0.24...0.36,
            secondControlFraction: 0.56...0.72,
            firstDropFraction: 0.20...0.34,
            secondDropFraction: 0.60...0.82,
            entrySlope: -0.56 ... -0.26,
            middleSlope: -0.62 ... -0.26
        )
        static let swoopProfile = DownhillFeatureProfile(
            length: 240...400,
            drop: 190...290,
            firstControlFraction: 0.16...0.26,
            secondControlFraction: 0.46...0.60,
            firstDropFraction: 0.14...0.26,
            secondDropFraction: 0.58...0.78,
            entrySlope: -0.78 ... -0.36,
            middleSlope: -0.98 ... -0.46
        )
        /// First-descent fall lines use a much steeper, shorter swoop. The
        /// shape earns dangerous speed before the rider reaches a compression.
        static let extremeSwoopProfile = DownhillFeatureProfile(
            length: 260...380,
            drop: 380...520,
            firstControlFraction: 0.14...0.22,
            secondControlFraction: 0.42...0.56,
            firstDropFraction: 0.16...0.28,
            secondDropFraction: 0.64...0.82,
            entrySlope: -1.10 ... -0.72,
            middleSlope: -1.45 ... -0.90
        )
        static let chuteProfile = DownhillChuteProfile(
            /// Long, flowing chutes turn gravity into usable horizontal speed
            /// rather than dropping the bike into a momentum-killing catch.
            length: 720...900,
            drop: 700...920,
            entryControlFraction: 0.10...0.16,
            plungeControlFraction: 0.44...0.56,
            compressionControlFraction: 0.72...0.80,
            entryDropFraction: 0.06...0.10,
            plungeDropFraction: 0.64...0.74,
            compressionTailDrop: 95...140,
            entrySlope: -0.82 ... -0.54,
            plungeSlope: -1.30 ... -1.00,
            compressionSlope: -0.16 ... 0.06,
            exitSlope: -0.46 ... -0.22
        )
        /// The high-risk chute is the core of the opening fall line. It stays
        /// continuous and sampled, but the steep plunge and compact catch
        /// create real pitch momentum that must be managed with lean.
        static let extremeChuteProfile = DownhillChuteProfile(
            length: 660...820,
            drop: 960...1200,
            entryControlFraction: 0.08...0.13,
            plungeControlFraction: 0.39...0.50,
            compressionControlFraction: 0.68...0.76,
            entryDropFraction: 0.07...0.12,
            plungeDropFraction: 0.68...0.80,
            compressionTailDrop: 140...195,
            entrySlope: -1.12 ... -0.78,
            plungeSlope: -1.75 ... -1.32,
            compressionSlope: -0.28 ... -0.04,
            exitSlope: -0.62 ... -0.38
        )
        static let benchProfile = DownhillFeatureProfile(
            length: 280...440,
            drop: 38...66,
            firstControlFraction: 0.30...0.46,
            secondControlFraction: 0.64...0.80,
            firstDropFraction: 0.22...0.36,
            secondDropFraction: 0.64...0.80,
            entrySlope: -0.16 ... -0.06,
            middleSlope: -0.18 ... -0.05
        )
        static let rollerProfile = DownhillRollerProfile(
            length: 230...360,
            drop: 135...210,
            firstControlFraction: 0.18...0.25,
            secondControlFraction: 0.40...0.52,
            thirdControlFraction: 0.68...0.80,
            firstDropFraction: 0.14...0.26,
            secondDropFraction: 0.44...0.60,
            thirdDropFraction: 0.72...0.88,
            entrySlope: -0.56 ... -0.24,
            firstSlope: -0.66 ... -0.24,
            secondSlope: -0.86 ... -0.36
        )
        static let lipProfile = DownhillLipProfile(
            length: 360...500,
            drop: 235...335,
            approachControlFraction: 0.18...0.24,
            crestOffsetFraction: 0.16...0.22,
            approachDropFraction: 0.24...0.32,
            approachLengthDropFraction: 0.04...0.06,
            climb: 42...58,
            lipDrop: 130...180,
            troughSlope: -0.18 ... -0.06,
            crestSlope: 0.40...0.58
        )
        static let stepDownProfile = DownhillStepDownProfile(
            length: 530...680,
            drop: 550...740,
            approachControlFraction: 0.16...0.22,
            crestControlFraction: 0.30...0.36,
            cliffLengthFraction: 0.22...0.30,
            landingLengthFraction: 0.32...0.42,
            approachDropFraction: 0.10...0.16,
            climb: 42...58,
            cliffDropFraction: 0.22...0.30,
            landingDropFraction: 0.84...0.94,
            troughSlope: -0.22 ... -0.07,
            crestSlope: 0.40...0.58,
            cliffSlope: -0.82 ... -0.58,
            landingSlope: -0.46 ... -0.22,
            exitSlope: -0.28 ... -0.14
        )
        /// Larger continuous cliff launch reserved for the intense descent
        /// grammar. It has more vertical commitment, but keeps the same safe,
        /// sampled surface beneath both wheels.
        static let intenseStepDownProfile = DownhillStepDownProfile(
            length: 760...920,
            drop: 780...1000,
            approachControlFraction: 0.14...0.20,
            crestControlFraction: 0.28...0.34,
            cliffLengthFraction: 0.22...0.28,
            landingLengthFraction: 0.34...0.44,
            approachDropFraction: 0.12...0.18,
            climb: 46...64,
            cliffDropFraction: 0.24...0.32,
            landingDropFraction: 0.84...0.92,
            troughSlope: -0.28 ... -0.10,
            crestSlope: 0.40...0.58,
            cliffSlope: -0.85 ... -0.65,
            landingSlope: -0.46 ... -0.26,
            exitSlope: -0.30 ... -0.16
        )
    }

    enum Handling {
        /// Rider inputs add force or an equal-and-opposite torque couple to
        /// the vehicle; they never write velocity, change gravity, or lift
        /// the bike.
        static let pedalForce: CGFloat = 18_000
        static let pedalFadeSpeed: CGFloat = 3_000
        static let pedalClimbForce: CGFloat = 38_000
        static let groundLeanTorque: CGFloat = 48
        static let airLeanTorque: CGFloat = 28

        /// Downhill gravity acceleration multiplier.
        /// Massively increases the speed gained on sustained downhills (aerodynamic tuck gravity gain).
        static let downhillGravityMultiplier: CGFloat = 6.0
        /// Minimal rolling drag when coasting (0.5% decay per second).
        static let coastingRollingDrag: CGFloat = 0.005
        /// Momentum inertia factor that protects cached downhill speed on uphills.
        static let uphillGravityReduction: CGFloat = 0.40
    }

    enum Crash {
        static let spawnGrace: TimeInterval = 1.6
        static let minimumTravelBeforeCrashChecks: CGFloat = 90
        static let maximumRelativeLeanAngle: CGFloat = .pi * 0.50
        static let minimumFrameStrikePitch: CGFloat = 0.85
        /// The frame is a real collision body. This guards impossible
        /// over-rotations or landing upside down.
        static let maximumAirborneRotation: CGFloat = .pi * 0.72
        static let fallBelowTerrainDistance: CGFloat = 360
    }

    enum Display {
        /// World-space points represented by one displayed metre.
        static let worldUnitsPerMeter: CGFloat = 5
        static let speedKilometersPerHourScale: CGFloat = 0.22
    }

    enum Camera {
        static let baseLookAhead: CGFloat = 120
        static let velocityLookAheadFactor: CGFloat = 0.18
        static let minimumLookAhead: CGFloat = 80
        static let maximumLookAhead: CGFloat = 180
        static let verticalBias: CGFloat = 42
        static let followResponsiveness: CGFloat = 5.5
    }
}

enum PhysicsCategory {
    static let bike: UInt32 = 1 << 0
    static let terrain: UInt32 = 1 << 1
    static let bikeChassis: UInt32 = 1 << 8
    static let bikeSwingarm: UInt32 = 1 << 9
    static let bikeWheel: UInt32 = 1 << 10
    static let bikeFrontFork: UInt32 = 1 << 11
    static let allBike: UInt32 = bike | bikeChassis | bikeSwingarm | bikeWheel | bikeFrontFork
}
