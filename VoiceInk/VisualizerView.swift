import SwiftUI

struct VisualizerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var levels: [CGFloat] = Array(repeating: 0, count: 50)
    private let smoothingFactor: CGFloat = 0.3
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<levels.count, id: \.self) { index in
                    VisualizerBar(level: levels[index])
                        .frame(width: (geometry.size.width - CGFloat(levels.count - 1) * 2) / CGFloat(levels.count))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black.opacity(0.1))
            .cornerRadius(10)
            .onReceive(audioEngine.$audioLevel) { newLevel in
                updateLevels(with: newLevel)
            }
        }
    }
    
    private func updateLevels(with newLevel: CGFloat) {
        // Apply smoothing to make transitions more natural
        for i in 0..<levels.count {
            let randomFactor = CGFloat.random(in: 0.8...1.2)
            let targetLevel = min(max(newLevel * randomFactor, 0), 1)
            let smoothedLevel = levels[i] + (targetLevel - levels[i]) * smoothingFactor
            
            withAnimation(.easeInOut(duration: 0.15)) {
                levels[i] = smoothedLevel
            }
        }
    }
}

struct VisualizerBar: View {
    let level: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(gradient: Gradient(colors: [.blue, .purple]),
                                   startPoint: .bottom,
                                   endPoint: .top)
                )
                .frame(height: level * geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}
