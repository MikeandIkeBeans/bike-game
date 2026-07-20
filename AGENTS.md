# Bike Game project instructions

## Game model

- This project is a **2D, landscape, side-view SpriteKit game**. SpriteKit world coordinates are y-up; the bike faces +x; positive rotation/torque pitches its nose up (back lean).
- The v1 vehicle model is one compound dynamic rigid body. The two wheels are visual only. Do not add joints, separate wheel bodies, or suspension without explicitly calling that out first.
- The current milestone is a hand-authored physics vertical slice: one hill, touch torque, camera, crash/reset. Do not add procedural terrain, cosmetics, ghosts, pickups, or leaderboard work until that loop is playtested.

## Physics safety rules

- `MountainBike/Game/GameTuning.swift` is the sole home for gameplay-feel and physics constants. Never change a value there as incidental cleanup; call out every tuning change in the final response.
- Terrain draw paths and terrain collision paths must be generated from the same sampled world-space points. Keep collider segments short and never move a physics terrain path beneath the bike.
- Use explicit physics category/collision/contact masks. Grounded state must use per-body `Set<ObjectIdentifier>` contact tracking, not a counter.
- `requestCrash` / the post-physics crash evaluator owns crash transitions. Contact callbacks may record facts or queue a crash, but must not reset/remove gameplay nodes directly.
- High-speed safeguards are required: capped linear/angular velocity plus `usesPreciseCollisionDetection` on the bike body.

## Verification

- Run an actual build after source changes and report its output accurately. A generic simulator build proves compile/link/bundle validation, not device feel or input behavior.
- Simulator-only build command:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MountainBike.xcodeproj -scheme MountainBike \
    -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath /tmp/trailrush-derived \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 build
  ```
