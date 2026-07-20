import SpriteKit

/// Owns immutable streamed terrain chunks and the exact sampled paths shared
/// by terrain drawing and collision.
final class TerrainStreamController {
    private struct TerrainChunk {
        let index: Int
        let points: [CGPoint]
        /// These are the exact sampled runs used for both the visible trail
        /// edge and its collision rails. Gaps are deliberately absent.
        let surfaceRuns: [[CGPoint]]
        let node: SKNode
        let sceneryNode: SKNode
        let terrainBodyIDs: Set<ObjectIdentifier>

        var startX: CGFloat { points.first?.x ?? 0 }
        var endX: CGFloat { points.last?.x ?? 0 }
    }

    private enum TerrainFeatureKind: CaseIterable, Equatable {
        case flow
        case swoop
        case chute
        case roller
        case bench
        case lip
        case stepDown

        var isJump: Bool {
            self == .lip || self == .stepDown
        }
    }

    /// A terrain grammar governs a short phrase of related features. It then
    /// transitions to another grammar, keeping an endless run varied while
    /// retaining a recognizable flow for more than one feature at a time.
    private enum TerrainGrammar: Int, CaseIterable, Equatable {
        case summitSpine
        case corniceRun
        case icefall
        case frostPines
        case moraine
        case slateRidge
        case gravelChute
        case fernFlow
        case canopyRoller
        case redClay
        case sandstone
        case canyonDrop
        case badlands
        case shaleRun
        case volcanic
        case ashFlow
        case meadow
        case riverRock
        case coastalBluff
        case sunsetGully

        var profile: TerrainGrammarProfile {
            switch self {
            case .summitSpine: GameTuning.Terrain.summitSpineGrammar
            case .corniceRun: GameTuning.Terrain.corniceRunGrammar
            case .icefall: GameTuning.Terrain.icefallGrammar
            case .frostPines: GameTuning.Terrain.frostPinesGrammar
            case .moraine: GameTuning.Terrain.moraineGrammar
            case .slateRidge: GameTuning.Terrain.slateRidgeGrammar
            case .gravelChute: GameTuning.Terrain.gravelChuteGrammar
            case .fernFlow: GameTuning.Terrain.fernFlowGrammar
            case .canopyRoller: GameTuning.Terrain.canopyRollerGrammar
            case .redClay: GameTuning.Terrain.redClayGrammar
            case .sandstone: GameTuning.Terrain.sandstoneGrammar
            case .canyonDrop: GameTuning.Terrain.canyonDropGrammar
            case .badlands: GameTuning.Terrain.badlandsGrammar
            case .shaleRun: GameTuning.Terrain.shaleRunGrammar
            case .volcanic: GameTuning.Terrain.volcanicGrammar
            case .ashFlow: GameTuning.Terrain.ashFlowGrammar
            case .meadow: GameTuning.Terrain.meadowGrammar
            case .riverRock: GameTuning.Terrain.riverRockGrammar
            case .coastalBluff: GameTuning.Terrain.coastalBluffGrammar
            case .sunsetGully: GameTuning.Terrain.sunsetGullyGrammar
            }
        }

        var stepDownProfile: DownhillStepDownProfile {
            usesExtremeFallLine
                ? GameTuning.Terrain.intenseStepDownProfile
                : GameTuning.Terrain.stepDownProfile
        }

        var swoopProfile: DownhillFeatureProfile {
            usesExtremeFallLine
                ? GameTuning.Terrain.extremeSwoopProfile
                : GameTuning.Terrain.swoopProfile
        }

        var chuteProfile: DownhillChuteProfile {
            usesExtremeFallLine
                ? GameTuning.Terrain.extremeChuteProfile
                : GameTuning.Terrain.chuteProfile
        }

        private var usesExtremeFallLine: Bool {
            switch self {
            case .summitSpine, .corniceRun, .icefall, .moraine,
                    .gravelChute, .canyonDrop, .badlands, .volcanic,
                    .coastalBluff, .sunsetGully:
                true
            default:
                false
            }
        }

        func isAvailable(in biome: TerrainBiome) -> Bool {
            biome.grammarIndices.contains(rawValue)
        }
    }

    private enum TerrainBiome: Int, CaseIterable {
        case summitIce
        case windCornice
        case blueIcefall
        case frostPine
        case glacialMoraine
        case slateRidge
        case gravelChute
        case fernGrove
        case canopyRollers
        case redClay
        case sandstoneMesa
        case canyonFloor
        case badlands
        case shaleRun
        case volcanicRock
        case ashField
        case alpineMeadow
        case riverRock
        case coastalBluff
        case sunsetGully

        /// Each biome exposes its signature grammar plus two nearby phrases.
        /// The offset options avoid a hard, repetitive seam at every color
        /// transition while keeping the terrain culturally tied to its zone.
        var grammarIndices: [Int] {
            [
                rawValue,
                (rawValue + 1) % TerrainGrammar.allCases.count,
                (rawValue + 6) % TerrainGrammar.allCases.count
            ]
        }

        var snowCovered: Bool {
            rawValue <= TerrainBiome.glacialMoraine.rawValue
        }
    }

    private struct TerrainPalette {
        let edge: SKColor
        let fill: SKColor
    }

    private static let biomePalettes: [TerrainPalette] = [
        TerrainPalette(edge: SKColor(red: 0.93, green: 0.97, blue: 1.00, alpha: 1), fill: SKColor(red: 0.29, green: 0.40, blue: 0.50, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.80, green: 0.91, blue: 0.98, alpha: 1), fill: SKColor(red: 0.24, green: 0.36, blue: 0.48, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.64, green: 0.90, blue: 0.96, alpha: 1), fill: SKColor(red: 0.13, green: 0.40, blue: 0.50, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.85, green: 0.94, blue: 0.92, alpha: 1), fill: SKColor(red: 0.14, green: 0.29, blue: 0.28, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.71, green: 0.77, blue: 0.76, alpha: 1), fill: SKColor(red: 0.31, green: 0.36, blue: 0.35, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.58, green: 0.65, blue: 0.72, alpha: 1), fill: SKColor(red: 0.20, green: 0.27, blue: 0.34, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.78, green: 0.66, blue: 0.49, alpha: 1), fill: SKColor(red: 0.35, green: 0.26, blue: 0.16, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.40, green: 0.72, blue: 0.39, alpha: 1), fill: SKColor(red: 0.13, green: 0.33, blue: 0.15, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.35, green: 0.59, blue: 0.30, alpha: 1), fill: SKColor(red: 0.10, green: 0.26, blue: 0.12, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.86, green: 0.42, blue: 0.23, alpha: 1), fill: SKColor(red: 0.40, green: 0.16, blue: 0.10, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.88, green: 0.66, blue: 0.30, alpha: 1), fill: SKColor(red: 0.45, green: 0.29, blue: 0.10, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.82, green: 0.47, blue: 0.20, alpha: 1), fill: SKColor(red: 0.38, green: 0.14, blue: 0.07, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.72, green: 0.46, blue: 0.27, alpha: 1), fill: SKColor(red: 0.31, green: 0.17, blue: 0.09, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.57, green: 0.55, blue: 0.50, alpha: 1), fill: SKColor(red: 0.22, green: 0.21, blue: 0.20, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.40, green: 0.28, blue: 0.27, alpha: 1), fill: SKColor(red: 0.16, green: 0.10, blue: 0.10, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.63, green: 0.61, blue: 0.57, alpha: 1), fill: SKColor(red: 0.27, green: 0.25, blue: 0.23, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.56, green: 0.76, blue: 0.35, alpha: 1), fill: SKColor(red: 0.20, green: 0.39, blue: 0.13, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.47, green: 0.66, blue: 0.69, alpha: 1), fill: SKColor(red: 0.16, green: 0.30, blue: 0.34, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.55, green: 0.80, blue: 0.80, alpha: 1), fill: SKColor(red: 0.12, green: 0.34, blue: 0.38, alpha: 1)),
        TerrainPalette(edge: SKColor(red: 0.92, green: 0.48, blue: 0.25, alpha: 1), fill: SKColor(red: 0.42, green: 0.17, blue: 0.10, alpha: 1))
    ]

    private struct TerrainCursor {
        var point: CGPoint
        var slope: CGFloat
        var nextFeatureIndex: Int
        var nonJumpFeatureCount: Int
        var hasGeneratedJump: Bool
        var previousFeatureKind: TerrainFeatureKind?
        var activeGrammar: TerrainGrammar
        var grammarFeatureCount: Int
    }

    private struct TerrainSegment {
        let start: CGPoint
        let end: CGPoint
        let startSlope: CGFloat
        let endSlope: CGFloat
        let isLinear: Bool
        /// An air gap retains its sampled endpoints for terrain queries, but
        /// has neither a visible top edge nor a collision rail between them.
        let isSurface: Bool

        init(
            start: CGPoint,
            end: CGPoint,
            startSlope: CGFloat,
            endSlope: CGFloat,
            isLinear: Bool,
            isSurface: Bool = true,
            maximumUphillSlope: CGFloat? = nil
        ) {
            self.start = start
            self.end = end
            // Every terrain rail is sampled from these same segments. Capping
            // only the positive tangents keeps trough exits rollable without
            // flattening the gravity-fed downhill faces that create speed.
            let uphillSlopeLimit = maximumUphillSlope
                ?? GameTuning.Terrain.maximumRollableUphillSlope
            self.startSlope = min(startSlope, uphillSlopeLimit)
            self.endSlope = min(endSlope, uphillSlopeLimit)
            self.isLinear = isLinear
            self.isSurface = isSurface
        }
    }

    private struct DeterministicRandom {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            mixed ^= mixed >> 31
            let unit = CGFloat(Double(mixed >> 11) / Double(1 << 53))
            return range.lowerBound + (range.upperBound - range.lowerBound) * unit
        }

    }

    private let terrainLayer: SKNode
    private let sceneryLayer: SKNode
    private var terrainPoints: [CGPoint] = []
    private var terrainChunks: [TerrainChunk] = []
    private var terrainRunIndex: UInt64 = 0
    private var terrainSeed = GameTuning.Terrain.proceduralCourseSeed
    private var terrainCursor = TerrainCursor(
        point: CGPoint(x: GameTuning.Terrain.streamStartX, y: GameTuning.Terrain.streamStartY),
        slope: 0,
        nextFeatureIndex: 0,
        nonJumpFeatureCount: 0,
        hasGeneratedJump: false,
        previousFeatureKind: nil,
        activeGrammar: .summitSpine,
        grammarFeatureCount: 0
    )
    private var nextTerrainChunkIndex = 0
    private(set) var terrainBodyIDs = Set<ObjectIdentifier>()

    var levelStartX: CGFloat { terrainPoints.first?.x ?? 0 }
    var levelEndX: CGFloat { terrainPoints.last?.x ?? 0 }

    init(terrainLayer: SKNode, sceneryLayer: SKNode) {
        self.terrainLayer = terrainLayer
        self.sceneryLayer = sceneryLayer
    }

    func reset() {
        terrainChunks.forEach { chunk in
            chunk.node.removeFromParent()
            chunk.sceneryNode.removeFromParent()
        }
        terrainChunks.removeAll(keepingCapacity: true)
        terrainPoints.removeAll(keepingCapacity: true)
        terrainBodyIDs.removeAll(keepingCapacity: true)
        terrainRunIndex &+= 1
        terrainSeed = GameTuning.Terrain.proceduralCourseSeed &+ (
            terrainRunIndex &* 0xA24B_AED4_963E_E407
        )
        terrainCursor = TerrainCursor(
            point: CGPoint(x: GameTuning.Terrain.streamStartX, y: GameTuning.Terrain.streamStartY),
            slope: 0,
            nextFeatureIndex: 0,
            nonJumpFeatureCount: 0,
            hasGeneratedJump: false,
            previousFeatureKind: nil,
            activeGrammar: .summitSpine,
            grammarFeatureCount: 0
        )
        nextTerrainChunkIndex = 0

        appendTerrainChunk()
        ensureTerrainAhead(of: GameTuning.Bike.spawnX)
    }

    /// Appending happens before physics, while retiring happens after it. Each
    /// chunk is immutable once installed, so no edge chain is ever replaced
    /// beneath a moving bike.
    func ensureTerrainAhead(of positionX: CGFloat) {
        let targetX = positionX + GameTuning.Terrain.streamAheadDistance
        while levelEndX < targetX {
            appendTerrainChunk()
        }
    }

    private func appendTerrainChunk() {
        let generated = makeTerrainChunk(index: nextTerrainChunkIndex, from: terrainCursor)
        terrainLayer.addChild(generated.chunk.node)
        sceneryLayer.addChild(generated.chunk.sceneryNode)
        terrainChunks.append(generated.chunk)
        terrainBodyIDs.formUnion(generated.chunk.terrainBodyIDs)
        terrainCursor = generated.cursor
        nextTerrainChunkIndex += 1
        rebuildTerrainPointIndex()
    }

    func retireTerrain(
        behind positionX: CGFloat,
        isTouching: (Set<ObjectIdentifier>) -> Bool,
        forgetBody: (ObjectIdentifier) -> Void
    ) {
        let retirementX = positionX - GameTuning.Terrain.streamRetirementDistance
        var retiredAny = false

        while let oldestChunk = terrainChunks.first, oldestChunk.endX < retirementX {
            guard !isTouching(oldestChunk.terrainBodyIDs) else { break }

            terrainChunks.removeFirst()
            terrainBodyIDs.subtract(oldestChunk.terrainBodyIDs)
            oldestChunk.terrainBodyIDs.forEach(forgetBody)
            oldestChunk.node.removeFromParent()
            oldestChunk.sceneryNode.removeFromParent()
            retiredAny = true
        }

        if retiredAny {
            rebuildTerrainPointIndex()
        }
    }

    private func rebuildTerrainPointIndex() {
        var indexedPoints: [CGPoint] = []
        for chunk in terrainChunks {
            if indexedPoints.isEmpty {
                indexedPoints.append(contentsOf: chunk.points)
            } else {
                // Neighbouring chunks share this exact endpoint. Keep one copy
                // for terrain queries while both physics edge chains retain it.
                indexedPoints.append(contentsOf: chunk.points.dropFirst())
            }
        }
        terrainPoints = indexedPoints
    }

    private func makeTerrainChunk(
        index: Int,
        from cursor: TerrainCursor
    ) -> (chunk: TerrainChunk, cursor: TerrainCursor) {
        let generated = terrainSegments(forChunk: index, from: cursor)
        let points = sampledPoints(from: generated.segments)
        let surfaceRuns = sampledSurfaceRuns(from: generated.segments)
        precondition(
            surfaceRuns.allSatisfy { $0.count > 1 },
            "Every terrain surface run needs at least one edge segment."
        )
        let chunkMidpointX = ((points.first?.x ?? cursor.point.x) + (points.last?.x ?? cursor.point.x)) / 2
        let chunkBiome = terrainBiome(at: chunkMidpointX)
        let terrainColors = colors(for: chunkBiome)

        let node = SKNode()
        var bodyIDs = Set<ObjectIdentifier>()
        for surfacePoints in surfaceRuns {
            let collisionPath = CGMutablePath()
            collisionPath.move(to: surfacePoints[0])
            surfacePoints.dropFirst().forEach { collisionPath.addLine(to: $0) }

            let terrainEdge = SKShapeNode(path: collisionPath)
            terrainEdge.strokeColor = terrainColors.edge
            terrainEdge.lineWidth = 5
            terrainEdge.lineCap = .round
            terrainEdge.lineJoin = .round
            terrainEdge.zPosition = 1

            let terrainBody = SKPhysicsBody(edgeChainFrom: collisionPath)
            terrainBody.categoryBitMask = PhysicsCategory.terrain
            terrainBody.collisionBitMask = PhysicsCategory.bike
            terrainBody.contactTestBitMask = PhysicsCategory.bike
            terrainBody.friction = GameTuning.Terrain.friction
            terrainBody.restitution = GameTuning.Terrain.restitution
            terrainBody.isDynamic = false
            terrainEdge.physicsBody = terrainBody
            bodyIDs.insert(ObjectIdentifier(terrainBody))

            let fillBottom = (surfacePoints.map(\.y).min() ?? 0) - GameTuning.Terrain.terrainFillDepth
            let fillPath = CGMutablePath()
            fillPath.move(to: surfacePoints[0])
            surfacePoints.dropFirst().forEach { fillPath.addLine(to: $0) }
            fillPath.addLine(to: CGPoint(x: surfacePoints.last!.x, y: fillBottom))
            fillPath.addLine(to: CGPoint(x: surfacePoints[0].x, y: fillBottom))
            fillPath.closeSubpath()

            let terrainFill = SKShapeNode(path: fillPath)
            terrainFill.fillColor = terrainColors.fill
            terrainFill.strokeColor = .clear

            node.addChild(terrainFill)
            node.addChild(terrainEdge)
        }

        let chunk = TerrainChunk(
            index: index,
            points: points,
            surfaceRuns: surfaceRuns,
            node: node,
            sceneryNode: makeSceneryNode(for: points, chunkIndex: index, biome: chunkBiome),
            terrainBodyIDs: bodyIDs
        )
        return (chunk, generated.cursor)
    }

    private func terrainSegments(
        forChunk chunkIndex: Int,
        from startingCursor: TerrainCursor
    ) -> (segments: [TerrainSegment], cursor: TerrainCursor) {
        if chunkIndex == 0 {
            let start = startingCursor.point
            let firstFlatEnd = CGPoint(
                x: start.x + GameTuning.Terrain.openingFirstFlatLength,
                y: start.y
            )
            let secondFlatEnd = CGPoint(
                x: firstFlatEnd.x + GameTuning.Terrain.openingSecondFlatLength,
                y: start.y
            )
            let gentleDropEnd = CGPoint(
                x: secondFlatEnd.x + GameTuning.Terrain.openingGentleDropLength,
                y: start.y - GameTuning.Terrain.openingGentleDrop
            )
            let exit = CGPoint(
                x: gentleDropEnd.x + GameTuning.Terrain.openingExitLength,
                y: gentleDropEnd.y - GameTuning.Terrain.openingExitDrop
            )
            var exitCursor = startingCursor
            exitCursor.point = exit
            exitCursor.slope = GameTuning.Terrain.openingExitSlope
            return (
                [
                    TerrainSegment(start: start, end: firstFlatEnd, startSlope: 0, endSlope: 0, isLinear: false),
                    TerrainSegment(start: firstFlatEnd, end: secondFlatEnd, startSlope: 0, endSlope: 0, isLinear: false),
                    TerrainSegment(
                        start: secondFlatEnd,
                        end: gentleDropEnd,
                        startSlope: 0,
                        endSlope: GameTuning.Terrain.openingGentleExitSlope,
                        isLinear: false
                    ),
                    TerrainSegment(
                        start: gentleDropEnd,
                        end: exit,
                        startSlope: GameTuning.Terrain.openingGentleExitSlope,
                        endSlope: GameTuning.Terrain.openingExitSlope,
                        isLinear: false
                    )
                ],
                exitCursor
            )
        }

        var cursor = startingCursor
        var segments: [TerrainSegment] = []
        for _ in 0..<GameTuning.Terrain.generatedFeaturesPerChunk {
            let feature = generatedFeature(from: cursor)
            segments.append(contentsOf: feature.segments)
            cursor = feature.cursor
        }
        return (segments, cursor)
    }

    private func generatedFeature(from cursor: TerrainCursor) -> (segments: [TerrainSegment], cursor: TerrainCursor) {
        let featureIndex = cursor.nextFeatureIndex
        let featureSeed = terrainSeed &+ (
            UInt64(featureIndex) &* 0xD134_2543_DE82_EF95
        )
        var random = DeterministicRandom(seed: featureSeed)
        let grammar = nextTerrainGrammar(
            from: cursor,
            biome: terrainBiome(at: cursor.point.x),
            random: &random
        )
        let kind = nextFeatureKind(from: cursor, grammar: grammar, random: &random)
        let generated: (segments: [TerrainSegment], exit: CGPoint, exitSlope: CGFloat)

        switch kind {
        case .flow:
            generated = profiledFeature(from: cursor, profile: GameTuning.Terrain.flowProfile, random: &random)
        case .swoop:
            generated = profiledFeature(from: cursor, profile: grammar.swoopProfile, random: &random)
        case .chute:
            generated = chuteFeature(from: cursor, profile: grammar.chuteProfile, random: &random)
        case .roller:
            generated = rollerFeature(from: cursor, random: &random)
        case .bench:
            generated = profiledFeature(from: cursor, profile: GameTuning.Terrain.benchProfile, random: &random)
        case .lip:
            generated = lipFeature(from: cursor, random: &random)
        case .stepDown:
            generated = stepDownFeature(
                from: cursor,
                profile: grammar.stepDownProfile,
                random: &random
            )
        }

        return (
            generated.segments,
            updatedTerrainCursor(
                from: cursor,
                kind: kind,
                grammar: grammar,
                exit: generated.exit,
                exitSlope: generated.exitSlope
            )
        )
    }

    private func nextTerrainGrammar(
        from cursor: TerrainCursor,
        biome: TerrainBiome,
        random: inout DeterministicRandom
    ) -> TerrainGrammar {
        let availableGrammars = TerrainGrammar.allCases.filter { $0.isAvailable(in: biome) }
        precondition(!availableGrammars.isEmpty, "Every terrain biome needs at least one grammar.")
        guard availableGrammars.contains(cursor.activeGrammar) else {
            return availableGrammars[0]
        }
        guard cursor.grammarFeatureCount >= cursor.activeGrammar.profile.minimumFeatureCount,
              random.value(in: 0...1) < GameTuning.Terrain.grammarTransitionChance else {
            return cursor.activeGrammar
        }

        let alternatives = availableGrammars.filter { $0 != cursor.activeGrammar }
        guard !alternatives.isEmpty else { return cursor.activeGrammar }
        let selection = min(
            Int(random.value(in: 0...CGFloat(alternatives.count))),
            alternatives.count - 1
        )
        return alternatives[selection]
    }

    /// This is a grammar-weighted draw. The only hard rules are that the
    /// opening gets enough runway and two air features cannot be adjacent.
    private func nextFeatureKind(
        from cursor: TerrainCursor,
        grammar: TerrainGrammar,
        random: inout DeterministicRandom
    ) -> TerrainFeatureKind {
        let profile = grammar.profile
        let minimumNonJumpFeatures = cursor.hasGeneratedJump
            ? GameTuning.Terrain.minimumNonJumpFeaturesBetweenJumps
            : GameTuning.Terrain.openingMinimumNonJumpFeaturesBeforeFirstJump
        guard cursor.nonJumpFeatureCount >= minimumNonJumpFeatures else {
            return weightedNonLipKind(from: cursor, grammar: grammar, random: &random)
        }

        let extraNonJumpFeatures = cursor.nonJumpFeatureCount - minimumNonJumpFeatures
        let jumpProbability = min(
            profile.jumpBaseProbability
                + CGFloat(extraNonJumpFeatures) * profile.jumpProbabilityIncreasePerNonJump,
            profile.maximumJumpProbability
        )
        if random.value(in: 0...1) < jumpProbability {
            return random.value(in: 0...1) < profile.stepDownShareOfJumps
                ? .stepDown
                : .lip
        }

        return weightedNonLipKind(from: cursor, grammar: grammar, random: &random)
    }

    private func weightedNonLipKind(
        from cursor: TerrainCursor,
        grammar: TerrainGrammar,
        random: inout DeterministicRandom
    ) -> TerrainFeatureKind {
        let profile = grammar.profile
        let repeatMultiplier = GameTuning.Terrain.repeatedFeatureWeightMultiplier
        let options: [(TerrainFeatureKind, CGFloat)] = [
            (TerrainFeatureKind.flow, profile.flowWeight),
            (TerrainFeatureKind.swoop, profile.swoopWeight),
            (TerrainFeatureKind.chute, profile.chuteWeight),
            (TerrainFeatureKind.roller, profile.rollerWeight),
            (TerrainFeatureKind.bench, profile.benchWeight)
        ].map { kind, weight in
            let adjustedWeight = cursor.previousFeatureKind == kind
                ? weight * repeatMultiplier
                : weight
            return (kind, adjustedWeight)
        }
        let totalWeight = options.reduce(0) { $0 + $1.1 }
        var roll = random.value(in: 0...totalWeight)
        for (kind, weight) in options {
            if roll < weight {
                return kind
            }
            roll -= weight
        }
        return options.last!.0
    }

    private func updatedTerrainCursor(
        from cursor: TerrainCursor,
        kind: TerrainFeatureKind,
        grammar: TerrainGrammar,
        exit: CGPoint,
        exitSlope: CGFloat
    ) -> TerrainCursor {
        return TerrainCursor(
            point: exit,
            slope: exitSlope,
            nextFeatureIndex: cursor.nextFeatureIndex + 1,
            nonJumpFeatureCount: kind.isJump ? 0 : cursor.nonJumpFeatureCount + 1,
            hasGeneratedJump: cursor.hasGeneratedJump || kind.isJump,
            previousFeatureKind: kind,
            activeGrammar: grammar,
            grammarFeatureCount: grammar == cursor.activeGrammar
                ? cursor.grammarFeatureCount + 1
                : 1
        )
    }

    private func profiledFeature(
        from cursor: TerrainCursor,
        profile: DownhillFeatureProfile,
        random: inout DeterministicRandom
    ) -> (segments: [TerrainSegment], exit: CGPoint, exitSlope: CGFloat) {
        let length = random.value(in: profile.length)
        let drop = random.value(in: profile.drop)
        let start = cursor.point
        let first = CGPoint(
            x: start.x + length * random.value(in: profile.firstControlFraction),
            y: start.y - drop * random.value(in: profile.firstDropFraction)
        )
        let second = CGPoint(
            x: start.x + length * random.value(in: profile.secondControlFraction),
            y: start.y - drop * random.value(in: profile.secondDropFraction)
        )
        let exit = CGPoint(x: start.x + length, y: start.y - drop)
        let entrySlope = random.value(in: profile.entrySlope)
        let middleSlope = random.value(in: profile.middleSlope)
        let exitSlope = -drop / length
        return (
            [
                TerrainSegment(start: start, end: first, startSlope: cursor.slope, endSlope: entrySlope, isLinear: false),
                TerrainSegment(start: first, end: second, startSlope: entrySlope, endSlope: middleSlope, isLinear: false),
                TerrainSegment(start: second, end: exit, startSlope: middleSlope, endSlope: exitSlope, isLinear: false)
            ],
            exit,
            exitSlope
        )
    }

    /// A long plunge followed by a shallow compression. The sharp change from
    /// a near-vertical face to a flatter catch naturally leaves the bike
    /// pitched forward unless the rider starts bringing it back.
    private func chuteFeature(
        from cursor: TerrainCursor,
        profile: DownhillChuteProfile,
        random: inout DeterministicRandom
    ) -> (segments: [TerrainSegment], exit: CGPoint, exitSlope: CGFloat) {
        let length = random.value(in: profile.length)
        let drop = random.value(in: profile.drop)
        let start = cursor.point
        let entry = CGPoint(
            x: start.x + length * random.value(in: profile.entryControlFraction),
            y: start.y - drop * random.value(in: profile.entryDropFraction)
        )
        let plunge = CGPoint(
            x: start.x + length * random.value(in: profile.plungeControlFraction),
            y: start.y - drop * random.value(in: profile.plungeDropFraction)
        )
        let exit = CGPoint(x: start.x + length, y: start.y - drop)
        let compression = CGPoint(
            x: start.x + length * random.value(in: profile.compressionControlFraction),
            y: exit.y + random.value(in: profile.compressionTailDrop)
        )
        let entrySlope = random.value(in: profile.entrySlope)
        let plungeSlope = random.value(in: profile.plungeSlope)
        let compressionSlope = random.value(in: profile.compressionSlope)
        let exitSlope = random.value(in: profile.exitSlope)
        return (
            [
                TerrainSegment(start: start, end: entry, startSlope: cursor.slope, endSlope: entrySlope, isLinear: false),
                TerrainSegment(start: entry, end: plunge, startSlope: entrySlope, endSlope: plungeSlope, isLinear: false),
                TerrainSegment(start: plunge, end: compression, startSlope: plungeSlope, endSlope: compressionSlope, isLinear: false),
                TerrainSegment(start: compression, end: exit, startSlope: compressionSlope, endSlope: exitSlope, isLinear: false)
            ],
            exit,
            exitSlope
        )
    }

    private func rollerFeature(
        from cursor: TerrainCursor,
        random: inout DeterministicRandom
    ) -> (segments: [TerrainSegment], exit: CGPoint, exitSlope: CGFloat) {
        let profile = GameTuning.Terrain.rollerProfile
        let length = random.value(in: profile.length)
        let drop = random.value(in: profile.drop)
        let start = cursor.point
        let first = CGPoint(
            x: start.x + length * random.value(in: profile.firstControlFraction),
            y: start.y - drop * random.value(in: profile.firstDropFraction)
        )
        let second = CGPoint(
            x: start.x + length * random.value(in: profile.secondControlFraction),
            y: start.y - drop * random.value(in: profile.secondDropFraction)
        )
        let third = CGPoint(
            x: start.x + length * random.value(in: profile.thirdControlFraction),
            y: start.y - drop * random.value(in: profile.thirdDropFraction)
        )
        let exit = CGPoint(x: start.x + length, y: start.y - drop)
        let entrySlope = random.value(in: profile.entrySlope)
        let firstSlope = random.value(in: profile.firstSlope)
        let secondSlope = random.value(in: profile.secondSlope)
        let exitSlope = -drop / length
        return (
            [
                TerrainSegment(start: start, end: first, startSlope: cursor.slope, endSlope: entrySlope, isLinear: false),
                TerrainSegment(start: first, end: second, startSlope: entrySlope, endSlope: firstSlope, isLinear: false),
                TerrainSegment(start: second, end: third, startSlope: firstSlope, endSlope: secondSlope, isLinear: false),
                TerrainSegment(start: third, end: exit, startSlope: secondSlope, endSlope: exitSlope, isLinear: false)
            ],
            exit,
            exitSlope
        )
    }

    private func lipFeature(
        from cursor: TerrainCursor,
        random: inout DeterministicRandom
    ) -> (segments: [TerrainSegment], exit: CGPoint, exitSlope: CGFloat) {
        let profile = GameTuning.Terrain.lipProfile
        let length = random.value(in: profile.length)
        let drop = random.value(in: profile.drop)
        let start = cursor.point
        let approachFraction = random.value(in: profile.approachControlFraction)
        let crestFraction = approachFraction + random.value(in: profile.crestOffsetFraction)
        let approach = CGPoint(
            x: start.x + length * approachFraction,
            y: start.y - (
                drop * random.value(in: profile.approachDropFraction)
                    + length * random.value(in: profile.approachLengthDropFraction)
            )
        )
        let climb = random.value(in: profile.climb)
        let crest = CGPoint(
            x: max(
                start.x + length * crestFraction,
                approach.x + GameTuning.Terrain.minimumRollableRampLength
            ),
            y: approach.y + climb
        )
        let takeoffTip = CGPoint(
            x: crest.x + GameTuning.Terrain.roundedTakeoffLength,
            y: crest.y + GameTuning.Terrain.roundedTakeoffRise
        )
        let releaseEnd = CGPoint(
            x: takeoffTip.x + GameTuning.Terrain.roundedReleaseLength,
            y: takeoffTip.y - GameTuning.Terrain.roundedReleaseDrop
        )
        // Ordinary lips are closed rollers, not mandatory holes. Their short
        // fall-away is curved enough to release a fast bike naturally, while a
        // slow rider continues down a real surface instead of meeting a gap.
        let landingEntryY = crest.y - random.value(in: profile.lipDrop)
        let landingEntryLength = max(
            random.value(in: GameTuning.Terrain.roundedLipLandingLength),
            abs(releaseEnd.y - landingEntryY) / GameTuning.Terrain.maximumLandingApproachSlope
        )
        let landingEntry = CGPoint(
            x: releaseEnd.x + landingEntryLength,
            y: landingEntryY
        )
        let exit = CGPoint(
            x: start.x + length + GameTuning.Terrain.lipLandingRunout,
            y: landingEntry.y
                + (start.x + length + GameTuning.Terrain.lipLandingRunout - landingEntry.x)
                    * GameTuning.Terrain.lipLandingRunoutSlope
        )
        let troughSlope = random.value(in: profile.troughSlope)
        let crestSlope = min(
            random.value(in: profile.crestSlope),
            GameTuning.Terrain.maximumRollableUphillSlope
        )
        let exitSlope = GameTuning.Terrain.lipLandingRunoutSlope
        return (
            [
                TerrainSegment(start: start, end: approach, startSlope: cursor.slope, endSlope: troughSlope, isLinear: false),
                TerrainSegment(start: approach, end: crest, startSlope: troughSlope, endSlope: crestSlope, isLinear: false),
                TerrainSegment(
                    start: crest,
                    end: takeoffTip,
                    startSlope: crestSlope,
                    endSlope: GameTuning.Terrain.roundedTakeoffEndSlope,
                    isLinear: false,
                    maximumUphillSlope: GameTuning.Terrain.roundedTakeoffEndSlope
                ),
                TerrainSegment(
                    start: takeoffTip,
                    end: releaseEnd,
                    startSlope: GameTuning.Terrain.roundedTakeoffEndSlope,
                    endSlope: GameTuning.Terrain.roundedReleaseEndSlope,
                    isLinear: false,
                    maximumUphillSlope: GameTuning.Terrain.roundedTakeoffEndSlope
                ),
                TerrainSegment(
                    start: releaseEnd,
                    end: landingEntry,
                    startSlope: GameTuning.Terrain.roundedReleaseEndSlope,
                    endSlope: GameTuning.Terrain.lipLandingEntrySlope,
                    isLinear: false
                ),
                TerrainSegment(
                    start: landingEntry,
                    end: exit,
                    startSlope: GameTuning.Terrain.lipLandingEntrySlope,
                    endSlope: exitSlope,
                    isLinear: false
                )
            ],
            exit,
            exitSlope
        )
    }

    /// A rising crest feeds a convex launch, then rolls into a continuous,
    /// curved cliff drop. The surface can still launch a fast rider, but it
    /// never ends in an out-of-bounds rail or a vertical landing wall.
    private func stepDownFeature(
        from cursor: TerrainCursor,
        profile: DownhillStepDownProfile,
        random: inout DeterministicRandom
    ) -> (segments: [TerrainSegment], exit: CGPoint, exitSlope: CGFloat) {
        let length = random.value(in: profile.length)
        let drop = random.value(in: profile.drop)
        let start = cursor.point
        let approach = CGPoint(
            x: start.x + length * random.value(in: profile.approachControlFraction),
            y: start.y - drop * random.value(in: profile.approachDropFraction)
        )
        let climb = random.value(in: profile.climb)
        let crest = CGPoint(
            x: max(
                start.x + length * random.value(in: profile.crestControlFraction),
                approach.x + GameTuning.Terrain.minimumRollableRampLength
            ),
            y: approach.y + climb
        )
        let takeoffTip = CGPoint(
            x: crest.x + GameTuning.Terrain.stepDownTakeoffLength,
            y: crest.y + GameTuning.Terrain.stepDownTakeoffRise
        )
        let cliffDrop = drop * random.value(in: profile.cliffDropFraction)
        let releaseEnd = CGPoint(
            x: takeoffTip.x + GameTuning.Terrain.stepDownReleaseLength,
            y: takeoffTip.y - GameTuning.Terrain.stepDownReleaseDrop
        )
        let remainingCliffDrop = max(
            0,
            cliffDrop - GameTuning.Terrain.stepDownReleaseDrop
        )
        let cliffLength = max(
            length * random.value(in: profile.cliffLengthFraction),
            GameTuning.Terrain.stepDownReleaseLength
                + remainingCliffDrop / GameTuning.Terrain.maximumContinuousCliffSlope
        )
        let cliffEnd = CGPoint(
            x: takeoffTip.x + cliffLength,
            y: takeoffTip.y - cliffDrop
        )
        let landingY = start.y - drop * random.value(in: profile.landingDropFraction)
        let landingLength = max(
            length * random.value(in: profile.landingLengthFraction),
            abs(landingY - cliffEnd.y) / GameTuning.Terrain.maximumLandingApproachSlope
        )
        let landing = CGPoint(
            x: cliffEnd.x + landingLength,
            y: landingY
        )
        let troughSlope = random.value(in: profile.troughSlope)
        let crestSlope = min(
            random.value(in: profile.crestSlope),
            GameTuning.Terrain.maximumRollableUphillSlope
        )
        let cliffSlope = random.value(in: profile.cliffSlope)
        let landingSlope = random.value(in: profile.landingSlope)
        let exitSlope = random.value(in: profile.exitSlope)
        let exitX = max(
            start.x + length + GameTuning.Terrain.stepDownLandingRunout,
            landing.x + GameTuning.Terrain.stepDownLandingRunout
        )
        let exit = CGPoint(
            x: exitX,
            y: landing.y
                + (exitX - landing.x) * exitSlope
        )
        return (
            [
                TerrainSegment(start: start, end: approach, startSlope: cursor.slope, endSlope: troughSlope, isLinear: false),
                TerrainSegment(start: approach, end: crest, startSlope: troughSlope, endSlope: crestSlope, isLinear: false),
                TerrainSegment(
                    start: crest,
                    end: takeoffTip,
                    startSlope: crestSlope,
                    endSlope: GameTuning.Terrain.stepDownTakeoffEndSlope,
                    isLinear: false,
                    maximumUphillSlope: GameTuning.Terrain.stepDownTakeoffEndSlope
                ),
                TerrainSegment(
                    start: takeoffTip,
                    end: releaseEnd,
                    startSlope: GameTuning.Terrain.stepDownTakeoffEndSlope,
                    endSlope: GameTuning.Terrain.stepDownReleaseEndSlope,
                    isLinear: false,
                    maximumUphillSlope: GameTuning.Terrain.stepDownTakeoffEndSlope
                ),
                TerrainSegment(
                    start: releaseEnd,
                    end: cliffEnd,
                    startSlope: GameTuning.Terrain.stepDownReleaseEndSlope,
                    endSlope: cliffSlope,
                    isLinear: false
                ),
                TerrainSegment(start: cliffEnd, end: landing, startSlope: cliffSlope, endSlope: landingSlope, isLinear: false),
                TerrainSegment(start: landing, end: exit, startSlope: landingSlope, endSlope: exitSlope, isLinear: false)
            ],
            exit,
            exitSlope
        )
    }

    private func sampledPoints(from segments: [TerrainSegment]) -> [CGPoint] {
        var sampled: [CGPoint] = []

        for segment in segments {
            let span = segment.end.x - segment.start.x
            let averageSlope = (segment.end.y - segment.start.y) / max(span, 1)
            let steepestSlope = max(abs(segment.startSlope), abs(segment.endSlope), abs(averageSlope))
            let estimatedLength = span * CGFloat(sqrt(1 + steepestSlope * steepestSlope))
            let steps = max(1, Int(ceil(estimatedLength / GameTuning.Terrain.maximumColliderSegmentLength)))

            for step in 0...steps {
                if !sampled.isEmpty, step == 0 { continue }

                let t = CGFloat(step) / CGFloat(steps)
                let x = segment.start.x + span * t
                let y: CGFloat
                if segment.isLinear {
                    y = segment.start.y + (segment.end.y - segment.start.y) * t
                } else {
                    let t2 = t * t
                    let t3 = t2 * t
                    let h00 = 2 * t3 - 3 * t2 + 1
                    let h10 = t3 - 2 * t2 + t
                    let h01 = -2 * t3 + 3 * t2
                    let h11 = t3 - t2
                    y = h00 * segment.start.y
                        + h10 * span * segment.startSlope
                        + h01 * segment.end.y
                        + h11 * span * segment.endSlope
                }
                sampled.append(CGPoint(x: x, y: y))
            }
        }
        return sampled
    }

    /// Each run is sampled once and then shared by the drawn edge and its
    /// physics body. An air-gap segment deliberately ends one run and begins
    /// the next without a bridging line or collision edge.
    private func sampledSurfaceRuns(from segments: [TerrainSegment]) -> [[CGPoint]] {
        var runs: [[CGPoint]] = []
        var currentRun: [CGPoint] = []

        for segment in segments {
            guard segment.isSurface else {
                if currentRun.count > 1 {
                    runs.append(currentRun)
                }
                currentRun.removeAll(keepingCapacity: true)
                continue
            }

            let segmentPoints = sampledPoints(from: [segment])
            if currentRun.isEmpty {
                currentRun.append(contentsOf: segmentPoints)
            } else {
                currentRun.append(contentsOf: segmentPoints.dropFirst())
            }
        }

        if currentRun.count > 1 {
            runs.append(currentRun)
        }
        return runs
    }

    private func makeSceneryNode(
        for points: [CGPoint],
        chunkIndex: Int,
        biome: TerrainBiome
    ) -> SKNode {
        let scenery = SKNode()
        guard let first = points.first, let last = points.last else { return scenery }

        var random = DeterministicRandom(seed: terrainSeed ^ UInt64(chunkIndex + 1))
        for treeIndex in 0..<3 {
            let x = first.x + (last.x - first.x) * random.value(in: 0.16...0.88)
            let tree = makePine(
                height: random.value(in: 60...94),
                snowCovered: biome.snowCovered
            )
            tree.position = CGPoint(x: x, y: terrainHeight(in: points, at: x) - 5)
            tree.alpha = treeIndex.isMultiple(of: 2) ? 0.82 : 0.62
            scenery.addChild(tree)
        }
        return scenery
    }

    private func terrainBiome(at x: CGFloat) -> TerrainBiome {
        let distanceMeters = max(
            0,
            (x - GameTuning.Bike.spawnX) / GameTuning.Display.worldUnitsPerMeter
        )
        let zoneIndex = Int(
            distanceMeters / GameTuning.Terrain.biomeZoneLengthMeters
        ) % TerrainBiome.allCases.count
        return TerrainBiome(rawValue: zoneIndex) ?? .summitIce
    }

    private func colors(for biome: TerrainBiome) -> (edge: SKColor, fill: SKColor) {
        precondition(
            Self.biomePalettes.count == TerrainBiome.allCases.count,
            "Every terrain biome needs a visual palette."
        )
        let palette = Self.biomePalettes[biome.rawValue]
        return (palette.edge, palette.fill)
    }

    func terrainHeight(at x: CGFloat) -> CGFloat {
        terrainHeight(in: terrainPoints, at: x)
    }

    private func terrainHeight(in points: [CGPoint], at x: CGFloat) -> CGFloat {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let next = points[index]
            if x <= next.x {
                let t = (x - previous.x) / (next.x - previous.x)
                return previous.y + (next.y - previous.y) * t
            }
        }
        return last.y
    }

    func terrainSlope(at x: CGFloat) -> CGFloat {
        guard terrainPoints.count > 1 else { return 0 }
        if x <= terrainPoints[0].x {
            return slope(between: terrainPoints[0], terrainPoints[1])
        }

        for index in 1..<terrainPoints.count {
            if x <= terrainPoints[index].x {
                return slope(between: terrainPoints[index - 1], terrainPoints[index])
            }
        }
        return slope(between: terrainPoints[terrainPoints.count - 2], terrainPoints[terrainPoints.count - 1])
    }

    private func terrainTangent(at x: CGFloat) -> CGVector {
        let ySlope = terrainSlope(at: x)
        let length = CGFloat(hypot(1, Double(ySlope)))
        return CGVector(dx: 1 / length, dy: ySlope / length)
    }

    /// Terrain queries that affect tire drive or rider attitude must ignore a
    /// reference-only air-gap line. Otherwise the controller reacts to ground
    /// the bike cannot actually touch as it leaves a lip.
    func surfaceTerrainHeight(at x: CGFloat) -> CGFloat? {
        for chunk in terrainChunks {
            for run in chunk.surfaceRuns {
                guard let first = run.first, let last = run.last,
                      x >= first.x, x <= last.x else {
                    continue
                }
                return terrainHeight(in: run, at: x)
            }
        }
        return nil
    }

    func surfaceTerrainSlope(at x: CGFloat) -> CGFloat? {
        for chunk in terrainChunks {
            for run in chunk.surfaceRuns {
                guard let first = run.first, let last = run.last,
                      x >= first.x, x <= last.x, run.count > 1 else {
                    continue
                }
                if x <= first.x {
                    return slope(between: run[0], run[1])
                }
                for index in 1..<run.count where x <= run[index].x {
                    return slope(between: run[index - 1], run[index])
                }
                return slope(between: run[run.count - 2], run[run.count - 1])
            }
        }
        return nil
    }

    func surfaceTerrainTangent(at x: CGFloat) -> CGVector? {
        guard let ySlope = surfaceTerrainSlope(at: x) else { return nil }
        let length = CGFloat(hypot(1, Double(ySlope)))
        return CGVector(dx: 1 / length, dy: ySlope / length)
    }

    func supportAngle(at x: CGFloat) -> CGFloat {
        let halfWheelbase = GameTuning.Bike.wheelOffsetX
        let rearX = x - halfWheelbase
        let frontX = x + halfWheelbase
        let rearHeight = surfaceTerrainHeight(at: rearX)
        let frontHeight = surfaceTerrainHeight(at: frontX)

        if let rearHeight, let frontHeight {
            return atan2(frontHeight - rearHeight, halfWheelbase * 2)
        }
        if let rearSlope = surfaceTerrainSlope(at: rearX) {
            return atan(rearSlope)
        }
        if let frontSlope = surfaceTerrainSlope(at: frontX) {
            return atan(frontSlope)
        }
        return 0
    }

    /// The rider/frame is visual, so it has no SpriteKit collision body of its
    /// own. These probes give it the one consequence a Trials-style bike needs:

    private func makePine(height: CGFloat, snowCovered: Bool) -> SKNode {
        let tree = SKNode()
        let trunk = SKShapeNode(rectOf: CGSize(width: height * 0.13, height: height * 0.34))
        trunk.fillColor = SKColor(red: 0.20, green: 0.13, blue: 0.09, alpha: 1)
        trunk.strokeColor = .clear
        trunk.position.y = height * 0.16
        tree.addChild(trunk)

        let foliageColor = snowCovered
            ? SKColor(red: 0.07, green: 0.19, blue: 0.22, alpha: 1)
            : SKColor(red: 0.05, green: 0.22, blue: 0.17, alpha: 1)
        for (index, scale) in [0.82, 0.64, 0.46].enumerated() {
            let width = height * CGFloat(scale)
            let y = height * (0.26 + CGFloat(index) * 0.19)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -width / 2, y: y))
            path.addLine(to: CGPoint(x: 0, y: y + height * 0.42))
            path.addLine(to: CGPoint(x: width / 2, y: y))
            path.closeSubpath()
            let foliage = SKShapeNode(path: path)
            foliage.fillColor = foliageColor
            foliage.strokeColor = .clear
            tree.addChild(foliage)

            if snowCovered {
                let snowPath = CGMutablePath()
                let snowWidth = width * 0.66
                snowPath.move(to: CGPoint(x: -snowWidth / 2, y: y + height * 0.17))
                snowPath.addLine(to: CGPoint(x: 0, y: y + height * 0.42))
                snowPath.addLine(to: CGPoint(x: snowWidth / 2, y: y + height * 0.17))
                snowPath.closeSubpath()
                let snow = SKShapeNode(path: snowPath)
                snow.fillColor = SKColor(red: 0.92, green: 0.97, blue: 1, alpha: 0.92)
                snow.strokeColor = .clear
                tree.addChild(snow)
            }
        }
        return tree
    }

    private func slope(between first: CGPoint, _ second: CGPoint) -> CGFloat {
        (second.y - first.y) / max(second.x - first.x, 1)
    }
}

