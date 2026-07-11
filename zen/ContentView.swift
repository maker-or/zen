import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appDelegate: AppDelegate

    var body: some View {
        NavigationStack {
            TabView {
                Text("Home")
                    .tabItem { Text("Home") }
                Text("API")
                    .tabItem { Text("API") }
                Text("ChatGPT")
                    .tabItem { Text("ChatGPT") }
                GridView()
                    .tabItem { Text("Grid") }
            }
            .background(
                VisualEffectView(material: .fullScreenUI, blendingMode: .withinWindow)
                    .ignoresSafeArea()
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .status) {
                Button(action: {}) {
                    Image(systemName: "sparkle")
                }
                Button(action: {}) {
                    Image(systemName: "shuffle")
                }
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
