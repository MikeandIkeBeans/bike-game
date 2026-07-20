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
        static let worldUnitsPerPhysicsMeter: CGFloat = 5.3
        static let earthGravityMetersPerSecondSquared: CGFloat = 9.81
        static let gravity = CGVector(
            dx: 0,
            dy: -earthGravityMetersPerSecondSquared * worldUnitsPerPhysicsMeter
        )
    }

    enum Bike {
        static let visualWheelRadius: CGFloat = 17
        static let wheelOffsetX: CGFloat = 27
        static let wheelOffsetY: CGFloat = -9
        static let collisionWheelRadius: CGFloat = 16
        /// The frame guard only protects the tire gap during a deep landing.
        /// It sits above the tire contact envelope so a slow approach cannot
        /// hook the chassis on an otherwise rollable launch face.
        static let frameGuardRadius: CGFloat = 9
        static let frameGuardOffsetY: CGFloat = 6
        static let spawnX: CGFloat = 0
        /// Put the tires directly on the opening surface so real contact can
        /// drive the first pedal stroke without a proximity-based assist.
        static let spawnClearance: CGFloat = 25
        static let startVelocity = CGVector.zero
        /// Gravity keeps the same acceleration, while this lighter chassis
        /// lets real rider force recover speed and climb ordinary grades.
        static let mass: CGFloat = 0.42
        /// Keep a downhill run's momentum through small crests; traction comes
        /// from collision geometry rather than heavy artificial drag.
        /// Ground damping is nearly zero so a chute's potential energy remains
        /// usable speed. Air damping is lower still, preserving the true
        /// ballistic arc between takeoff and landing.
        static let groundLinearDamping: CGFloat = 0.001
        static let airLinearDamping: CGFloat = 0
        static let friction: CGFloat = 0.005
        /// Retain more speed when the wheels transition across curved ground
        /// instead of turning every edge contact into an inelastic brake.
        static let restitution: CGFloat = 0.08
        // Retain a high-speed safety cap for reliable precise collisions, while
        // leaving enough headroom for a full-speed downhill launch.
        static let maximumSpeed: CGFloat = 1_800
    }

    enum Terrain {
        /// Finer rails follow the visual curve closely, avoiding sharp normal
        /// changes that bleed a downhill run's stored velocity.
        static let maximumColliderSegmentLength: CGFloat = 5
        static let friction: CGFloat = 0.005
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
        static let maximumLandingApproachSlope: CGFloat = 0.46
        /// Big launch features descend through a real, continuous cliff face.
        /// This is deliberately steep, but never a vertical collision rail.
        static let maximumContinuousCliffSlope: CGFloat = 0.72
        /// Generated trough exits must have enough horizontal room for a bike
        /// to roll out instead of becoming a divot with a near-vertical wall.
        static let minimumRollableRampLength: CGFloat = 94
        static let maximumRollableUphillSlope: CGFloat = 0.46
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
        static let biomeZoneLengthMeters: CGFloat = 1_600

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
        static let grammarTransitionChance: CGFloat = 0.54
        /// These prevent an air feature from appearing before the rider has
        /// runway or immediately after another air feature.
        static let openingMinimumNonJumpFeaturesBeforeFirstJump = 1
        static let minimumNonJumpFeaturesBetweenJumps = 1
        static let repeatedFeatureWeightMultiplier: CGFloat = 0.45

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

        static let summitSpineGrammar = grammar(minimum: 3, jump: 0.40, increase: 0.14, maximum: 0.78, stepDown: 0.56, flow: 0.06, swoop: 0.18, chute: 0.52, roller: 0.18, bench: 0.06)
        static let corniceRunGrammar = grammar(minimum: 2, jump: 0.46, increase: 0.15, maximum: 0.82, stepDown: 0.66, flow: 0.04, swoop: 0.20, chute: 0.56, roller: 0.14, bench: 0.06)
        static let icefallGrammar = grammar(minimum: 3, jump: 0.54, increase: 0.16, maximum: 0.88, stepDown: 0.78, flow: 0.03, swoop: 0.12, chute: 0.67, roller: 0.12, bench: 0.06)
        static let frostPinesGrammar = grammar(minimum: 2, jump: 0.32, increase: 0.14, maximum: 0.72, stepDown: 0.42, flow: 0.16, swoop: 0.24, chute: 0.24, roller: 0.29, bench: 0.07)
        static let moraineGrammar = grammar(minimum: 3, jump: 0.48, increase: 0.15, maximum: 0.84, stepDown: 0.70, flow: 0.05, swoop: 0.19, chute: 0.55, roller: 0.16, bench: 0.05)
        static let slateRidgeGrammar = grammar(minimum: 2, jump: 0.36, increase: 0.14, maximum: 0.76, stepDown: 0.46, flow: 0.09, swoop: 0.35, chute: 0.31, roller: 0.19, bench: 0.06)
        static let gravelChuteGrammar = grammar(minimum: 4, jump: 0.58, increase: 0.17, maximum: 0.92, stepDown: 0.85, flow: 0.02, swoop: 0.12, chute: 0.70, roller: 0.11, bench: 0.05)
        static let fernFlowGrammar = grammar(minimum: 2, jump: 0.28, increase: 0.12, maximum: 0.66, stepDown: 0.32, flow: 0.25, swoop: 0.27, chute: 0.16, roller: 0.25, bench: 0.07)
        static let canopyRollerGrammar = grammar(minimum: 2, jump: 0.34, increase: 0.13, maximum: 0.70, stepDown: 0.36, flow: 0.10, swoop: 0.22, chute: 0.14, roller: 0.47, bench: 0.07)
        static let redClayGrammar = grammar(minimum: 3, jump: 0.44, increase: 0.15, maximum: 0.82, stepDown: 0.64, flow: 0.07, swoop: 0.18, chute: 0.55, roller: 0.14, bench: 0.06)
        static let sandstoneGrammar = grammar(minimum: 3, jump: 0.51, increase: 0.16, maximum: 0.88, stepDown: 0.78, flow: 0.04, swoop: 0.22, chute: 0.52, roller: 0.16, bench: 0.06)
        static let canyonDropGrammar = grammar(minimum: 4, jump: 0.62, increase: 0.18, maximum: 0.94, stepDown: 0.92, flow: 0.02, swoop: 0.10, chute: 0.75, roller: 0.08, bench: 0.05)
        static let badlandsGrammar = grammar(minimum: 3, jump: 0.48, increase: 0.16, maximum: 0.86, stepDown: 0.74, flow: 0.05, swoop: 0.16, chute: 0.58, roller: 0.15, bench: 0.06)
        static let shaleRunGrammar = grammar(minimum: 2, jump: 0.38, increase: 0.14, maximum: 0.78, stepDown: 0.54, flow: 0.08, swoop: 0.27, chute: 0.42, roller: 0.17, bench: 0.06)
        static let volcanicGrammar = grammar(minimum: 4, jump: 0.56, increase: 0.17, maximum: 0.92, stepDown: 0.88, flow: 0.03, swoop: 0.11, chute: 0.71, roller: 0.10, bench: 0.05)
        static let ashFlowGrammar = grammar(minimum: 2, jump: 0.30, increase: 0.13, maximum: 0.68, stepDown: 0.38, flow: 0.19, swoop: 0.29, chute: 0.19, roller: 0.27, bench: 0.06)
        static let meadowGrammar = grammar(minimum: 2, jump: 0.25, increase: 0.11, maximum: 0.60, stepDown: 0.28, flow: 0.28, swoop: 0.25, chute: 0.13, roller: 0.28, bench: 0.06)
        static let riverRockGrammar = grammar(minimum: 3, jump: 0.42, increase: 0.15, maximum: 0.80, stepDown: 0.60, flow: 0.07, swoop: 0.21, chute: 0.48, roller: 0.18, bench: 0.06)
        static let coastalBluffGrammar = grammar(minimum: 4, jump: 0.60, increase: 0.17, maximum: 0.93, stepDown: 0.90, flow: 0.03, swoop: 0.14, chute: 0.68, roller: 0.10, bench: 0.05)
        static let sunsetGullyGrammar = grammar(minimum: 3, jump: 0.47, increase: 0.16, maximum: 0.85, stepDown: 0.70, flow: 0.06, swoop: 0.20, chute: 0.55, roller: 0.14, bench: 0.05)

        static let flowProfile = DownhillFeatureProfile(
            length: 220...350,
            drop: 72...122,
            firstControlFraction: 0.24...0.36,
            secondControlFraction: 0.56...0.72,
            firstDropFraction: 0.20...0.34,
            secondDropFraction: 0.60...0.82,
            entrySlope: -0.46 ... -0.20,
            middleSlope: -0.52 ... -0.20
        )
        static let swoopProfile = DownhillFeatureProfile(
            length: 240...400,
            drop: 118...190,
            firstControlFraction: 0.16...0.26,
            secondControlFraction: 0.46...0.60,
            firstDropFraction: 0.14...0.26,
            secondDropFraction: 0.58...0.78,
            entrySlope: -0.54 ... -0.22,
            middleSlope: -0.68 ... -0.30
        )
        /// First-descent fall lines use a much steeper, shorter swoop. The
        /// shape earns dangerous speed before the rider reaches a compression.
        static let extremeSwoopProfile = DownhillFeatureProfile(
            length: 260...380,
            drop: 260...370,
            firstControlFraction: 0.14...0.22,
            secondControlFraction: 0.42...0.56,
            firstDropFraction: 0.16...0.28,
            secondDropFraction: 0.64...0.82,
            entrySlope: -0.80 ... -0.48,
            middleSlope: -1.05 ... -0.62
        )
        static let chuteProfile = DownhillChuteProfile(
            /// Long, flowing chutes turn gravity into usable horizontal speed
            /// rather than dropping the bike into a momentum-killing catch.
            length: 720...900,
            drop: 560...740,
            entryControlFraction: 0.10...0.16,
            plungeControlFraction: 0.44...0.56,
            compressionControlFraction: 0.72...0.80,
            entryDropFraction: 0.06...0.10,
            plungeDropFraction: 0.64...0.74,
            compressionTailDrop: 64...98,
            entrySlope: -0.64 ... -0.40,
            plungeSlope: -1.00 ... -0.72,
            compressionSlope: -0.16 ... 0.06,
            exitSlope: -0.46 ... -0.22
        )
        /// The high-risk chute is the core of the opening fall line. It stays
        /// continuous and sampled, but the steep plunge and compact catch
        /// create real pitch momentum that must be managed with lean.
        static let extremeChuteProfile = DownhillChuteProfile(
            length: 660...820,
            drop: 780...980,
            entryControlFraction: 0.08...0.13,
            plungeControlFraction: 0.39...0.50,
            compressionControlFraction: 0.68...0.76,
            entryDropFraction: 0.07...0.12,
            plungeDropFraction: 0.68...0.80,
            compressionTailDrop: 100...150,
            entrySlope: -0.86 ... -0.56,
            plungeSlope: -1.35 ... -1.00,
            compressionSlope: -0.28 ... -0.04,
            exitSlope: -0.62 ... -0.38
        )
        static let benchProfile = DownhillFeatureProfile(
            length: 280...440,
            drop: 30...56,
            firstControlFraction: 0.30...0.46,
            secondControlFraction: 0.64...0.80,
            firstDropFraction: 0.22...0.36,
            secondDropFraction: 0.64...0.80,
            entrySlope: -0.16 ... -0.06,
            middleSlope: -0.18 ... -0.05
        )
        static let rollerProfile = DownhillRollerProfile(
            length: 230...360,
            drop: 82...142,
            firstControlFraction: 0.18...0.25,
            secondControlFraction: 0.40...0.52,
            thirdControlFraction: 0.68...0.80,
            firstDropFraction: 0.14...0.26,
            secondDropFraction: 0.44...0.60,
            thirdDropFraction: 0.72...0.88,
            entrySlope: -0.40 ... -0.16,
            firstSlope: -0.46 ... -0.14,
            secondSlope: -0.62 ... -0.24
        )
        static let lipProfile = DownhillLipProfile(
            length: 360...500,
            drop: 165...240,
            approachControlFraction: 0.18...0.24,
            crestOffsetFraction: 0.16...0.22,
            approachDropFraction: 0.24...0.32,
            approachLengthDropFraction: 0.04...0.06,
            climb: 30...42,
            lipDrop: 92...132,
            troughSlope: -0.18 ... -0.06,
            crestSlope: 0.40...0.58
        )
        static let stepDownProfile = DownhillStepDownProfile(
            length: 530...680,
            drop: 410...570,
            approachControlFraction: 0.16...0.22,
            crestControlFraction: 0.30...0.36,
            cliffLengthFraction: 0.22...0.30,
            landingLengthFraction: 0.32...0.42,
            approachDropFraction: 0.10...0.16,
            climb: 30...42,
            cliffDropFraction: 0.22...0.30,
            landingDropFraction: 0.84...0.94,
            troughSlope: -0.22 ... -0.07,
            crestSlope: 0.40...0.58,
            cliffSlope: -0.72 ... -0.52,
            landingSlope: -0.46 ... -0.22,
            exitSlope: -0.28 ... -0.14
        )
        /// Larger continuous cliff launch reserved for the intense descent
        /// grammar. It has more vertical commitment, but keeps the same safe,
        /// sampled surface beneath both wheels.
        static let intenseStepDownProfile = DownhillStepDownProfile(
            length: 760...920,
            drop: 620...800,
            approachControlFraction: 0.14...0.20,
            crestControlFraction: 0.28...0.34,
            cliffLengthFraction: 0.22...0.28,
            landingLengthFraction: 0.34...0.44,
            approachDropFraction: 0.12...0.18,
            climb: 34...48,
            cliffDropFraction: 0.24...0.32,
            landingDropFraction: 0.84...0.92,
            troughSlope: -0.28 ... -0.10,
            crestSlope: 0.40...0.58,
            cliffSlope: -0.72 ... -0.58,
            landingSlope: -0.46 ... -0.26,
            exitSlope: -0.30 ... -0.16
        )
    }

    /// Arcade handling assists for the single rigid-body bike. These deliberately
    /// bound rotation and drive so terrain contacts stay playable rather than
    /// trying to simulate a full suspension model.
    enum Handling {
        /// PEDAL is a physical push that keeps a rider moving and able to
        /// climb, but fades out before it can replace downhill momentum.
        /// World-scale rider force: strong enough to crest ordinary climbs,
        /// while still fading before it can substitute for a downhill run.
        static let pedalForce: CGFloat = 1_400
        static let pedalAssistSpeed: CGFloat = 1_000
        /// Extra rider power is only available against an uphill grade, so it
        /// restores climbing without turning PEDAL into a downhill speed boost.
        static let pedalClimbForce: CGFloat = 2_200
        /// SpriteKit can report an edge contact one frame late. This accepts a
        /// tire only when it is actually within the terrain collision envelope,
        /// rather than treating the bike's centre as a proxy for support.
        static let pedalWheelContactSlop: CGFloat = 2
        static let pedalMaximumWheelPenetration: CGFloat = 5
        /// Keeps balance/crash evaluation stable across a contact boundary;
        /// it must never extend pedal force into airtime.
        static let handlingContactGrace: TimeInterval = 0.10

        /// Passive upright stabilization keeps starts readable, then fades out
        /// so terrain pitch and rider lean decide a high-speed outcome.
        static let groundStabilizationTorque: CGFloat = 24
        static let groundStabilizationFadeSpeed: CGFloat = 260
        static let groundMaximumAngularVelocity: CGFloat = 1.8
        /// A fast rider may carry more real pitch momentum from terrain
        /// transitions. The low-speed cap keeps starts and slow climbs calm.
        static let highSpeedGroundAngularVelocity: CGFloat = 5.0
        static let groundAngularDamping: CGFloat = 1.15
        static let highSpeedGroundAngularDamping: CGFloat = 0.22
        static let highSpeedHandlingStart: CGFloat = 170
        static let highSpeedHandlingFull: CGFloat = 440
        /// Once the opening stabilization has faded, a bike should not
        /// silently snap back to the trail. This small residual keeps a slow
        /// roll readable while leaving high-speed pitch to the rider.
        static let highSpeedTrailAlignmentTorque: CGFloat = 3.5
        /// A single compound body does not expose SpriteKit's per-wheel
        /// braking moment. Feed back only sustained, real post-contact
        /// deceleration as an equivalent nose-down load. It never adds linear
        /// speed or changes gravity.
        static let terrainPitchStartSpeed: CGFloat = 105
        static let terrainPitchFullSpeed: CGFloat = 310
        static let terrainDecelerationForFullPitch: CGFloat = 620
        static let terrainDecelerationPitchTorque: CGFloat = 20
        static let terrainMaximumPitchTorque: CGFloat = 24
        /// Ease the load over multiple physics frames so a sampled collider
        /// seam cannot impersonate a violent impact.
        static let terrainPitchResponseTime: TimeInterval = 0.16
        /// Part of the existing pedal force is applied at the rear tire. This
        /// keeps total drive unchanged while giving pedaling a real wheelie
        /// consequence that forward lean can counter.
        static let rearTractionForceShare: CGFloat = 0.008
        /// Lean only changes the grounded target pitch once the bike is
        /// rolling. This prevents a control press from toppling a stopped bike.
        static let groundLeanMinimumSpeed: CGFloat = 55
        static let groundLeanFullSpeed: CGFloat = 220
        static let groundLeanMaximumOffset: CGFloat = 0.42
        /// Deliberate lean has more authority than the high-speed trail
        /// alignment so a skilled rider can correct a real pitch load.
        static let groundLeanResponseTorque: CGFloat = 36

        /// Air lean can set up a landing, but it targets a limited pitch from
        /// takeoff instead of applying unlimited spin while the button is held.
        static let airLeanMaximumOffset: CGFloat = 0.58
        static let airLeanResponseTorque: CGFloat = 26
        static let airMaximumAngularVelocity: CGFloat = 2.4
        static let airAngularDamping: CGFloat = 0.45

    }

    enum Crash {
        static let spawnGrace: TimeInterval = 1.6
        static let minimumTravelBeforeCrashChecks: CGFloat = 90
        static let maximumRelativeLeanAngle: CGFloat = .pi * 0.80
        static let unsafeLeanDuration: TimeInterval = 0.90
        /// At high speed, getting far out of line must be corrected with lean
        /// input before the bike can settle into a flip.
        static let highSpeedLeanChallengeStart: CGFloat = 165
        static let highSpeedLeanChallengeFull: CGFloat = 430
        static let highSpeedMaximumRelativeLeanAngle: CGFloat = .pi * 0.16
        static let highSpeedUnsafeLeanDuration: TimeInterval = 0.11
        /// A convex crest naturally unloads one tire for a fraction of a
        /// second. Give the chassis this brief transition to re-settle before
        /// a lost-balance or frame-strike check may end the run.
        static let crestSupportGrace: TimeInterval = 0.22
        /// A full rotation after takeoff is an uncontrolled flip, not a safe
        /// recovery. Normal jumps retain plenty of room to pitch for landing.
        static let maximumAirborneRotation: CGFloat = .pi * 0.72
        /// A rear-wheelie needs more room than an over-the-bars pitch before
        /// the visual frame probe is allowed to end the run.
        static let minimumRearWheelieFrameStrikePitch: CGFloat = 1.45
        static let minimumFrameStrikePitch: CGFloat = 1.10
        static let frameProbeClearance: CGFloat = -2
        static let frameStrikeMaximumTerrainSlope: CGFloat = 0.60
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
}
