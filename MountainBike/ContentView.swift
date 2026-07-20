import SpriteKit
import SwiftUI

struct ContentView: View {
    @State private var scene = MountainBikeScene(size: CGSize(width: 844, height: 390))

    var body: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .background(.black)
    }
}
