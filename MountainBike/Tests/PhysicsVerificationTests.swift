import Foundation
import CoreGraphics

// MARK: - Mini Test Framework

struct TestSuite {
    var passed = 0
    var failed = 0
    var total = 0

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

    func summary() -> Bool {
        print("\n==========================================")
        print("TEST RESULTS: \(passed)/\(total) passed (\(failed) failures)")
        print("==========================================")
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

func normalizedAngle(_ angle: CGFloat) -> CGFloat {
    var result = angle
    while result > .pi { result -= .pi * 2 }
    while result < -.pi { result += .pi * 2 }
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

print("🔬 RUNNING MOUNTAIN BIKE PHYSICS & MATH VERIFICATION SUITE...\n")

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

// Test 2: Angle Normalization Bounds
print("\n• Test Group 2: Trigonometric Angle Normalization")
suite.assertNear(normalizedAngle(0), 0, "Zero angle normalizes to zero")
suite.assertNear(normalizedAngle(.pi), .pi, "pi normalizes to pi")
suite.assertNear(normalizedAngle(3 * .pi), .pi, "3*pi normalizes to pi")
suite.assertNear(normalizedAngle(-5 * .pi), -.pi, "-5*pi normalizes to -pi")
suite.assertNear(normalizedAngle(.pi * 0.5), .pi * 0.5, "pi/2 preserves exact quadrant")
suite.assertNear(normalizedAngle(-.pi * 0.5), -.pi * 0.5, "-pi/2 preserves exact quadrant")
suite.assertNear(normalizedAngle(2.5 * .pi), .pi * 0.5, "2.5*pi wraps to pi/2")

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

// 1. Touch while intro drops into riding
sm.handleTouch(lean: 1.0, pedal: true)
suite.assertEqual(sm.state, MockRunState.riding, "Drops in to riding on touch")
suite.assertEqual(sm.pedalHeld, true, "Pedal is held while riding")
suite.assertEqual(sm.leanInput, 1.0, "Lean is active while riding")

// 2. Crash occurs
sm.enterCrash()
suite.assertEqual(sm.state, MockRunState.crashing, "Enters crashing state")
suite.assertEqual(sm.crashSequenceActive, true, "Crash sequence is active")
suite.assertEqual(sm.pedalHeld, false, "Pedal input is zeroed on crash")
suite.assertEqual(sm.leanInput, 0.0, "Lean input is zeroed on crash")

// 3. User attempts touch while crashing (ragdoll in flight)
sm.handleTouch(lean: -1.0, pedal: true)
suite.assertEqual(sm.state, MockRunState.crashing, "Touch during crashing is ignored, stays crashing")
suite.assertEqual(sm.pedalHeld, false, "Pedal input is NOT accepted during crash")
suite.assertEqual(sm.leanInput, 0.0, "Lean input is NOT accepted during crash")

// 4. Sequence timer completes
sm.crashSequenceCompleted()
suite.assertEqual(sm.state, MockRunState.results, "Transitions to results state after sequence completes")

// 5. User taps screen in results state
sm.handleTouch(lean: 0.0, pedal: true)
suite.assertEqual(sm.state, MockRunState.riding, "Tap in results state resets and drops into riding")
suite.assertEqual(sm.pedalHeld, true, "Pedal is registered in new run")

// 6. Explicit restart key 'R' during crash cancels immediately
sm.enterCrash()
suite.assertEqual(sm.state, MockRunState.crashing, "In crash state again")
sm.handleExplicitRestartKey()
suite.assertEqual(sm.state, MockRunState.riding, "Explicit restart bypasses crash delay safely")
suite.assertEqual(sm.crashSequenceActive, false, "Crash sequence action cancelled")

let allPassed = suite.summary()
exit(allPassed ? 0 : 1)
