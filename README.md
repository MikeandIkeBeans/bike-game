# Trail Rush

Trail Rush is an iPhone landscape, side-view downhill-biking prototype built with SwiftUI and SpriteKit. It is an early physics vertical slice, not a finished game or a full bicycle simulation.

## Current status

- The bike uses one compound SpriteKit rigid body; its two wheels are visual only.
- The course streams deterministic terrain chunks generated from a seed.
- PEDAL and lean controls, a follow camera, HUD, crash/reset flow, and local best-distance storage are implemented.
- Bike behavior is still under active tuning and needs playtesting across terrain. It should not be treated as final or fully stable.

## Controls

- Tap the opening overlay to begin a run.
- Hold the center **PEDAL** control to drive while the bike has terrain support.
- Hold **LEAN BACK** to pitch the nose up, or **LEAN FORWARD** to pitch the nose down.
- Controls support multitouch, so PEDAL can be combined with either lean direction.
- Releasing PEDAL does not brake; gravity, momentum, and terrain contacts determine movement.

## Requirements

- Xcode with the iOS 17 SDK (deployment target: iOS 17.0)
- An iPhone Simulator or iPhone device
- No third-party dependencies, network services, or external setup

## Run in Xcode

1. Open `MountainBike.xcodeproj`.
2. Select the `MountainBike` scheme and an iPhone target.
3. Build and run. The app is landscape-only on iPhone.

## Simulator build check

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project MountainBike.xcodeproj -scheme MountainBike \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/trailrush-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 build
```

## Project structure

- `MountainBike/Game/BikeNode.swift` — bike visuals and its single compound physics body.
- `MountainBike/Game/MountainBikeScene.swift` — input, drive/lean handling, contacts, camera, HUD, and crash flow.
- `MountainBike/Game/TerrainStreamController.swift` — deterministic streamed terrain, rendering, and collision rails.
- `MountainBike/Game/GameTuning.swift` — gameplay and physics values; change deliberately and test each change.

## Development guardrails

Do not add independent wheel bodies, joints, or suspension mechanics without first redesigning contacts, control forces, crash rules, and playtests around that vehicle model. Terrain visuals and collision rails must continue to use the same sampled world-space points.

## License

No license has been selected yet.
