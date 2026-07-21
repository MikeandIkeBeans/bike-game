import SpriteKit
import SwiftUI

struct ContentView: View {
    private enum GameMode: CaseIterable, Hashable, Identifiable {
        case trailRide
        case rearSuspensionRig

        var id: Self { self }

        var title: String {
            switch self {
            case .trailRide:
                "TRAIL RIDE"
            case .rearSuspensionRig:
                "REAR SUSPENSION RIG"
            }
        }

        var subtitle: String {
            switch self {
            case .trailRide:
                "One-body bike on the hand-authored hill"
            case .rearSuspensionRig:
                "Flat-ground playable bike and rear-suspension test lab"
            }
        }

        func makeScene() -> SKScene {
            switch self {
            case .trailRide:
                MountainBikeScene(size: ContentView.sceneSize)
            case .rearSuspensionRig:
                RearSuspensionRigScene(size: ContentView.sceneSize)
            }
        }
    }

    private enum SuspensionLabActivity: CaseIterable, Hashable, Identifiable {
        case rideBike
        case stressFixture

        var id: Self { self }

        var title: String {
            switch self {
            case .rideBike:
                "RIDE BIKE"
            case .stressFixture:
                "STRESS FIXTURE"
            }
        }

        var subtitle: String {
            switch self {
            case .rideBike:
                "Flat-ground playable bike with live rear suspension"
            case .stressFixture:
                "Fixed-pivot automated bounded-load endurance test"
            }
        }

        func makeScene() -> SKScene {
            switch self {
            case .rideBike:
                PlayableRearSuspensionScene(size: ContentView.sceneSize)
            case .stressFixture:
                RearSuspensionRigScene(size: ContentView.sceneSize)
            }
        }
    }

    private static let sceneSize = CGSize(width: 844, height: 390)

    @State private var scene: SKScene? = nil
    @State private var isShowingSuspensionLabPicker = false

    var body: some View {
        Group {
            if let scene {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
            } else if isShowingSuspensionLabPicker {
                suspensionLabPicker
            } else {
                modePicker
            }
        }
        .background(.black)
    }

    private var modePicker: some View {
        VStack(spacing: 16) {
            VStack(spacing: 7) {
                Text("BIKE GAME")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.63, green: 0.95, blue: 0.86))

                Text("CHOOSE A MODE")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("The suspension lab stays separate from the hill physics.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .padding(.bottom, 6)

            ForEach(GameMode.allCases) { mode in
                Button {
                    switch mode {
                    case .trailRide:
                        scene = mode.makeScene()
                    case .rearSuspensionRig:
                        isShowingSuspensionLabPicker = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(mode.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.8)

                        Text(mode.subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, 18)
                    .background(modeButtonBackground(for: mode))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityHint(mode.subtitle)
            }
        }
        .frame(maxWidth: 400)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.055, blue: 0.090),
                    Color(red: 0.045, green: 0.095, blue: 0.125)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .ignoresSafeArea()
    }

    private var suspensionLabPicker: some View {
        VStack(spacing: 16) {
            VStack(spacing: 7) {
                Text("REAR SUSPENSION LAB")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.63, green: 0.95, blue: 0.86))

                Text("CHOOSE AN ACTIVITY")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Ride the flat-ground prototype or keep running the fixed-pivot fixture.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .padding(.bottom, 6)

            ForEach(SuspensionLabActivity.allCases) { activity in
                Button {
                    scene = activity.makeScene()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(activity.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(activity.subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, 18)
                    .background(modeButtonBackground(for: activity == .rideBike ? .trailRide : .rearSuspensionRig))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(activity.title)
                .accessibilityHint(activity.subtitle)
            }

            Button("BACK TO MODES") {
                isShowingSuspensionLabPicker = false
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.top, 3)
        }
        .frame(maxWidth: 400)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.055, blue: 0.090),
                    Color(red: 0.045, green: 0.095, blue: 0.125)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .ignoresSafeArea()
    }

    private func modeButtonBackground(for mode: GameMode) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(mode == .trailRide
                ? Color(red: 0.08, green: 0.24, blue: 0.28)
                : Color(red: 0.14, green: 0.20, blue: 0.32))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
    }

}
