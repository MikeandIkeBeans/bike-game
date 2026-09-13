import SpriteKit
import SwiftUI

struct ContentView: View {
    private static let sceneSize = CGSize(width: 844, height: 390)

    @State private var scene: SKScene = MountainBikeScene(size: ContentView.sceneSize)

    var body: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .background(.black)
    }
}
