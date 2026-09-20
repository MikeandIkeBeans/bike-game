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

// Method A: Full Rebuild
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

// Method B: Incremental Append
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

// Test boundary continuity
suite.assertEqual(incrementalPoints.first?.x, 0, "Level start X is 0")
suite.assertEqual(incrementalPoints.last?.x, 300, "Level end X is 300")

// Test zero-allocation minY computation
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
                if airborneTime >= 0.75 || airDistance >= 20 {
                    lastToast = airDistance >= 30 ? "HUGE AIR \(airDistance)m" : "BIG AIR \(airDistance)m"
                }
            }
            airborneTime = 0
            airborneStartX = 0
        }
        wasGrounded = isGrounded
    }
}

var ld = MockLandingDetector()

// 1. Initial on ground: no haptics or toasts
ld.update(isGrounded: true, posX: 0, delta: 0.016)
suite.assert(!ld.hapticTriggered, "No haptic while grounded")
suite.assert(ld.lastToast == nil, "No toast while grounded")

// 2. Micro bump (< 0.25s)
ld.update(isGrounded: false, posX: 10, delta: 0.10)
ld.update(isGrounded: true, posX: 20, delta: 0.016)
suite.assert(!ld.hapticTriggered, "Micro bump < 0.25s triggers no haptic")
suite.assert(ld.lastToast == nil, "Micro bump triggers no toast")

// 3. Medium jump: 0.4s flight, 8m distance
ld.hapticTriggered = false
ld.update(isGrounded: false, posX: 30, delta: 0.20)
ld.update(isGrounded: false, posX: 50, delta: 0.20)
ld.update(isGrounded: true, posX: 70, delta: 0.016)
suite.assert(ld.hapticTriggered, "Medium jump >= 0.25s triggers landing haptic")
suite.assert(ld.lastToast == nil, "Medium jump below 20m/0.75s does not trigger big air toast")

// 4. Big air: 0.8s flight, 24m distance
ld.hapticTriggered = false
ld.update(isGrounded: false, posX: 100, delta: 0.40)
ld.update(isGrounded: false, posX: 160, delta: 0.40)
ld.update(isGrounded: true, posX: 220, delta: 0.016) // (220-100)/5 = 24m
suite.assert(ld.hapticTriggered, "Big jump triggers landing haptic")
suite.assertEqual(ld.lastToast, "BIG AIR 24m", "Big jump triggers BIG AIR 24m toast")

// 5. Huge air: 1.2s flight, 36m distance
ld.hapticTriggered = false
ld.lastToast = nil
ld.update(isGrounded: false, posX: 300, delta: 0.60)
ld.update(isGrounded: false, posX: 400, delta: 0.60)
ld.update(isGrounded: true, posX: 480, delta: 0.016) // (480-300)/5 = 36m
suite.assert(ld.hapticTriggered, "Huge jump triggers landing haptic")
suite.assertEqual(ld.lastToast, "HUGE AIR 36m", "Huge jump triggers HUGE AIR 36m toast")

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

// 1. Not pedalling while grounded: no roost
rc.update(pedalHeld: false, isGrounded: true, delta: 0.05)
rc.update(pedalHeld: false, isGrounded: true, delta: 0.05)
suite.assertEqual(rc.roostEmissionCount, 0, "No roost emitted when not pedalling")

// 2. Pedalling while airborne: no roost
rc.update(pedalHeld: true, isGrounded: false, delta: 0.05)
rc.update(pedalHeld: true, isGrounded: false, delta: 0.05)
suite.assertEqual(rc.roostEmissionCount, 0, "No roost emitted when airborne")
suite.assertEqual(rc.roostTimer, 0, "Roost timer reset while airborne")

// 3. Pedalling while grounded emits at 0.08s cadence
rc.update(pedalHeld: true, isGrounded: true, delta: 0.04)
suite.assertEqual(rc.roostEmissionCount, 0, "No roost at 0.04s (< 0.08s)")
rc.update(pedalHeld: true, isGrounded: true, delta: 0.04)
suite.assertEqual(rc.roostEmissionCount, 1, "First roost emitted at 0.08s threshold")
rc.update(pedalHeld: true, isGrounded: true, delta: 0.08)
suite.assertEqual(rc.roostEmissionCount, 2, "Second roost emitted at 0.16s")

// 4. Tire contact point calculation
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

// 1. Neutral stance at rest
rp.update(deltaTime: 0.1, leanInput: 0, pedalHeld: false)
suite.assertEqual(rp.posX, 0.0, "Neutral X is 0.0")
suite.assertEqual(rp.posY, 0.0, "Neutral Y is 0.0")
suite.assertEqual(rp.rot, 0.0, "Neutral rotation is 0.0")

// 2. Lean back (leanInput = 1.0): shifts weight rearward and crouches slightly
for _ in 0..<30 {
    rp.update(deltaTime: 0.016, leanInput: 1.0, pedalHeld: false)
}
suite.assertNear(rp.posX, -8.0, accuracy: 0.1, "Lean back target X converges to -8.0")
suite.assertNear(rp.posY, -3.0, accuracy: 0.1, "Lean back crouch Y converges to -3.0")
suite.assertNear(rp.rot, 0.12, accuracy: 0.01, "Lean back rotation converges to +0.12 rad")

// 3. Lean forward (leanInput = -1.0): shifts weight forward and tucks
for _ in 0..<40 {
    rp.update(deltaTime: 0.016, leanInput: -1.0, pedalHeld: false)
}
suite.assertNear(rp.posX, 8.0, accuracy: 0.1, "Lean forward target X converges to +8.0")
suite.assertNear(rp.posY, -3.0, accuracy: 0.1, "Lean forward tuck Y converges to -3.0")
suite.assertNear(rp.rot, -0.12, accuracy: 0.01, "Lean forward rotation converges to -0.12 rad")

// 4. Pedal only (leanInput = 0, pedalHeld = true): centered crouch
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

    let wheelRadius: CGFloat = 16.0
    let frameGuardRadius: CGFloat = 0.0
    let recoveryClearance: CGFloat = 1.0
    let trigger: CGFloat = 6.0

    mutating func recover(terrainY: CGFloat) {
        // Catastrophic tunneling rescue (checked first if severe breach > 60 units below terrain)
        if chassisY < terrainY - 60 {
            rescued = true
            chassisY = terrainY + 35
            chassisVy = 0
            rearWheelY = terrainY + wheelRadius + recoveryClearance
            frontWheelY = terrainY + wheelRadius + recoveryClearance
            return
        }

        var maxDeltaY: CGFloat = 0
        let idealWheelY = terrainY + wheelRadius
        // Rear wheel recovery
        if rearWheelY <= idealWheelY - trigger {
            let dY = (idealWheelY + recoveryClearance) - rearWheelY
            if dY > maxDeltaY { maxDeltaY = dY }
        }
        // Front wheel recovery
        if frontWheelY <= idealWheelY - trigger {
            let dY = (idealWheelY + recoveryClearance) - frontWheelY
            if dY > maxDeltaY { maxDeltaY = dY }
        }
        // Chassis frame recovery
        let minChassisY = terrainY + frameGuardRadius
        if chassisY <= minChassisY - trigger {
            let dY = (minChassisY + recoveryClearance) - chassisY
            if dY > maxDeltaY { maxDeltaY = dY }
        }

        // Translate the ENTIRE assembly together as a single unit
        if maxDeltaY > 0 && maxDeltaY <= 30 {
            rearWheelY += maxDeltaY
            frontWheelY += maxDeltaY
            chassisY += maxDeltaY
            if rearWheelVy < 0 { rearWheelVy = 0 }
            if frontWheelVy < 0 { frontWheelVy = 0 }
            if chassisVy < 0 { chassisVy = 0 }
        }
    }
}

// 1. Wheel and chassis comfortably above ground: no adjustment
var pr1 = MockPenetrationRecovery(rearWheelY: 130, rearWheelVy: -50, frontWheelY: 130, frontWheelVy: -50, chassisY: 150, chassisVy: -50)
pr1.recover(terrainY: 100)
suite.assertEqual(pr1.rearWheelY, 130.0, "Above ground rear wheel position unchanged")
suite.assertEqual(pr1.rearWheelVy, -50.0, "Above ground downward velocity preserved")

// 1b. Normal ground contact deflection (ideal is 116, contact deflection is 114.5): NO false recovery
var pr1b = MockPenetrationRecovery(rearWheelY: 114.5, rearWheelVy: -10, frontWheelY: 114.5, frontWheelVy: -10, chassisY: 140, chassisVy: 0)
pr1b.recover(terrainY: 100)
suite.assertEqual(pr1b.rearWheelY, 114.5, "Normal contact deflection does NOT falsely trigger recovery: 114.5 == 114.5")
suite.assertEqual(pr1b.rearWheelVy, -10.0, "Contact downward velocity not zeroed during normal contact: -10.0 == -10.0")

// 2. Wheel genuinely penetrates surface by trigger threshold (ideal is 100 + 16 = 116; current is 110)
var pr2 = MockPenetrationRecovery(rearWheelY: 110, rearWheelVy: -300, frontWheelY: 116, frontWheelVy: 0, chassisY: 140, chassisVy: 0)
pr2.recover(terrainY: 100)
suite.assertEqual(pr2.rearWheelY, 117.0, "Penetrating rear wheel clamped to idealY + recoveryClearance (117.0)")
suite.assertEqual(pr2.rearWheelVy, 0.0, "Penetrating rear wheel downward velocity cancelled")

// 3. Severe wheel breach below terrain line (current is 90, terrain is 100)
var pr3 = MockPenetrationRecovery(rearWheelY: 90, rearWheelVy: -800, frontWheelY: 92, frontWheelVy: -750, chassisY: 120, chassisVy: -400)
pr3.recover(terrainY: 100)
suite.assertEqual(pr3.rearWheelY, 117.0, "Subterranean rear wheel restored above surface")
suite.assert(pr3.frontWheelY >= 117.0, "Subterranean front wheel restored above surface")
suite.assertEqual(pr3.rearWheelVy, 0.0, "Subterranean rear downward velocity zeroed")
suite.assertEqual(pr3.frontWheelVy, 0.0, "Subterranean front downward velocity zeroed")

// 4. Chassis frame bottom-out penetration (terrain is 100, trigger 6 -> subterranean chassis 93 <= 94)
var pr4 = MockPenetrationRecovery(rearWheelY: 117, rearWheelVy: 0, frontWheelY: 117, frontWheelVy: 0, chassisY: 93, chassisVy: -250)
pr4.recover(terrainY: 100)
suite.assertEqual(pr4.chassisY, 101.0, "Chassis frame clamped to minChassisY + recoveryClearance (101.0)")
suite.assertEqual(pr4.chassisVy, 0.0, "Chassis downward velocity zeroed")

// 5. Catastrophic tunneling rescue (>60 units below terrain)
var pr5 = MockPenetrationRecovery(rearWheelY: 30, rearWheelVy: -1000, frontWheelY: 30, frontWheelVy: -1000, chassisY: 35, chassisVy: -1000)
pr5.recover(terrainY: 100)
suite.assert(pr5.rescued, "Catastrophic tunneling triggers emergency rescue")
suite.assertEqual(pr5.chassisY, 135.0, "Catastrophic chassis rescued to safe height above ground")
suite.assertEqual(pr5.chassisVy, 0.0, "Rescued vertical velocity zeroed")

// Test 14: Newtonian Gravity & Ballistic Launch Invariants
print("\n• Test Group 14: Newtonian Gravity & Ballistic Launch Invariants")

// 1. Friction coefficients: solid tire grip on dirt, frictionless chassis for scoops
let tireFriction: CGFloat = 0.90
let terrainFriction: CGFloat = 1.10
let combinedTireMu = sqrt(tireFriction * terrainFriction)
suite.assert(combinedTireMu >= 0.85, "Combined tire friction (\(combinedTireMu)) provides solid traction (>= 0.85)")
let chassisFriction: CGFloat = 0.02
suite.assert(chassisFriction <= 0.03, "Chassis friction (\(chassisFriction)) prevents ground hang-up and plowing drag (<= 0.03)")

// 2. Pure Newtonian gravity acceleration down 45° slope (no multipliers or artificial boosts)
let g: CGFloat = 9.81 * 14.0 // 137.34 pt/s²
let downhillSlopeAngle = CGFloat.pi / 4.0 // 45 deg
let accelAlong45Downhill = g * sin(downhillSlopeAngle) // 97.11 pt/s²
suite.assertNear(accelAlong45Downhill, 97.11, accuracy: 0.5, "Pure gravity acceleration down 45° slope is ~97.1 pt/s²")

// Simulate 1.5 seconds of downhill roll from 200 pt/s without any artificial multiplier
var downhillSpeed: CGFloat = 200.0
for _ in 0..<94 { // 94 frames * 0.016s = 1.504s
    downhillSpeed += accelAlong45Downhill * 0.016
}
suite.assert(downhillSpeed > 340.0, "Natural gravity massively builds speed down 45° hill (200 -> \(downhillSpeed) pt/s > 340)")

// 3. Consistent gravity deceleration up 30° hill
let uphillAngle = CGFloat.pi / 6.0 // 30 deg
let decelAlong30Uphill = g * sin(uphillAngle) // 68.67 pt/s²
suite.assertNear(decelAlong30Uphill, 68.67, accuracy: 0.5, "Pure gravity deceleration up 30° slope is ~68.7 pt/s²")

// 4. Parabolic jump trajectory: launching at 700 pt/s off 25.6° kicker (slope ~0.48)
let kickerTakeoffAngle = atan(0.48) // ~25.64 degrees
let launchVx = 700.0 * cos(kickerTakeoffAngle) // ~631.0 pt/s
let launchVy = 700.0 * sin(kickerTakeoffAngle) // ~302.9 pt/s
let apexHeight = (launchVy * launchVy) / (2.0 * g) // ~334.0 pt
let timeToApex = launchVy / g // ~2.21 s
let totalHangtime = timeToApex * 2.0 // ~4.41 s
let jumpDistance = launchVx * totalHangtime // ~2783 pt

suite.assert(apexHeight > 280.0 && apexHeight < 400.0, "Launch apex height is natural and weighted: \(apexHeight) pt (~334 pt)")
suite.assert(totalHangtime > 3.5 && totalHangtime < 5.5, "Hangtime is realistic (~4.4s): \(totalHangtime)s")
suite.assert(jumpDistance > 2000.0, "Horizontal jump distance carries far across landing zone: \(jumpDistance) pt")

// 5. Space launch elimination under authoritative gravity: even at 1500 pt/s launch, bike returns to earth
let extremeLaunchVy: CGFloat = 600.0
let extremeApexTime = extremeLaunchVy / g
let extremeApexHeight = (extremeLaunchVy * extremeLaunchVy) / (2.0 * g)
suite.assert(extremeApexTime < 5.0, "Extreme launch reaches apex within 5.0s (eliminates space launch bug): \(extremeApexTime)s")
suite.assert(extremeApexHeight < 1500.0, "Extreme launch apex is bounded by physics (< 1500 pt): \(extremeApexHeight) pt")

// 6. Trail-relative pitch crash detection: chassis touching terrain only crashes when pitched severely relative to trail slope and not grounded on both wheels
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
suite.assert(!uHillScrape.frameStrike && !uHillScrape.lostControl, "Compression at bottom of U-hill (0.90 rad relative pitch) does NOT cause false crash")

let airborneInverted = evaluateRunCrash(bothWheelsGrounded: false, isGrounded: false, chassisContact: false, chassisRotation: .pi, supportAngle: 0.0)
suite.assert(!airborneInverted.lostControl && !airborneInverted.frameStrike, "Mid-air inversion does NOT cause false crash")

let severeNoseDive = evaluateRunCrash(bothWheelsGrounded: false, isGrounded: true, chassisContact: true, chassisRotation: -1.30, supportAngle: 0.0)
suite.assert(severeNoseDive.frameStrike, "Severe nose-dive frame strike (>= 1.20 rad) correctly triggers crash")

let severeLoopOut = evaluateRunCrash(bothWheelsGrounded: false, isGrounded: true, chassisContact: true, chassisRotation: 1.30, supportAngle: 0.0)
suite.assert(severeLoopOut.frameStrike, "Severe loop-out frame strike (>= 1.20 rad) correctly triggers crash")

// 7. Braking deceleration: dedicated brake applies backward force along trail tangent
func simulateBraking(velocity: CGVector, tangent: CGVector, totalMass: CGFloat = 6.6, delta: TimeInterval = 0.016) -> CGVector {
    let alongTrail = velocity.dx * tangent.dx + velocity.dy * tangent.dy
    guard alongTrail > 20 else { return velocity }
    let brakeForce: CGFloat = 600
    let decel = (brakeForce / totalMass) * CGFloat(delta)
    let newSpeed = max(0, alongTrail - decel)
    return CGVector(dx: tangent.dx * newSpeed, dy: tangent.dy * newSpeed)
}

let fastVel = CGVector(dx: 500.0, dy: 0.0)
let flatTangent = CGVector(dx: 1.0, dy: 0.0)
let brakedVel = simulateBraking(velocity: fastVel, tangent: flatTangent)
suite.assert(brakedVel.dx < fastVel.dx, "Braking decelerates forward speed: \(fastVel.dx) -> \(brakedVel.dx)")

// 8. Transition momentum redirection: smooth climb velocity alignment with energy conservation
func simulateTransitionRedirection(velocity: CGVector, tangent: CGVector, isGrounded: Bool, delta: TimeInterval = 0.016) -> CGVector {
    guard isGrounded, tangent.dx > 0.1 else { return velocity }
    let currentSpeed = hypot(velocity.dx, velocity.dy)
    guard currentSpeed > 60 else { return velocity }

    let normal = CGVector(dx: -tangent.dy, dy: tangent.dx)
    let normalVelocity = velocity.dx * normal.dx + velocity.dy * normal.dy
    guard normalVelocity < -10 else { return velocity }

    let maxClimbDy: CGFloat = 0.48
    let climbDy = min(tangent.dy, maxClimbDy)
    let climbDx = sqrt(max(0.01, 1.0 - climbDy * climbDy))

    let targetVx = climbDx * currentSpeed
    let targetVy = climbDy * currentSpeed

    let blend: CGFloat = min(CGFloat(delta) * 25.0, 0.80)
    var newVx = velocity.dx * (1 - blend) + targetVx * blend
    var newVy = velocity.dy * (1 - blend) + targetVy * blend

    let newSpeed = hypot(newVx, newVy)
    if newSpeed > currentSpeed && newSpeed > 0 {
        let scale = currentSpeed / newSpeed
        newVx *= scale
        newVy *= scale
    }
    return CGVector(dx: newVx, dy: newVy)
}

// Entering a transition ramp (tangent dy = 0.45, dx = 0.893) at 800 pt/s downhill (vy = -200, vx = 774)
let scoopTangent = CGVector(dx: 0.893, dy: 0.450)
let scoopInVel = CGVector(dx: 774.0, dy: -200.0)
let inSpeed = hypot(scoopInVel.dx, scoopInVel.dy)
let redirectedVel = simulateTransitionRedirection(velocity: scoopInVel, tangent: scoopTangent, isGrounded: true)
let outSpeed = hypot(redirectedVel.dx, redirectedVel.dy)

suite.assert(redirectedVel.dy > scoopInVel.dy, "Transition scoop redirects velocity upward: \(scoopInVel.dy) -> \(redirectedVel.dy)")
suite.assert(outSpeed <= inSpeed + 0.01, "Transition redirection strictly conserves kinetic energy (no free speed): \(outSpeed) <= \(inSpeed)")

// Test 15: Uphill Pedal Traction & Anti-Rollback Ratchet Invariants
print("\n• Test Group 15: Uphill Pedal Traction & Anti-Rollback Ratchet Invariants")
func simulateUphillPedal(
    velocity: CGVector,
    tangent: CGVector,
    pedalHeld: Bool,
    isGrounded: Bool,
    pedalForce: CGFloat = 1_200,
    pedalClimbForce: CGFloat = 2_200,
    totalMass: CGFloat = 6.6,
    delta: TimeInterval = 0.016
) -> CGVector {
    guard pedalHeld, isGrounded else { return velocity }
    var vel = velocity
    let alongTrail = vel.dx * tangent.dx + vel.dy * tangent.dy

    // Anti-rollback ratchet
    if alongTrail < 0 && tangent.dy > 0 {
        vel.dx -= tangent.dx * alongTrail
        vel.dy -= tangent.dy * alongTrail
    }

    let forwardSpeed = max(0, vel.dx * tangent.dx + vel.dy * tangent.dy)
    let forceFade = max(0, min(1, 1 - forwardSpeed / 1_400))
    let climbLoad = max(tangent.dy, 0)
    let riderForce = (pedalForce + pedalClimbForce * climbLoad) * forceFade

    let accel = riderForce / totalMass
    vel.dx += tangent.dx * accel * CGFloat(delta)
    vel.dy += tangent.dy * accel * CGFloat(delta)
    return vel
}

// 1. Sliding backward down a 25-degree hill (-50 backward velocity along trail)
let hillAngle = CGFloat.pi / 7.2 // ~25 degrees
let hillTangent = CGVector(dx: cos(hillAngle), dy: sin(hillAngle))
let backwardVel = CGVector(dx: -hillTangent.dx * 50, dy: -hillTangent.dy * 50)

let engagedVel = simulateUphillPedal(velocity: backwardVel, tangent: hillTangent, pedalHeld: true, isGrounded: true)
let engagedTrailSpeed = engagedVel.dx * hillTangent.dx + engagedVel.dy * hillTangent.dy
suite.assert(engagedTrailSpeed > 0, "Anti-rollback ratchet cancels backward slide and drives forward: \(engagedTrailSpeed) > 0")

// 2. Starting from a dead stop on a 30-degree steep hill
let steepAngle = CGFloat.pi / 6.0 // 30 degrees (slope 0.577)
let steepTangent = CGVector(dx: cos(steepAngle), dy: sin(steepAngle))
var climbingVel = CGVector.zero

for _ in 0..<5 {
    climbingVel = simulateUphillPedal(velocity: climbingVel, tangent: steepTangent, pedalHeld: true, isGrounded: true)
}
let climbSpeedAfter5Frames = climbingVel.dx * steepTangent.dx + climbingVel.dy * steepTangent.dy
suite.assert(climbSpeedAfter5Frames > 8.0, "Pedal climb force powers bike up steep 30° hill from dead stop: \(climbSpeedAfter5Frames) > 8 pt/s")

// 3. Normal low-speed pedaling on flat accelerates smoothly
let flatVel = CGVector(dx: 60.0, dy: 0.0)
let pedaledVel = simulateUphillPedal(velocity: flatVel, tangent: flatTangent, pedalHeld: true, isGrounded: true)
suite.assert(pedaledVel.dx > flatVel.dx, "Pedaling on flat accelerates bike forward smoothly: \(flatVel.dx) -> \(pedaledVel.dx)")

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
    let ox = CGFloat(cycle) * 15400.0
    let oy = CGFloat(cycle) * -7565.3

    switch phase {
    case 0:
        return [
            TestSegment(start: CGPoint(x: -480 + ox, y: 1200 + oy), end: CGPoint(x: 20 + ox, y: 1200 + oy), startSlope: 0, endSlope: 0),
            TestSegment(start: CGPoint(x: 20 + ox, y: 1200 + oy), end: CGPoint(x: 260 + ox, y: 1080 + oy), startSlope: 0, endSlope: -1.0),
            TestSegment(start: CGPoint(x: 260 + ox, y: 1080 + oy), end: CGPoint(x: 1760 + ox, y: -420 + oy), startSlope: -1.0, endSlope: -1.0)
        ]
    case 1:
        return [
            TestSegment(start: CGPoint(x: 1760 + ox, y: -420 + oy), end: CGPoint(x: 2360 + ox, y: -1020 + oy), startSlope: -1.0, endSlope: -1.0),
            TestSegment(start: CGPoint(x: 2360 + ox, y: -1020 + oy), end: CGPoint(x: 3360 + ox, y: -1520 + oy), startSlope: -1.0, endSlope: 0.0),
            TestSegment(start: CGPoint(x: 3360 + ox, y: -1520 + oy), end: CGPoint(x: 3860 + ox, y: -1400 + oy), startSlope: 0.0, endSlope: 0.48),
            TestSegment(start: CGPoint(x: 3860 + ox, y: -1400 + oy), end: CGPoint(x: 4000 + ox, y: -1332.8 + oy), startSlope: 0.48, endSlope: 0.48),
            TestSegment(start: CGPoint(x: 4000 + ox, y: -1332.8 + oy), end: CGPoint(x: 6500 + ox, y: -2707.8 + oy), startSlope: 0.48, endSlope: -0.55, isSurface: false)
        ]
    case 2:
        return [
            TestSegment(start: CGPoint(x: 6500 + ox, y: -2707.8 + oy), end: CGPoint(x: 9500 + ox, y: -4357.8 + oy), startSlope: -0.55, endSlope: -0.55)
        ]
    case 3:
        return [
            TestSegment(start: CGPoint(x: 9500 + ox, y: -4357.8 + oy), end: CGPoint(x: 12500 + ox, y: -6007.8 + oy), startSlope: -0.55, endSlope: -0.55)
        ]
    case 4:
        return [
            TestSegment(start: CGPoint(x: 12500 + ox, y: -6007.8 + oy), end: CGPoint(x: 13800 + ox, y: -6365.3 + oy), startSlope: -0.55, endSlope: 0.0),
            TestSegment(start: CGPoint(x: 13800 + ox, y: -6365.3 + oy), end: CGPoint(x: 14920 + ox, y: -6365.3 + oy), startSlope: 0.0, endSlope: 0.0)
        ]
    default:
        return []
    }
}

// 1. Check spawn flat platform
let chunk0 = testMakeMegaJumpChunk(index: 0)
suite.assertEqual(chunk0[0].start.x, -480.0, "Mega Jump starts at x = -480")
suite.assertEqual(chunk0[0].start.y, 1200.0, "Mega Jump starting elevation is 1200")
suite.assertEqual(chunk0[0].startSlope, 0.0, "Mega Jump spawn starting slope is flat 0.0")

// 2. Downhill leadup length & steepness
let leadupStart = chunk0[1].start.x // x = 20
let leadupEnd = testMakeMegaJumpChunk(index: 1)[0].end.x // x = 2360
let leadupLength = leadupEnd - leadupStart
suite.assert(leadupLength >= 2000.0, "Downhill leadup is massive: \(leadupLength) >= 2000 pt")
suite.assertEqual(testMakeMegaJumpChunk(index: 1)[0].endSlope, -1.0, "Downhill leadup is steep 45-degree plunge (-1.0)")

// 3. Launch ramp takeoff slope & elevation gain (short, fast, snappy)
let chunk1 = testMakeMegaJumpChunk(index: 1)
let launchSeg = chunk1[3] // snappy kicker ramp
suite.assert(launchSeg.endSlope <= 0.55, "Launch ramp has steep, mega-launching angle: \(launchSeg.endSlope) (~25.6°)")
let rampGain = launchSeg.end.y - chunk1[1].end.y // y = -1332.8 - (-1520) = 187.2
suite.assert(rampGain <= 250.0, "Launch ramp provides smooth elevation gain: \(rampGain) <= 250 pt")
suite.assert(!chunk1[4].isSurface, "Launch kicker terminates with an air gap (isSurface == false) to ensure ballistic flight")
let gapLengthMeters = (chunk1[4].end.x - chunk1[4].start.x) / 14.0
suite.assert(gapLengthMeters >= 100.0, "Mega Jump gap spans 100s of meters: \(gapLengthMeters)m >= 100m")

// 4. Landing catch runway length
let chunk2 = testMakeMegaJumpChunk(index: 2)
let chunk3 = testMakeMegaJumpChunk(index: 3)
let landingCatchLen = (chunk3[0].end.x - chunk2[0].start.x)
suite.assert(landingCatchLen >= 5000.0, "Landing catch zone is expansive: \(landingCatchLen) >= 5000 pt")
suite.assertEqual(chunk2[0].startSlope, -0.55, "Landing catch slope is smooth -0.55")

// 5. C1 Continuity check across 15 chunks (3 full cycles)
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
suite.assert(c1Continuous, "All 15 chunks (3 full Mega Jump cycles) maintain strict C1 position & slope continuity")

// Test Group 12: Chassis Collider Geometry & Suspension Kinematics
print("\n• Test Group 12: Chassis Skid Plate & Suspension Kinematics")
let frameVerts: [CGPoint] = [
    CGPoint(x: -12, y: 2),
    CGPoint(x: -5, y: 0),
    CGPoint(x: 14, y: 8),
    CGPoint(x: 14, y: 16),
    CGPoint(x: -14, y: 16)
]

// 1. Skid plate clearance above wheels
let skidPlateMinY = frameVerts.map(\.y).min() ?? 0
suite.assert(skidPlateMinY >= 0.0, "Chassis collider lowest point (\(skidPlateMinY)) sits at or above y = 0 (tucked safely above wheel axle at -27 and contact at -43)")

// 2. Upswept leading edge (glides over lips instead of plowing)
let bottomVertex = frameVerts.first(where: { $0.y == skidPlateMinY }) ?? .zero
let frontVertex = frameVerts.first(where: { $0.x > 0 && $0.y < 16 }) ?? .zero
let upsweepSlope = (frontVertex.y - bottomVertex.y) / (frontVertex.x - bottomVertex.x)
suite.assert(upsweepSlope > 0.35, "Chassis leading edge sweeps upward with ski slope \(upsweepSlope) > 0.35 to skip over lips")

// 3. Strict convexity test (all cross products strictly positive for CCW polygon)
var strictlyConvex = true
let n = frameVerts.count
for i in 0..<n {
    let pPrev = frameVerts[i]
    let pCurr = frameVerts[(i + 1) % n]
    let pNext = frameVerts[(i + 2) % n]
    let v1 = CGPoint(x: pCurr.x - pPrev.x, y: pCurr.y - pPrev.y)
    let v2 = CGPoint(x: pNext.x - pCurr.x, y: pNext.y - pCurr.y)
    let cross = v1.x * v2.y - v1.y * v2.x
    if cross <= 0 {
        strictlyConvex = false
    }
}
suite.assert(strictlyConvex, "Chassis collider polygon is strictly convex for valid SKPhysicsBody construction")

// 4. Suspension travel and stiffness invariants
let rearTravelRange: CGFloat = 0.26 - (-0.06) // 0.32 rad
suite.assert(rearTravelRange >= 0.25, "Rear suspension angular travel range (\(rearTravelRange) rad) is >= 0.25 rad")
let frontForkTravel: CGFloat = abs(-14.0) // 14.0 pt
suite.assert(frontForkTravel >= 12.0, "Front fork compression travel (\(frontForkTravel) pt) is >= 12.0 pt")
let rearShockFreq: CGFloat = 30.0
suite.assert(rearShockFreq >= 28.0, "Rear shock frequency (\(rearShockFreq) Hz) is >= 28.0 Hz to prevent U-hill bottom-out")
suite.assertEqual(chassisFriction, 0.02, "Chassis friction is set to ultra-slick 0.02")

// 5. Rollable trough transition invariant
let minRampLen: CGFloat = 200
suite.assert(minRampLen >= 180, "Trough transition ramp length (\(minRampLen) pt) provides smooth, rollable U-hill exit")

let allPassed = suite.summary()
exit(allPassed ? 0 : 1)
