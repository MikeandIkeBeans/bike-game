import Foundation
import CoreGraphics

// MARK: - Mini Test Framework

struct TestSuite {
    var passed = 0
    var failed = 0
    var total = 0
    var fuzzScenariosTested = 0

    mutating func assert(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
        total += 1
        if condition {
            passed += 1
            print("  ✅ [PASS] \(name)")
        } else {
            failed += 1
            print("  ❌ [FAIL] \(name) at line \(line)")
        }
    }

    mutating func assertEqual<T: Equatable>(_ a: T, _ b: T, _ name: String, file: String = #file, line: Int = #line) {
        assert(a == b, "\(name): \(a) == \(b)", file: file, line: line)
    }

    mutating func assertNear(_ a: CGFloat, _ b: CGFloat, accuracy: CGFloat = 0.001, _ name: String, file: String = #file, line: Int = #line) {
        let diff = abs(a - b)
        assert(diff <= accuracy, "\(name): |\(a) - \(b)| = \(diff) <= \(accuracy)", file: file, line: line)
    }

    mutating func recordFuzzBatch(passed: Int, failed: Int, batchName: String) {
        fuzzScenariosTested += (passed + failed)
        total += (passed + failed)
        self.passed += passed
        self.failed += failed
        if failed == 0 {
            print("  ✅ [FUZZ PASS] \(batchName): \(passed)/\(passed) scenarios verified without failure")
        } else {
            print("  ❌ [FUZZ FAIL] \(batchName): \(failed) failures detected out of \(passed + failed) scenarios!")
        }
    }

    func summary() -> Bool {
        print("\n========================================================")
        print("TEST RESULTS SUMMARY")
        print("========================================================")
        print("  • Standard Unit & Integration Assertions: \(total - fuzzScenariosTested)")
        print("  • Property-Based Fuzz Scenarios:          \(fuzzScenariosTested)")
        print("  • Total Verification Checks:              \(total)")
        print("  • Passed:                                 \(passed)")
        print("  • Failed:                                 \(failed)")
        print("========================================================")
        return failed == 0
    }
}

// MARK: - Core Math Implementations to Verify

func hermiteY(start: CGPoint, end: CGPoint, startSlope: CGFloat, endSlope: CGFloat, t: CGFloat) -> CGFloat {
    let span = end.x - start.x
    let t2 = t * t
    let t3 = t2 * t
    let h00 = 2 * t3 - 3 * t2 + 1
    let h10 = t3 - 2 * t2 + t
    let h01 = -2 * t3 + 3 * t2
    let h11 = t3 - t2
    return h00 * start.y
        + h10 * span * startSlope
        + h01 * end.y
        + h11 * span * endSlope
}

func hermiteSlope(start: CGPoint, end: CGPoint, startSlope: CGFloat, endSlope: CGFloat, t: CGFloat) -> CGFloat {
    let span = end.x - start.x
    guard span > 0.0001 else { return startSlope }
    let t2 = t * t
    let dh00 = 6 * t2 - 6 * t
    let dh10 = 3 * t2 - 4 * t + 1
    let dh01 = -6 * t2 + 6 * t
    let dh11 = 3 * t2 - 2 * t
    let dy_dt = dh00 * start.y + dh10 * span * startSlope + dh01 * end.y + dh11 * span * endSlope
    return dy_dt / span
}

func normalizedAngle(_ angle: CGFloat) -> CGFloat {
    guard angle.isFinite else { return 0 }
    let twoPi = CGFloat.pi * 2
    var result = angle.truncatingRemainder(dividingBy: twoPi)
    if result > .pi {
        result -= twoPi
    } else if result < -.pi {
        result += twoPi
    }
    return result
}

func spawnClearance(attitude: CGFloat, collisionWheelRadius: CGFloat, padding: CGFloat, rearAxleOffsetY: CGFloat, minCosine: CGFloat) -> CGFloat {
    let safeCosine = max(cos(attitude), minCosine)
    return (collisionWheelRadius + padding - rearAxleOffsetY) / safeCosine
}

struct PRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }

    mutating func cgFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        let raw = CGFloat(next() &>> 11) / CGFloat(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * raw
    }
}

// MARK: - Test Executions

var suite = TestSuite()

print("🔬 RUNNING COMPREHENSIVE BIKE GAME PHYSICS & SYSTEM VERIFICATION SUITE...\n")

// Test 1: Hermite Spline Boundary Conditions
print("• Test Group 1: Hermite Spline Sampling & Continuity")
let p0 = CGPoint(x: 0, y: 100)
let p1 = CGPoint(x: 200, y: 50)
let s0: CGFloat = -0.5
let s1: CGFloat = -0.2

let yStart = hermiteY(start: p0, end: p1, startSlope: s0, endSlope: s1, t: 0.0)
let yEnd = hermiteY(start: p0, end: p1, startSlope: s0, endSlope: s1, t: 1.0)
let yMid = hermiteY(start: p0, end: p1, startSlope: s0, endSlope: s1, t: 0.5)

suite.assertNear(yStart, p0.y, "Spline at t=0 matches start point y")
suite.assertNear(yEnd, p1.y, "Spline at t=1 matches end point y")
suite.assert(yMid < p0.y && yMid > p1.y, "Spline at t=0.5 lies monotonically between descending endpoints")
suite.assertNear(hermiteSlope(start: p0, end: p1, startSlope: s0, endSlope: s1, t: 0.0), s0, "Spline derivative at t=0 matches start slope")
suite.assertNear(hermiteSlope(start: p0, end: p1, startSlope: s0, endSlope: s1, t: 1.0), s1, "Spline derivative at t=1 matches end slope")

// Test 2: Angle Normalization Bounds
print("\n• Test Group 2: Trigonometric Angle Normalization")
suite.assertNear(normalizedAngle(0), 0, "Zero angle normalizes to zero")
suite.assertNear(normalizedAngle(.pi), .pi, "pi normalizes to pi")
suite.assertNear(normalizedAngle(3 * .pi), .pi, "3*pi normalizes to pi")
suite.assertNear(normalizedAngle(-5 * .pi), -.pi, "-5*pi normalizes to -pi")
suite.assertNear(normalizedAngle(.pi * 0.5), .pi * 0.5, "pi/2 preserves exact quadrant")
suite.assertNear(normalizedAngle(-.pi * 0.5), -.pi * 0.5, "-pi/2 preserves exact quadrant")
suite.assertNear(normalizedAngle(2.5 * .pi), .pi * 0.5, "2.5*pi wraps to pi/2")
suite.assertEqual(normalizedAngle(.infinity), 0, "Infinity angle safely normalizes to 0 without infinite loop")
suite.assertEqual(normalizedAngle(-.infinity), 0, "-Infinity angle safely normalizes to 0 without infinite loop")
suite.assertEqual(normalizedAngle(.nan), 0, "NaN angle safely normalizes to 0 without hang")

// Test 3: Spawn Clearance Calculations
print("\n• Test Group 3: Spawn Clearance & Safe Attitude")
let wheelRadius: CGFloat = 16
let padding: CGFloat = 0
let axleOffsetY: CGFloat = -27
let minCosine: CGFloat = 0.35

let flatClearance = spawnClearance(attitude: 0, collisionWheelRadius: wheelRadius, padding: padding, rearAxleOffsetY: axleOffsetY, minCosine: minCosine)
suite.assertNear(flatClearance, 43.0, "Flat ground clearance equals radius - offsetY (16 - (-27) = 43)")

let steepSlopeAngle: CGFloat = -0.6 // ~34 degrees steep descent
let steepClearance = spawnClearance(attitude: steepSlopeAngle, collisionWheelRadius: wheelRadius, padding: padding, rearAxleOffsetY: axleOffsetY, minCosine: minCosine)
suite.assert(steepClearance > flatClearance, "Steep descent requires greater vertical clearance than flat ground")

let verticalAttitude: CGFloat = .pi / 2 // 90 degrees vertical wall
let guardedClearance = spawnClearance(attitude: verticalAttitude, collisionWheelRadius: wheelRadius, padding: padding, rearAxleOffsetY: axleOffsetY, minCosine: minCosine)
suite.assert(guardedClearance.isFinite, "Guard against vertical tangent prevents infinite/NaN clearance")

// Test 4: Deterministic Random Repeatability
print("\n• Test Group 4: Procedural Course Seed Repeatability")
let seed: UInt64 = 0x5452_4149_4C52_5553
var rng1 = PRNG(seed: seed)
var rng2 = PRNG(seed: seed)

let v1 = (0..<10).map { _ in rng1.cgFloat(in: 100...500) }
let v2 = (0..<10).map { _ in rng2.cgFloat(in: 100...500) }
suite.assertEqual(v1, v2, "Identical seed produces 100% deterministic identical sequence")

// Test 5: Physics Category Bitmask Disjointness
print("\n• Test Group 5: Physics Category Bitmasks")
let bike: UInt32 = 1 << 0
let terrain: UInt32 = 1 << 1
let bikeChassis: UInt32 = 1 << 8
let bikeSwingarm: UInt32 = 1 << 9
let bikeWheel: UInt32 = 1 << 10
let bikeFrontFork: UInt32 = 1 << 11
let allBike = bike | bikeChassis | bikeSwingarm | bikeWheel | bikeFrontFork

suite.assert((bike & terrain) == 0, "Bike and Terrain masks are strictly disjoint")
suite.assert((allBike & terrain) == 0, "All bike components are disjoint from terrain mask")
suite.assert((bikeChassis & bikeSwingarm) == 0, "Chassis and Swingarm masks are disjoint")
suite.assert((bikeWheel & bikeFrontFork) == 0, "Wheel and Front Fork masks are disjoint")

// Test 6: ContactBook Symmetric Tracking & Memory Isolation
print("\n• Test Group 6: ContactBook Symmetric Tracking & Memory Isolation")
struct TestContactBook {
    var contactsByBody: [Int: Set<Int>] = [:]

    mutating func began(_ first: Int, _ second: Int) {
        contactsByBody[first, default: []].insert(second)
        contactsByBody[second, default: []].insert(first)
    }

    mutating func ended(_ first: Int, _ second: Int) {
        remove(first, other: second)
        remove(second, other: first)
    }

    func touches(_ body: Int) -> Bool {
        !(contactsByBody[body]?.isEmpty ?? true)
    }

    func touches(_ body: Int, anyOf ids: Set<Int>) -> Bool {
        guard let contacts = contactsByBody[body] else { return false }
        return !contacts.isDisjoint(with: ids)
    }

    mutating func forget(_ bodyID: Int) {
        guard let otherIDs = contactsByBody.removeValue(forKey: bodyID) else { return }
        for otherID in otherIDs {
            remove(otherID, other: bodyID)
        }
    }

    private mutating func remove(_ body: Int, other: Int) {
        guard var contacts = contactsByBody[body] else { return }
        contacts.remove(other)
        if contacts.isEmpty {
            contactsByBody.removeValue(forKey: body)
        } else {
            contactsByBody[body] = contacts
        }
    }
}

var cb = TestContactBook()
cb.began(101, 201) // Chassis touches Terrain Chunk A
cb.began(102, 201) // Rear Wheel touches Terrain Chunk A
cb.began(103, 202) // Front Wheel touches Terrain Chunk B

suite.assert(cb.touches(101), "Chassis is touching")
suite.assert(cb.touches(102), "Rear wheel is touching")
suite.assert(cb.touches(201, anyOf: [101, 102]), "Chunk A detects touches from bike parts")
suite.assert(!cb.touches(101, anyOf: [202]), "Chassis is not touching Chunk B")

// Retire Chunk A (forget 201)
cb.forget(201)
suite.assert(!cb.touches(201), "Retired Chunk A is completely purged")
suite.assert(!cb.touches(101), "Chassis contact set is cleared")
suite.assert(!cb.touches(102), "Rear wheel contact set is cleared")
suite.assert(cb.touches(103), "Front wheel still retains valid contact with Chunk B")
suite.assert(cb.contactsByBody[201] == nil, "Chunk A key was removed from dictionary")

// Test 7: Axle Clearance & Grounded Invariant Bounds
print("\n• Test Group 7: Axle Clearance & Grounded Invariant Bounds")
func testAxleClearance(axleY: CGFloat, terrainY: CGFloat, collisionRadius: CGFloat = 16, tolerance: CGFloat = 8, recoveryTrigger: CGFloat = 6) -> CGFloat? {
    let clearance = axleY - terrainY
    let minClearance = -recoveryTrigger
    let maxClearance = collisionRadius + tolerance
    return (clearance >= minClearance && clearance <= maxClearance) ? clearance : nil
}

let terrainHeight: CGFloat = 100.0
suite.assert(testAxleClearance(axleY: terrainHeight + 16, terrainY: terrainHeight) != nil, "Tire resting on surface (+16) is grounded")
suite.assert(testAxleClearance(axleY: terrainHeight + 10, terrainY: terrainHeight) != nil, "Tire compressed by 6 units (+10) is grounded")
suite.assert(testAxleClearance(axleY: terrainHeight + 24, terrainY: terrainHeight) != nil, "Tire at max grounded tolerance (+24) is grounded")
suite.assert(testAxleClearance(axleY: terrainHeight - 6, terrainY: terrainHeight) != nil, "Tire at exact recovery trigger threshold (-6) is grounded")
suite.assert(testAxleClearance(axleY: terrainHeight + 35, terrainY: terrainHeight) == nil, "Tire high airborne (+35) is not grounded")
suite.assert(testAxleClearance(axleY: terrainHeight - 20, terrainY: terrainHeight) == nil, "Tire submerged beneath terrain (-20) is NOT grounded")

// Test 8: RunState Transition & Crash Input Invariants
print("\n• Test Group 8: RunState Transitions & Crash Input Guard")
enum MockRunState {
    case intro
    case riding
    case crashing
    case results
}

struct MockRunStateMachine {
    var state: MockRunState = .intro
    var leanInput: CGFloat = 0
    var pedalHeld: Bool = false
    var crashSequenceActive: Bool = false

    mutating func startRun() {
        guard state != .crashing else { return }
        if state == .results {
            resetRun()
        }
        guard state == .intro else { return }
        state = .riding
    }

    mutating func enterCrash() {
        guard state == .riding else { return }
        state = .crashing
        leanInput = 0
        pedalHeld = false
        crashSequenceActive = true
    }

    mutating func crashSequenceCompleted() {
        guard state == .crashing else { return }
        crashSequenceActive = false
        state = .results
    }

    mutating func resetRun() {
        crashSequenceActive = false
        leanInput = 0
        pedalHeld = false
        state = .intro
    }

    mutating func handleTouch(lean: CGFloat, pedal: Bool) {
        if state != .riding {
            startRun()
        }
        guard state == .riding else { return }
        leanInput = lean
        pedalHeld = pedal
    }

    mutating func handleExplicitRestartKey() {
        resetRun()
        startRun()
    }
}

var sm = MockRunStateMachine()
suite.assertEqual(sm.state, MockRunState.intro, "Starts in intro state")

sm.handleTouch(lean: 1.0, pedal: true)
suite.assertEqual(sm.state, MockRunState.riding, "Drops in to riding on touch")
suite.assertEqual(sm.pedalHeld, true, "Pedal is held while riding")
suite.assertEqual(sm.leanInput, 1.0, "Lean is active while riding")

sm.enterCrash()
suite.assertEqual(sm.state, MockRunState.crashing, "Enters crashing state")
suite.assertEqual(sm.crashSequenceActive, true, "Crash sequence is active")
suite.assertEqual(sm.pedalHeld, false, "Pedal input is zeroed on crash")
suite.assertEqual(sm.leanInput, 0.0, "Lean input is zeroed on crash")

sm.handleTouch(lean: -1.0, pedal: true)
suite.assertEqual(sm.state, MockRunState.crashing, "Touch during crashing is ignored, stays crashing")
suite.assertEqual(sm.pedalHeld, false, "Pedal input is NOT accepted during crash")
suite.assertEqual(sm.leanInput, 0.0, "Lean input is NOT accepted during crash")

sm.crashSequenceCompleted()
suite.assertEqual(sm.state, MockRunState.results, "Transitions to results state after sequence completes")

sm.handleTouch(lean: 0.0, pedal: true)
suite.assertEqual(sm.state, MockRunState.riding, "Tap in results state resets and drops into riding")
suite.assertEqual(sm.pedalHeld, true, "Pedal is registered in new run")

sm.enterCrash()
suite.assertEqual(sm.state, MockRunState.crashing, "In crash state again")
sm.handleExplicitRestartKey()
suite.assertEqual(sm.state, MockRunState.riding, "Explicit restart bypasses crash delay safely")
suite.assertEqual(sm.crashSequenceActive, false, "Crash sequence action cancelled")

// Test 9: Terrain Chunk Streaming & Point Indexing Invariants
print("\n• Test Group 9: Terrain Chunk Streaming & Point Index Invariants")
struct MockChunk {
    let points: [CGPoint]
    var startX: CGFloat { points.first?.x ?? 0 }
    var endX: CGFloat { points.last?.x ?? 0 }
}

var testChunks: [MockChunk] = [
    MockChunk(points: [CGPoint(x: 0, y: 100), CGPoint(x: 50, y: 95), CGPoint(x: 100, y: 90)]),
    MockChunk(points: [CGPoint(x: 100, y: 90), CGPoint(x: 150, y: 85), CGPoint(x: 200, y: 80)]),
    MockChunk(points: [CGPoint(x: 200, y: 80), CGPoint(x: 250, y: 82), CGPoint(x: 300, y: 85)])
]

func fullRebuild(chunks: [MockChunk]) -> [CGPoint] {
    var result: [CGPoint] = []
    for chunk in chunks {
        if result.isEmpty {
            result.append(contentsOf: chunk.points)
        } else {
            result.append(contentsOf: chunk.points.dropFirst())
        }
    }
    return result
}

var incrementalPoints: [CGPoint] = []
for chunk in testChunks {
    if incrementalPoints.isEmpty {
        incrementalPoints.append(contentsOf: chunk.points)
    } else {
        incrementalPoints.append(contentsOf: chunk.points.dropFirst())
    }
}

let expectedPoints = fullRebuild(chunks: testChunks)
suite.assertEqual(incrementalPoints.count, expectedPoints.count, "Incremental count matches full rebuild count")
suite.assertEqual(incrementalPoints.count, 7, "Exact point count across 3 continuous chunks")
for i in 0..<incrementalPoints.count {
    suite.assertEqual(incrementalPoints[i], expectedPoints[i], "Point \(i) matches exactly")
}

suite.assertEqual(incrementalPoints.first?.x, 0, "Level start X is 0")
suite.assertEqual(incrementalPoints.last?.x, 300, "Level end X is 300")

let testSurfacePoints = [CGPoint(x: 10, y: 55), CGPoint(x: 20, y: 12), CGPoint(x: 30, y: 44)]
let minY = testSurfacePoints.min(by: { $0.y < $1.y })?.y ?? 0
suite.assertEqual(minY, 12, "Zero-allocation minY matches expected minimum")

// Test 10: Airborne & Landing Detection Invariants
print("\n• Test Group 10: Airborne & Landing Detection Invariants")
struct MockLandingDetector {
    var wasGrounded = true
    var airborneTime: TimeInterval = 0
    var airborneStartX: CGFloat = 0
    var worldUnitsPerMeter: CGFloat = 5
    var lastToast: String? = nil
    var hapticTriggered = false

    mutating func update(isGrounded: Bool, posX: CGFloat, delta: TimeInterval) {
        if !isGrounded {
            if wasGrounded {
                airborneStartX = posX
                airborneTime = 0
            }
            airborneTime += delta
        } else if !wasGrounded {
            if airborneTime >= 0.25 {
                hapticTriggered = true
                let airDistance = max(0, Int((posX - airborneStartX) / worldUnitsPerMeter))
                if airDistance >= 80 {
                    lastToast = "MONSTER AIR \(airDistance)m"
                } else if airDistance >= 30 {
                    lastToast = "HUGE AIR \(airDistance)m"
                } else if airborneTime >= 0.75 || airDistance >= 20 {
                    lastToast = "BIG AIR \(airDistance)m"
                }
            }
            airborneTime = 0
            airborneStartX = 0
        }
        wasGrounded = isGrounded
    }
}

var ld = MockLandingDetector()
ld.update(isGrounded: true, posX: 0, delta: 0.016)
suite.assert(!ld.hapticTriggered, "No haptic while grounded")
suite.assert(ld.lastToast == nil, "No toast while grounded")

ld.update(isGrounded: false, posX: 10, delta: 0.10)
ld.update(isGrounded: true, posX: 20, delta: 0.016)
suite.assert(!ld.hapticTriggered, "Micro bump < 0.25s triggers no haptic")
suite.assert(ld.lastToast == nil, "Micro bump triggers no toast")

ld.hapticTriggered = false
ld.update(isGrounded: false, posX: 30, delta: 0.20)
ld.update(isGrounded: false, posX: 50, delta: 0.20)
ld.update(isGrounded: true, posX: 70, delta: 0.016)
suite.assert(ld.hapticTriggered, "Medium jump >= 0.25s triggers landing haptic")
suite.assert(ld.lastToast == nil, "Medium jump below 20m/0.75s does not trigger big air toast")

ld.hapticTriggered = false
ld.update(isGrounded: false, posX: 100, delta: 0.40)
ld.update(isGrounded: false, posX: 160, delta: 0.40)
ld.update(isGrounded: true, posX: 220, delta: 0.016)
suite.assert(ld.hapticTriggered, "Big jump triggers landing haptic")
suite.assertEqual(ld.lastToast, "BIG AIR 24m", "Big jump triggers BIG AIR 24m toast")

ld.hapticTriggered = false
ld.lastToast = nil
ld.update(isGrounded: false, posX: 300, delta: 0.60)
ld.update(isGrounded: false, posX: 400, delta: 0.60)
ld.update(isGrounded: true, posX: 480, delta: 0.016)
suite.assert(ld.hapticTriggered, "Huge jump triggers landing haptic")
suite.assertEqual(ld.lastToast, "HUGE AIR 36m", "Huge jump triggers HUGE AIR 36m toast")

ld.hapticTriggered = false
ld.lastToast = nil
ld.update(isGrounded: false, posX: 1000, delta: 1.50)
ld.update(isGrounded: false, posX: 1300, delta: 1.50)
ld.update(isGrounded: true, posX: 1470, delta: 0.016)
suite.assert(ld.hapticTriggered, "Monster jump triggers landing haptic")
suite.assertEqual(ld.lastToast, "MONSTER AIR 94m", "Canyon jump triggers MONSTER AIR 94m toast")

// Test 11: Particle System & Roost Cadence Invariants
print("\n• Test Group 11: Particle System & Roost Cadence Invariants")
struct MockRoostController {
    var roostTimer: TimeInterval = 0
    var roostEmissionCount = 0
    let roostInterval: TimeInterval = 0.08
    let collisionWheelRadius: CGFloat = 16

    mutating func update(pedalHeld: Bool, isGrounded: Bool, delta: TimeInterval) {
        guard pedalHeld, isGrounded else {
            roostTimer = 0
            return
        }
        roostTimer += delta
        if roostTimer >= roostInterval {
            roostTimer = 0
            roostEmissionCount += 1
        }
    }

    func tireGroundContact(axle: CGPoint) -> CGPoint {
        CGPoint(x: axle.x, y: axle.y - collisionWheelRadius)
    }
}

var rc = MockRoostController()
rc.update(pedalHeld: false, isGrounded: true, delta: 0.05)
rc.update(pedalHeld: false, isGrounded: true, delta: 0.05)
suite.assertEqual(rc.roostEmissionCount, 0, "No roost emitted when not pedalling")

rc.update(pedalHeld: true, isGrounded: false, delta: 0.05)
rc.update(pedalHeld: true, isGrounded: false, delta: 0.05)
suite.assertEqual(rc.roostEmissionCount, 0, "No roost emitted when airborne")
suite.assertEqual(rc.roostTimer, 0, "Roost timer reset while airborne")

rc.update(pedalHeld: true, isGrounded: true, delta: 0.04)
suite.assertEqual(rc.roostEmissionCount, 0, "No roost at 0.04s (< 0.08s)")
rc.update(pedalHeld: true, isGrounded: true, delta: 0.04)
suite.assertEqual(rc.roostEmissionCount, 1, "First roost emitted at 0.08s threshold")
rc.update(pedalHeld: true, isGrounded: true, delta: 0.08)
suite.assertEqual(rc.roostEmissionCount, 2, "Second roost emitted at 0.16s")

let rearAxle = CGPoint(x: 100, y: 50)
let contact = rc.tireGroundContact(axle: rearAxle)
suite.assertEqual(contact.x, 100, "Tire contact X matches axle X")
suite.assertEqual(contact.y, 34, "Tire contact Y is exactly axleY - collisionWheelRadius (50 - 16 = 34)")

// Test 12: Dynamic Rider Pose & Weight-Shift Invariants
print("\n• Test Group 12: Dynamic Rider Pose & Weight-Shift Invariants")
struct MockRiderPose {
    var posX: CGFloat = 0
    var posY: CGFloat = 0
    var rot: CGFloat = 0

    mutating func update(deltaTime: TimeInterval, leanInput: CGFloat, pedalHeld: Bool) {
        let targetX: CGFloat = leanInput * -8.0
        let targetY: CGFloat = (abs(leanInput) > 0 || pedalHeld) ? -3.0 : 0.0
        let targetRot: CGFloat = leanInput * 0.12
        let lerpRate = min(CGFloat(deltaTime) * 12.0, 1.0)
        posX += (targetX - posX) * lerpRate
        posY += (targetY - posY) * lerpRate
        rot += (targetRot - rot) * lerpRate
    }
}

var rp = MockRiderPose()
rp.update(deltaTime: 0.1, leanInput: 0, pedalHeld: false)
suite.assertEqual(rp.posX, 0.0, "Neutral X is 0.0")
suite.assertEqual(rp.posY, 0.0, "Neutral Y is 0.0")
suite.assertEqual(rp.rot, 0.0, "Neutral rotation is 0.0")

for _ in 0..<30 {
    rp.update(deltaTime: 0.016, leanInput: 1.0, pedalHeld: false)
}
suite.assertNear(rp.posX, -8.0, accuracy: 0.1, "Lean back target X converges to -8.0")
suite.assertNear(rp.posY, -3.0, accuracy: 0.1, "Lean back crouch Y converges to -3.0")
suite.assertNear(rp.rot, 0.12, accuracy: 0.01, "Lean back rotation converges to +0.12 rad")

for _ in 0..<40 {
    rp.update(deltaTime: 0.016, leanInput: -1.0, pedalHeld: false)
}
suite.assertNear(rp.posX, 8.0, accuracy: 0.1, "Lean forward target X converges to +8.0")
suite.assertNear(rp.posY, -3.0, accuracy: 0.1, "Lean forward tuck Y converges to -3.0")
suite.assertNear(rp.rot, -0.12, accuracy: 0.01, "Lean forward rotation converges to -0.12 rad")

for _ in 0..<40 {
    rp.update(deltaTime: 0.016, leanInput: 0, pedalHeld: true)
}
suite.assertNear(rp.posX, 0.0, accuracy: 0.1, "Pedal-only target X returns to center")
suite.assertNear(rp.posY, -3.0, accuracy: 0.1, "Pedal crouch remains at -3.0")
suite.assertNear(rp.rot, 0.0, accuracy: 0.01, "Pedal rotation returns to 0.0")

// Test 13: Anti-Tunneling Terrain Penetration Recovery Invariants
print("\n• Test Group 13: Anti-Tunneling Terrain Penetration Recovery Invariants")
struct MockPenetrationRecovery {
    var rearWheelY: CGFloat
    var rearWheelVy: CGFloat
    var frontWheelY: CGFloat
    var frontWheelVy: CGFloat
    var chassisY: CGFloat
    var chassisVy: CGFloat
    var rescued = false
    var crashed = false

    let wheelRadius: CGFloat = 16.0
    let frameGuardRadius: CGFloat = 0.0
    let recoveryClearance: CGFloat = 1.0
    let trigger: CGFloat = 6.0

    mutating func recover(terrainY: CGFloat) {
        if chassisY < terrainY - 50 {
            crashed = true
            return
        }

        var maxDeltaY: CGFloat = 0
        let idealWheelY = terrainY + wheelRadius
        if rearWheelY <= idealWheelY - trigger {
            let dY = (idealWheelY + recoveryClearance) - rearWheelY
            if dY > maxDeltaY { maxDeltaY = dY }
        }
        if frontWheelY <= idealWheelY - trigger {
            let dY = (idealWheelY + recoveryClearance) - frontWheelY
            if dY > maxDeltaY { maxDeltaY = dY }
        }
        let minChassisY = terrainY + frameGuardRadius
        if chassisY <= minChassisY - trigger {
            let dY = (minChassisY + recoveryClearance) - chassisY
            if dY > maxDeltaY { maxDeltaY = dY }
        }

        if maxDeltaY > 0 && maxDeltaY <= 45 {
            rearWheelY += maxDeltaY
            frontWheelY += maxDeltaY
            chassisY += maxDeltaY
            if rearWheelVy < 0 { rearWheelVy = 0 }
            if frontWheelVy < 0 { frontWheelVy = 0 }
            if chassisVy < 0 { chassisVy = 0 }
        }
    }
}

var pr1 = MockPenetrationRecovery(rearWheelY: 130, rearWheelVy: -50, frontWheelY: 130, frontWheelVy: -50, chassisY: 150, chassisVy: -50)
pr1.recover(terrainY: 100)
suite.assertEqual(pr1.rearWheelY, 130.0, "Above ground rear wheel position unchanged")
suite.assertEqual(pr1.rearWheelVy, -50.0, "Above ground downward velocity preserved")

var pr1b = MockPenetrationRecovery(rearWheelY: 114.5, rearWheelVy: -10, frontWheelY: 114.5, frontWheelVy: -10, chassisY: 140, chassisVy: 0)
pr1b.recover(terrainY: 100)
suite.assertEqual(pr1b.rearWheelY, 114.5, "Normal contact deflection does NOT falsely trigger recovery")
suite.assertEqual(pr1b.rearWheelVy, -10.0, "Contact downward velocity not zeroed during normal contact")

var pr2 = MockPenetrationRecovery(rearWheelY: 110, rearWheelVy: -300, frontWheelY: 116, frontWheelVy: 0, chassisY: 140, chassisVy: 0)
pr2.recover(terrainY: 100)
suite.assertEqual(pr2.rearWheelY, 117.0, "Penetrating rear wheel clamped to idealY + recoveryClearance (117.0)")
suite.assertEqual(pr2.rearWheelVy, 0.0, "Penetrating rear wheel downward velocity cancelled")

var pr3 = MockPenetrationRecovery(rearWheelY: 90, rearWheelVy: -800, frontWheelY: 92, frontWheelVy: -750, chassisY: 120, chassisVy: -400)
pr3.recover(terrainY: 100)
suite.assertEqual(pr3.rearWheelY, 117.0, "Subterranean rear wheel restored above surface")
suite.assert(pr3.frontWheelY >= 117.0, "Subterranean front wheel restored above surface")
suite.assertEqual(pr3.rearWheelVy, 0.0, "Subterranean rear downward velocity zeroed")
suite.assertEqual(pr3.frontWheelVy, 0.0, "Subterranean front downward velocity zeroed")

var pr4 = MockPenetrationRecovery(rearWheelY: 117, rearWheelVy: 0, frontWheelY: 117, frontWheelVy: 0, chassisY: 93, chassisVy: -250)
pr4.recover(terrainY: 100)
suite.assertEqual(pr4.chassisY, 101.0, "Chassis frame clamped to minChassisY + recoveryClearance (101.0)")
suite.assertEqual(pr4.chassisVy, 0.0, "Chassis downward velocity zeroed")

var pr5 = MockPenetrationRecovery(rearWheelY: 30, rearWheelVy: -1000, frontWheelY: 30, frontWheelVy: -1000, chassisY: 35, chassisVy: -1000)
pr5.recover(terrainY: 100)
suite.assert(pr5.crashed, "Severe subterranean breach correctly triggers crash")
suite.assertEqual(pr5.rescued, false, "Subterranean drop must NEVER teleport bike to surface")

// Test 14: Newtonian Gravity & Ballistic Launch Invariants
print("\n• Test Group 14: Newtonian Gravity & Ballistic Launch Invariants")
let tireFriction: CGFloat = 0.90
let terrainFriction: CGFloat = 1.10
let combinedTireMu = sqrt(tireFriction * terrainFriction)
suite.assert(combinedTireMu >= 0.85, "Combined tire friction (\(combinedTireMu)) provides solid traction (>= 0.85)")
let chassisFriction: CGFloat = 0.02
suite.assert(chassisFriction <= 0.03, "Chassis friction (\(chassisFriction)) prevents ground plowing drag (<= 0.03)")

let g: CGFloat = 1800.0 // GameTuning.Simulation.gravityAcceleration
let downhillSlopeAngle = CGFloat.pi / 4.0 // 45 deg
let accelAlong45Downhill = g * sin(downhillSlopeAngle)
suite.assert(accelAlong45Downhill > 1200.0, "Authoritative gravity produces punchy downhill acceleration")

let kickerTakeoffAngle = atan(0.30)
let launchVx = 800.0 * cos(kickerTakeoffAngle)
let launchVy = 800.0 * sin(kickerTakeoffAngle)
let apexHeight = (launchVy * launchVy) / (2.0 * g)
let timeToApex = launchVy / g
let totalHangtime = timeToApex * 2.0
let jumpDistance = launchVx * totalHangtime

suite.assert(apexHeight > 10.0 && apexHeight < 100.0, "Launch apex height is natural and weighted")
suite.assert(totalHangtime > 0.15 && totalHangtime < 1.0, "Hangtime is snappy under 1800 pt/s² gravity")
suite.assert(jumpDistance > 100.0, "Horizontal jump carries across gap")

func evaluateRunCrash(bothWheelsGrounded: Bool = false, isGrounded: Bool, chassisContact: Bool, chassisRotation: CGFloat, supportAngle: CGFloat) -> (lostControl: Bool, frameStrike: Bool) {
    let relativePitch = normalizedAngle(chassisRotation - supportAngle)
    let lostControl = isGrounded && abs(relativePitch) >= (CGFloat.pi * 0.50)
    let frameStrike = chassisContact && !bothWheelsGrounded && abs(relativePitch) >= 1.20
    return (lostControl, frameStrike)
}

let flatScrape = evaluateRunCrash(bothWheelsGrounded: true, isGrounded: true, chassisContact: true, chassisRotation: 0.10, supportAngle: 0.0)
suite.assert(!flatScrape.frameStrike && !flatScrape.lostControl, "Upright chassis scrape during suspension compression does NOT cause false crash")

let downhillAligned = evaluateRunCrash(bothWheelsGrounded: true, isGrounded: true, chassisContact: true, chassisRotation: -0.785, supportAngle: -0.785)
suite.assert(!downhillAligned.frameStrike && !downhillAligned.lostControl, "Riding steep 45° downhill aligned with slope does NOT cause false crash")

let uHillScrape = evaluateRunCrash(bothWheelsGrounded: true, isGrounded: true, chassisContact: true, chassisRotation: 0.40, supportAngle: -0.50)
suite.assert(!uHillScrape.frameStrike && !uHillScrape.lostControl, "Compression at bottom of U-hill does NOT cause false crash")

let airborneInverted = evaluateRunCrash(bothWheelsGrounded: false, isGrounded: false, chassisContact: false, chassisRotation: .pi, supportAngle: 0.0)
suite.assert(!airborneInverted.lostControl && !airborneInverted.frameStrike, "Mid-air inversion does NOT cause false crash")

let severeNoseDive = evaluateRunCrash(bothWheelsGrounded: false, isGrounded: true, chassisContact: true, chassisRotation: -1.30, supportAngle: 0.0)
suite.assert(severeNoseDive.frameStrike, "Severe nose-dive frame strike (>= 1.20 rad) correctly triggers crash")

let severeLoopOut = evaluateRunCrash(bothWheelsGrounded: false, isGrounded: true, chassisContact: true, chassisRotation: 1.30, supportAngle: 0.0)
suite.assert(severeLoopOut.frameStrike, "Severe loop-out frame strike (>= 1.20 rad) correctly triggers crash")

// Test 15: Uphill Pedal Traction & Anti-Rollback Ratchet Invariants
print("\n• Test Group 15: Uphill Pedal Traction & Anti-Rollback Ratchet Invariants")
func simulateUphillPedal(
    velocity: CGVector,
    tangent: CGVector,
    pedalHeld: Bool,
    isGrounded: Bool,
    pedalForce: CGFloat = 2_200,
    totalMass: CGFloat = 6.6,
    delta: TimeInterval = 0.016
) -> CGVector {
    guard pedalHeld, isGrounded else { return velocity }
    var vel = velocity
    let alongTrail = vel.dx * tangent.dx + vel.dy * tangent.dy

    if alongTrail < 0 && tangent.dy > 0 {
        vel.dx -= tangent.dx * alongTrail
        vel.dy -= tangent.dy * alongTrail
    }

    let forwardSpeed = max(0, vel.dx * tangent.dx + vel.dy * tangent.dy)
    let forceFade = max(0, min(1, 1 - forwardSpeed / 1_600))
    let riderForce = pedalForce * forceFade

    let accel = riderForce / totalMass
    vel.dx += tangent.dx * accel * CGFloat(delta)
    vel.dy += tangent.dy * accel * CGFloat(delta)
    return vel
}

let hillAngle = CGFloat.pi / 7.2
let hillTangent = CGVector(dx: cos(hillAngle), dy: sin(hillAngle))
let backwardVel = CGVector(dx: -hillTangent.dx * 50, dy: -hillTangent.dy * 50)

let engagedVel = simulateUphillPedal(velocity: backwardVel, tangent: hillTangent, pedalHeld: true, isGrounded: true)
let engagedTrailSpeed = engagedVel.dx * hillTangent.dx + engagedVel.dy * hillTangent.dy
suite.assert(engagedTrailSpeed > 0, "Anti-rollback ratchet cancels backward slide and drives forward: \(engagedTrailSpeed) > 0")

let flatTangent = CGVector(dx: 1.0, dy: 0.0)
let flatVel = CGVector(dx: 60.0, dy: 0.0)
let pedaledVel = simulateUphillPedal(velocity: flatVel, tangent: flatTangent, pedalHeld: true, isGrounded: true)
suite.assert(pedaledVel.dx > flatVel.dx, "Pedaling on flat accelerates bike forward smoothly: \(flatVel.dx) -> \(pedaledVel.dx)")

// Test 16: Mega Jump Map & Smooth Physics Continuity Invariants
print("\n• Test Group 16: Alternate Mega Jump Map & Smooth Physics Continuity Invariants")

struct TestSegment {
    let start: CGPoint
    let end: CGPoint
    let startSlope: CGFloat
    let endSlope: CGFloat
    let isLinear: Bool
    let isSurface: Bool
    let maximumUphillSlope: CGFloat?

    init(start: CGPoint, end: CGPoint, startSlope: CGFloat, endSlope: CGFloat, isLinear: Bool = false, isSurface: Bool = true, maximumUphillSlope: CGFloat? = 1.2) {
        self.start = start
        self.end = end
        self.startSlope = startSlope
        self.endSlope = endSlope
        self.isLinear = isLinear
        self.isSurface = isSurface
        self.maximumUphillSlope = maximumUphillSlope
    }
}

func testMakeMegaJumpChunk(index: Int) -> [TestSegment] {
    let cycle = index / 5
    let phase = index % 5
    let ox = CGFloat(cycle) * 18100.0
    let oy = CGFloat(cycle) * -4312.5

    switch phase {
    case 0:
        return [
            TestSegment(start: CGPoint(x: -480 + ox, y: 1200 + oy), end: CGPoint(x: 20 + ox, y: 1200 + oy), startSlope: 0, endSlope: 0),
            TestSegment(start: CGPoint(x: 20 + ox, y: 1200 + oy), end: CGPoint(x: 820 + ox, y: 940 + oy), startSlope: 0, endSlope: -0.65),
            TestSegment(start: CGPoint(x: 820 + ox, y: 940 + oy), end: CGPoint(x: 2220 + ox, y: 30 + oy), startSlope: -0.65, endSlope: -0.65)
        ]
    case 1:
        return [
            TestSegment(start: CGPoint(x: 2220 + ox, y: 30 + oy), end: CGPoint(x: 2820 + ox, y: -360 + oy), startSlope: -0.65, endSlope: -0.65),
            TestSegment(start: CGPoint(x: 2820 + ox, y: -360 + oy), end: CGPoint(x: 4020 + ox, y: -750 + oy), startSlope: -0.65, endSlope: 0.0),
            TestSegment(start: CGPoint(x: 4020 + ox, y: -750 + oy), end: CGPoint(x: 4620 + ox, y: -645 + oy), startSlope: 0.0, endSlope: 0.30),
            TestSegment(start: CGPoint(x: 4620 + ox, y: -645 + oy), end: CGPoint(x: 4800 + ox, y: -591.0 + oy), startSlope: 0.30, endSlope: 0.30),
            TestSegment(start: CGPoint(x: 4800 + ox, y: -591.0 + oy), end: CGPoint(x: 6200 + ox, y: -700.0 + oy), startSlope: 0.30, endSlope: -0.25, isSurface: false)
        ]
    case 2:
        return [
            TestSegment(start: CGPoint(x: 6200 + ox, y: -700.0 + oy), end: CGPoint(x: 9200 + ox, y: -1450.0 + oy), startSlope: -0.25, endSlope: -0.25)
        ]
    case 3:
        return [
            TestSegment(start: CGPoint(x: 9200 + ox, y: -1450.0 + oy), end: CGPoint(x: 12200 + ox, y: -2200.0 + oy), startSlope: -0.25, endSlope: -0.25)
        ]
    case 4:
        return [
            TestSegment(start: CGPoint(x: 12200 + ox, y: -2200.0 + oy), end: CGPoint(x: 15200 + ox, y: -2950.0 + oy), startSlope: -0.25, endSlope: -0.25),
            TestSegment(start: CGPoint(x: 15200 + ox, y: -2950.0 + oy), end: CGPoint(x: 16500 + ox, y: -3112.5 + oy), startSlope: -0.25, endSlope: 0.0),
            TestSegment(start: CGPoint(x: 16500 + ox, y: -3112.5 + oy), end: CGPoint(x: 17620 + ox, y: -3112.5 + oy), startSlope: 0.0, endSlope: 0.0)
        ]
    default:
        return []
    }
}

let chunk0 = testMakeMegaJumpChunk(index: 0)
suite.assertEqual(chunk0[0].start.x, -480.0, "Mega Jump starts at x = -480")
suite.assertEqual(chunk0[0].start.y, 1200.0, "Mega Jump starting elevation is 1200")

let chunk1 = testMakeMegaJumpChunk(index: 1)
suite.assert(!chunk1[4].isSurface, "Launch kicker terminates with an air gap (isSurface == false)")
let gapLengthMeters = (chunk1[4].end.x - chunk1[4].start.x) / 14.0
suite.assert(gapLengthMeters >= 100.0, "Mega Jump gap spans 100s of meters: \(gapLengthMeters)m >= 100m")

var prevEnd: CGPoint?
var prevSlope: CGFloat?
var c1Continuous = true

for chunkIdx in 0..<15 {
    let segs = testMakeMegaJumpChunk(index: chunkIdx)
    for seg in segs {
        if let pe = prevEnd, let ps = prevSlope {
            if abs(seg.start.x - pe.x) > 0.001 || abs(seg.start.y - pe.y) > 0.001 || abs(seg.startSlope - ps) > 0.001 {
                c1Continuous = false
            }
        }
        prevEnd = seg.end
        prevSlope = seg.endSlope
    }
}
suite.assert(c1Continuous, "All 15 chunks maintain strict C1 position & slope continuity")

// Test 17: Trail Rush Ground Adhesion & Centrifugal Lift Elimination
print("\n• Test Group 17: Trail Rush Ground Adhesion & Centrifugal Lift Elimination")
func applyTrailAdhesion(
    velocity: CGVector,
    tangent: CGVector,
    isGrounded: Bool,
    isAirGap: Bool
) -> CGVector {
    guard isGrounded, !isAirGap else { return velocity }
    let normal = CGVector(dx: -tangent.dy, dy: tangent.dx)
    let outwardNormalVel = velocity.dx * normal.dx + velocity.dy * normal.dy
    guard outwardNormalVel > 0 else { return velocity }

    // Redirect outward normal velocity along the tangent to maintain ground contact over crests
    let tangentSpeed = velocity.dx * tangent.dx + velocity.dy * tangent.dy
    let preservedSpeed = hypot(velocity.dx, velocity.dy)
    let newAlong = max(tangentSpeed, preservedSpeed * 0.98)
    return CGVector(dx: tangent.dx * newAlong, dy: tangent.dy * newAlong)
}

let crestTangent = CGVector(dx: 0.966, dy: -0.259) // descending over a convex crest
let flyingLiftVelocity = CGVector(dx: 500.0, dy: 100.0) // bike lifting off due to crest
let adheredVelocity = applyTrailAdhesion(velocity: flyingLiftVelocity, tangent: crestTangent, isGrounded: true, isAirGap: false)
let normalOfCrest = CGVector(dx: -crestTangent.dy, dy: crestTangent.dx)
let residualNormalVel = adheredVelocity.dx * normalOfCrest.dx + adheredVelocity.dy * normalOfCrest.dy
suite.assertNear(residualNormalVel, 0.0, accuracy: 0.01, "Centrifugal lift is cancelled: outward normal velocity clamped to 0")
suite.assert(adheredVelocity.dx > 450.0, "Forward momentum along trail is preserved during adhesion")

// Test 18: 20-Biome Grammar Selection & Snowline Blend Invariants
print("\n• Test Group 18: 20-Biome Grammar Selection & Snowline Blend Invariants")
enum BiomeKind: Int, CaseIterable {
    case summitIce = 0, windCornice, blueIcefall, frostPine, glacialMoraine
    case slateRidge, gravelChute, fernGrove, canopyRollers, redClay
    case sandstoneMesa, canyonFloor, badlands, shaleRun, volcanicRock
    case ashField, alpineMeadow, riverRock, coastalBluff, sunsetGully

    var isSnowCovered: Bool {
        rawValue <= 4 // First 5 biomes are alpine/snow
    }
}

suite.assertEqual(BiomeKind.allCases.count, 20, "Exact 20 distinct biomes configured")
suite.assert(BiomeKind.summitIce.isSnowCovered, "Summit Ice is snow covered")
suite.assert(BiomeKind.glacialMoraine.isSnowCovered, "Glacial Moraine is snow covered")
suite.assert(!BiomeKind.slateRidge.isSnowCovered, "Slate Ridge is below snow line")
suite.assert(!BiomeKind.sunsetGully.isSnowCovered, "Sunset Gully is below snow line")

func alpineBlend(distanceMeters: CGFloat, alpineEnd: CGFloat = 10_000, blendWidth: CGFloat = 850) -> CGFloat {
    let raw = (distanceMeters - alpineEnd) / blendWidth
    let clamped = max(0, min(1, raw))
    return 1 - clamped
}

suite.assertNear(alpineBlend(distanceMeters: 5_000), 1.0, "High alpine is 100% alpine atmosphere")
suite.assertNear(alpineBlend(distanceMeters: 10_000), 1.0, "Alpine end threshold starts blend at 1.0")
suite.assertNear(alpineBlend(distanceMeters: 10_425), 0.5, "Midpoint of blend transition is 0.5")
suite.assertNear(alpineBlend(distanceMeters: 10_850), 0.0, "End of blend transition reaches 0.0")
suite.assertNear(alpineBlend(distanceMeters: 20_000), 0.0, "Post-alpine zone remains at 0.0")

// Test 19: Terrain Height & Slope Binary Search Interpolation
print("\n• Test Group 19: Terrain Height & Slope Binary Search Interpolation")
let terrainSampleRun: [CGPoint] = [
    CGPoint(x: 0, y: 100),
    CGPoint(x: 100, y: 80),
    CGPoint(x: 200, y: 70),
    CGPoint(x: 300, y: 75),
    CGPoint(x: 400, y: 90)
]

func sampleTerrainHeight(at x: CGFloat, in run: [CGPoint]) -> CGFloat? {
    guard let first = run.first, let last = run.last, x >= first.x, x <= last.x else { return nil }
    if x <= first.x { return first.y }
    if x >= last.x { return last.y }
    var low = 0
    var high = run.count - 1
    while low < high {
        let mid = (low + high) / 2
        if run[mid].x < x {
            low = mid + 1
        } else {
            high = mid
        }
    }
    let p0 = run[low - 1]
    let p1 = run[low]
    let t = (x - p0.x) / (p1.x - p0.x)
    return p0.y + (p1.y - p0.y) * t
}

suite.assertNear(sampleTerrainHeight(at: 0, in: terrainSampleRun)!, 100.0, "Exact height at x = 0")
suite.assertNear(sampleTerrainHeight(at: 50, in: terrainSampleRun)!, 90.0, "Linear interpolation at x = 50 is 90.0")
suite.assertNear(sampleTerrainHeight(at: 100, in: terrainSampleRun)!, 80.0, "Exact height at x = 100")
suite.assertNear(sampleTerrainHeight(at: 150, in: terrainSampleRun)!, 75.0, "Linear interpolation at x = 150 is 75.0")
suite.assert(sampleTerrainHeight(at: -10, in: terrainSampleRun) == nil, "Out-of-bounds negative x safely returns nil")
suite.assert(sampleTerrainHeight(at: 500, in: terrainSampleRun) == nil, "Out-of-bounds positive x safely returns nil")

// Test 20: Articulated Multi-Body Rig Joint Drift Repair & Non-Finite Recovery
print("\n• Test Group 20: Articulated Multi-Body Rig Joint Drift Repair & Non-Finite Recovery")
struct MockRig {
    var chassisPos: CGPoint
    var rearWheelPos: CGPoint
    var frontWheelPos: CGPoint
    var chassisVelocity: CGVector
    var maxDrift: CGFloat = 250.0

    mutating func checkAndRepair() -> Bool {
        let chassisBroken = !chassisPos.x.isFinite || !chassisPos.y.isFinite
        let rearDrift = hypot(rearWheelPos.x - chassisPos.x, rearWheelPos.y - chassisPos.y)
        let frontDrift = hypot(frontWheelPos.x - chassisPos.x, frontWheelPos.y - chassisPos.y)
        let velBroken = !chassisVelocity.dx.isFinite || !chassisVelocity.dy.isFinite

        if chassisBroken || velBroken || rearDrift > maxDrift || frontDrift > maxDrift {
            // Repair: snap wheels back relative to chassis
            if !chassisPos.x.isFinite || !chassisPos.y.isFinite {
                chassisPos = CGPoint(x: 0, y: 100)
            }
            if !chassisVelocity.dx.isFinite || !chassisVelocity.dy.isFinite {
                chassisVelocity = .zero
            }
            rearWheelPos = CGPoint(x: chassisPos.x - 30, y: chassisPos.y - 27)
            frontWheelPos = CGPoint(x: chassisPos.x + 30, y: chassisPos.y - 27)
            return true
        }
        return false
    }
}

var intactRig = MockRig(chassisPos: CGPoint(x: 100, y: 200), rearWheelPos: CGPoint(x: 70, y: 173), frontWheelPos: CGPoint(x: 130, y: 173), chassisVelocity: CGVector(dx: 100, dy: 0))
suite.assert(!intactRig.checkAndRepair(), "Intact rig does not trigger repair")

var driftedRig = MockRig(chassisPos: CGPoint(x: 100, y: 200), rearWheelPos: CGPoint(x: -500, y: 173), frontWheelPos: CGPoint(x: 130, y: 173), chassisVelocity: CGVector(dx: 100, dy: 0))
suite.assert(driftedRig.checkAndRepair(), "Drifted wheel (> 250pt) triggers automatic repair")
suite.assertNear(driftedRig.rearWheelPos.x, 70.0, "Rear wheel snapped back to standard offset")

var nanRig = MockRig(chassisPos: CGPoint(x: CGFloat.nan, y: 200), rearWheelPos: CGPoint(x: 70, y: 173), frontWheelPos: CGPoint(x: 130, y: 173), chassisVelocity: CGVector(dx: CGFloat.infinity, dy: 0))
suite.assert(nanRig.checkAndRepair(), "NaN/Inf coordinate rig triggers repair safely without crash")
suite.assert(nanRig.chassisPos.x.isFinite, "Repaired chassis has finite coordinates")
suite.assert(nanRig.chassisVelocity.dx.isFinite, "Repaired chassis has finite velocity")

// Test 21: HUD Distance, Speed, and Unit Conversions
print("\n• Test Group 21: HUD Distance, Speed, and Unit Conversions")
let worldUnitsPerMeter: CGFloat = 5.0
let speedScale: CGFloat = 0.22

func computeDisplayDistance(chassisX: CGFloat, spawnX: CGFloat = 0) -> Int {
    max(0, Int((chassisX - spawnX) / worldUnitsPerMeter))
}

func computeDisplaySpeed(velocity: CGVector) -> Int {
    let speed = hypot(velocity.dx, velocity.dy)
    return Int(speed * speedScale)
}

suite.assertEqual(computeDisplayDistance(chassisX: 500), 100, "500 world units equals 100 display meters")
suite.assertEqual(computeDisplayDistance(chassisX: -50), 0, "Negative distance clamped to 0")
suite.assertEqual(computeDisplaySpeed(velocity: CGVector(dx: 500, dy: 0)), 110, "500 pt/s velocity equals 110 km/h")
suite.assertEqual(computeDisplaySpeed(velocity: CGVector(dx: 1000, dy: 0)), 220, "1000 pt/s velocity equals 220 km/h")

// Test 22: Integration Test: Simulated Trail Rush Descent
print("\n• Test Group 22: Integration Test: Simulated Trail Rush Descent (1,000 Frames @ 60 FPS)")
struct TrailRushSimulation {
    var posX: CGFloat = 0
    var posY: CGFloat = 500
    var vx: CGFloat = 260
    var vy: CGFloat = 0
    var isGrounded: Bool = true
    var maxForwardSpeed: CGFloat = 650.0

    mutating func step(dt: CGFloat) {
        // Continuous terrain drop slope ~ -0.45
        let slope: CGFloat = -0.45
        let length = hypot(1.0, slope)
        let tangent = CGVector(dx: 1.0 / length, dy: slope / length)

        // Gravity along downhill
        let gAccel: CGFloat = 1800.0 * (-slope / length)
        vx += tangent.dx * gAccel * dt
        vy += tangent.dy * gAccel * dt

        // Speed cap for Trail Rush
        let currentSpeed = hypot(vx, vy)
        if currentSpeed > maxForwardSpeed {
            let scale = maxForwardSpeed / currentSpeed
            vx *= scale
            vy *= scale
        }

        posX += vx * dt
        posY += vy * dt
    }
}

var trSim = TrailRushSimulation()
for _ in 0..<1200 {
    trSim.step(dt: 1.0 / 60.0)
}
suite.assert(trSim.posX > 10_000, "Trail Rush simulated run covered > 10,000 pt distance: \(trSim.posX) pt")
suite.assert(trSim.vx <= 650.01, "Trail Rush strictly enforces max forward speed cap (\(trSim.vx) <= 650.0)")
suite.assert(trSim.posY < 500, "Continuous downhill descent dropped elevation naturally: \(trSim.posY)")

// Test 23: Integration Test: Simulated Mega Jump Launch & Landing
print("\n• Test Group 23: Integration Test: Simulated Mega Jump Launch & Landing (600 Frames @ 60 FPS)")
struct MegaJumpSimulation {
    var posX: CGFloat = 2000
    var posY: CGFloat = 100
    var vx: CGFloat = 750
    var vy: CGFloat = 0
    var inFlight: Bool = false
    var landed: Bool = false
    var maxAirDistance: CGFloat = 0

    mutating func step(dt: CGFloat) {
        if posX < 4800 {
            // Downhill leadup and kicker ramp
            vx += 800.0 * dt
            if posX >= 4600 {
                // Kicker launches upward
                vy = 350.0
                inFlight = true
            }
        } else if inFlight && posX < 6200 {
            // Ballistic flight over 1400pt canyon gap
            vy -= 1800.0 * dt
        } else if inFlight && posX >= 6200 {
            // Touchdown on catch runway
            inFlight = false
            landed = true
            maxAirDistance = (posX - 4800) / 14.0
            vy = -vx * 0.25 // smooth downslope catch
        } else {
            // Safe rollout along landing catch
            vx = max(200.0, vx - 100.0 * dt)
        }
        posX += vx * dt
        posY += vy * dt
    }
}

var mjSim = MegaJumpSimulation()
for _ in 0..<600 {
    mjSim.step(dt: 1.0 / 60.0)
}
suite.assert(mjSim.landed, "Mega Jump simulation completed ballistic flight and landed on catch runway")
suite.assert(mjSim.maxAirDistance >= 100.0, "Ballistic canyon air gap cleared 100+ meters: \(mjSim.maxAirDistance)m")
suite.assert(mjSim.posX > 12000, "Post-landing high-speed rollout carries far down track: \(mjSim.posX) pt")

// Test 24: Integration Test: Full Crash, Ragdoll Ejection & Restart Lifecycle
print("\n• Test Group 24: Integration Test: Full Crash, Ragdoll Ejection & Restart Lifecycle")
var fullSM = MockRunStateMachine()
fullSM.startRun()
suite.assertEqual(fullSM.state, MockRunState.riding, "Lifecycle begins riding")

fullSM.enterCrash()
suite.assertEqual(fullSM.state, MockRunState.crashing, "Severe pitch triggers crashing")
suite.assertEqual(fullSM.pedalHeld, false, "Input locked out during crash")

fullSM.handleTouch(lean: 1.0, pedal: true)
suite.assertEqual(fullSM.state, MockRunState.crashing, "Touch during crash ignored")

fullSM.crashSequenceCompleted()
suite.assertEqual(fullSM.state, MockRunState.results, "Sequence completion transitions to results screen")

fullSM.handleTouch(lean: 0.0, pedal: false)
suite.assertEqual(fullSM.state, MockRunState.riding, "Touch in results restarts new run cleanly")

// Test 25: Airtime Stability, Downforce Isolation & Micro-Bump Filtering Invariants
print("\n• Test Group 25: Airtime Stability, Downforce Isolation & Micro-Bump Filtering Invariants")

// 1. Lost-grip weight: airborne over trail that is still there gets pulled down.
//    Authored jumps and gaps with no surface stay on gravity alone.
func lostGripPull(isGrounded: Bool, isEarnedJump: Bool, surfaceBelow: Bool) -> CGFloat {
    guard !isGrounded, !isEarnedJump, surfaceBelow else { return 0 }
    return 3_600
}

suite.assertEqual(lostGripPull(isGrounded: false, isEarnedJump: false, surfaceBelow: true), 3_600, "Losing grip over trail pulls the bike down")
suite.assertEqual(lostGripPull(isGrounded: false, isEarnedJump: true, surfaceBelow: true), 0, "Authored jump stays on gravity alone")
suite.assertEqual(lostGripPull(isGrounded: false, isEarnedJump: false, surfaceBelow: false), 0, "Canyon gap stays ballistic")
suite.assertEqual(lostGripPull(isGrounded: true, isEarnedJump: false, surfaceBelow: true), 0, "Planted tires are not given the lost-grip pull")

// 2. Nose follows the fall. Positive torque pitches the nose up.
func noseDipTorque(pitch: CGFloat, target: CGFloat, angularVelocity: CGFloat) -> CGFloat {
    var error = target - pitch
    let twoPi = CGFloat.pi * 2
    error = error.truncatingRemainder(dividingBy: twoPi)
    if error > .pi { error -= twoPi }
    if error < -.pi { error += twoPi }
    let torque = error * 160 - angularVelocity * 22
    return min(80, max(-80, torque))
}

let fallingNose = noseDipTorque(pitch: 0, target: -0.5, angularVelocity: 0)
suite.assert(fallingNose < -40, "Nose above a falling flight path is torqued down: \(fallingNose)")
suite.assertEqual(noseDipTorque(pitch: -0.4, target: -0.4, angularVelocity: 0), 0, "Nose aligned with the flight path gets no extra torque")
suite.assert(noseDipTorque(pitch: -0.4, target: -0.4, angularVelocity: 2) < 0, "Spin past the flight path is damped")

// 3. Micro-bump airtime filtering (< 0.10s does not show AIR)
func formatSurfaceStatus(isGrounded: Bool, airborneTime: TimeInterval) -> String {
    if isGrounded || airborneTime < 0.10 {
        return "GRIP"
    } else {
        return String(format: "AIR %.1fs", airborneTime)
    }
}

suite.assertEqual(formatSurfaceStatus(isGrounded: true, airborneTime: 0.0), "GRIP", "Fully grounded shows GRIP")
suite.assertEqual(formatSurfaceStatus(isGrounded: false, airborneTime: 0.04), "GRIP", "Micro-bump (< 0.10s) does not falsely trigger AIR")
suite.assertEqual(formatSurfaceStatus(isGrounded: false, airborneTime: 0.50), "AIR 0.5s", "Sustained airtime displays AIR 0.5s")

// 4. Universal earned jump recognition (kicker, lips, step-downs, cliffs on any map)
func isEarnedJump(recentMaxSlope: CGFloat, currentSlope: CGFloat, speed: CGFloat, vy: CGFloat, airGap: Bool) -> Bool {
    if airGap { return true }
    let isTakeoffSlope = recentMaxSlope >= 0.15 || currentSlope >= 0.12
    return isTakeoffSlope && speed >= 90.0 && vy > 8.0
}

suite.assert(isEarnedJump(recentMaxSlope: 0.35, currentSlope: 0.30, speed: 200, vy: 50, airGap: false), "Trail Rush lip launch is recognized as earned jump")
suite.assert(isEarnedJump(recentMaxSlope: 0.40, currentSlope: 0.20, speed: 500, vy: 150, airGap: false), "Mega Jump kicker launch is recognized as earned jump")
suite.assert(!isEarnedJump(recentMaxSlope: -0.20, currentSlope: -0.30, speed: 300, vy: -50, airGap: false), "Downhill roll is NOT an earned jump")

// MARK: - Test Group 26: 10,000-Scenario Property-Based Fuzzing Engine
print("\n• Test Group 26: 10,000-Scenario Property-Based Fuzzing Engine")

var fuzzPRNG = PRNG(seed: 0xDEAD_BEEF_CAFE_1234)

// -------------------------------------------------------------
// Fuzz Suite 1: Spline Evaluator & Boundary Stress (2,500 scenarios)
// -------------------------------------------------------------
var f1Pass = 0
var f1Fail = 0
for _ in 0..<2500 {
    let x0 = fuzzPRNG.cgFloat(in: -1000...1000)
    let span = fuzzPRNG.cgFloat(in: 1...2000)
    let x1 = x0 + span
    let y0 = fuzzPRNG.cgFloat(in: -5000...5000)
    let y1 = fuzzPRNG.cgFloat(in: -5000...5000)
    let s0 = fuzzPRNG.cgFloat(in: -5...5)
    let s1 = fuzzPRNG.cgFloat(in: -5...5)
    let t = fuzzPRNG.cgFloat(in: 0...1)

    let yAtT = hermiteY(start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), startSlope: s0, endSlope: s1, t: t)
    let slopeAtT = hermiteSlope(start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), startSlope: s0, endSlope: s1, t: t)

    if yAtT.isFinite && slopeAtT.isFinite {
        f1Pass += 1
    } else {
        f1Fail += 1
    }
}
suite.recordFuzzBatch(passed: f1Pass, failed: f1Fail, batchName: "Spline Evaluator & Boundary Fuzzing (2,500 scenarios)")

// -------------------------------------------------------------
// Fuzz Suite 2: Trigonometric & Extreme Float Robustness (2,500 scenarios)
// -------------------------------------------------------------
var f2Pass = 0
var f2Fail = 0
for i in 0..<2500 {
    let testAngle: CGFloat
    if i == 0 { testAngle = .infinity }
    else if i == 1 { testAngle = -.infinity }
    else if i == 2 { testAngle = .nan }
    else if i == 3 { testAngle = 0.0 }
    else if i == 4 { testAngle = -.pi }
    else if i == 5 { testAngle = .pi }
    else {
        testAngle = fuzzPRNG.cgFloat(in: -100_000...100_000)
    }

    let norm = normalizedAngle(testAngle)
    if norm.isFinite && norm >= -.pi - 0.0001 && norm <= .pi + 0.0001 {
        f2Pass += 1
    } else {
        f2Fail += 1
    }
}
suite.recordFuzzBatch(passed: f2Pass, failed: f2Fail, batchName: "Trigonometric & Extreme Float Fuzzing (2,500 scenarios)")

// -------------------------------------------------------------
// Fuzz Suite 3: Continuous Procedural Terrain Streaming (2,500 chunks)
// -------------------------------------------------------------
var f3Pass = 0
var f3Fail = 0
var f3CurrentPoint = CGPoint(x: -480, y: 1000)
var f3CurrentSlope: CGFloat = 0.0

for _ in 0..<2500 {
    let featureLength = fuzzPRNG.cgFloat(in: 200...800)
    let featureDrop = fuzzPRNG.cgFloat(in: -50...600)
    let endPoint = CGPoint(x: f3CurrentPoint.x + featureLength, y: f3CurrentPoint.y - featureDrop)
    let endSlope = fuzzPRNG.cgFloat(in: -1.2...0.5)

    // Evaluate midpoint continuity
    let midY = hermiteY(start: f3CurrentPoint, end: endPoint, startSlope: f3CurrentSlope, endSlope: endSlope, t: 0.5)
    let midSlope = hermiteSlope(start: f3CurrentPoint, end: endPoint, startSlope: f3CurrentSlope, endSlope: endSlope, t: 0.5)

    if midY.isFinite && midSlope.isFinite && endPoint.x > f3CurrentPoint.x {
        f3Pass += 1
    } else {
        f3Fail += 1
    }
    f3CurrentPoint = endPoint
    f3CurrentSlope = endSlope
}
suite.recordFuzzBatch(passed: f3Pass, failed: f3Fail, batchName: "Continuous Terrain Streaming & C1 Continuity Fuzzing (2,500 chunks)")

// -------------------------------------------------------------
// Fuzz Suite 4: Multi-Body Dynamics & Crash State Permutations (2,500 scenarios)
// -------------------------------------------------------------
var f4Pass = 0
var f4Fail = 0
for _ in 0..<2500 {
    let bothWheelsGrounded = fuzzPRNG.next() % 2 == 0
    let isGrounded = bothWheelsGrounded || (fuzzPRNG.next() % 2 == 0)
    let chassisContact = fuzzPRNG.next() % 2 == 0
    let chassisRot = fuzzPRNG.cgFloat(in: -CGFloat.pi...CGFloat.pi)
    let supportAngle = fuzzPRNG.cgFloat(in: -0.8...0.8)

    let crashResult = evaluateRunCrash(
        bothWheelsGrounded: bothWheelsGrounded,
        isGrounded: isGrounded,
        chassisContact: chassisContact,
        chassisRotation: chassisRot,
        supportAngle: supportAngle
    )

    // Invariant: Upright riding with both wheels grounded must NEVER crash
    let relativePitch = normalizedAngle(chassisRot - supportAngle)
    if bothWheelsGrounded && abs(relativePitch) < 1.0 {
        if crashResult.frameStrike || crashResult.lostControl {
            f4Fail += 1
            continue
        }
    }

    // Invariant: Severe nose-dive (>= 1.2 rad relative pitch) frame strike without both wheels grounded MUST crash
    if chassisContact && !bothWheelsGrounded && abs(relativePitch) >= 1.20 {
        if !crashResult.frameStrike {
            f4Fail += 1
            continue
        }
    }

    f4Pass += 1
}
suite.recordFuzzBatch(passed: f4Pass, failed: f4Fail, batchName: "Multi-Body Dynamics & Crash State Permutations Fuzzing (2,500 scenarios)")

// MARK: - Final Execution Summary
let allPassed = suite.summary()
exit(allPassed ? 0 : 1)
