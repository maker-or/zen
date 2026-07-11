import SwiftUI

struct ZoomPreset: Identifiable {
    let id: Int
    let name: String
    let cellSize: CGFloat
    let icon: String
}

struct GridView: View {
    @ObservedObject var state: ZenState = .shared

    private let presets: [ZoomPreset] = [
        ZoomPreset(id: 0, name: "Small",  cellSize: 60,  icon: "rectangle.grid.1x2"),
        ZoomPreset(id: 1, name: "Medium", cellSize: 100, icon: "rectangle.grid.2x2"),
        ZoomPreset(id: 2, name: "Large",  cellSize: 170, icon: "rectangle.grid.3x2"),
        ZoomPreset(id: 3, name: "X-Large",cellSize: 280, icon: "square.grid.4x3.fill"),
    ]

    @State private var currentPresetIndex: Int = 1
    @State private var gestureAccumulator: CGFloat = 0
    @State private var lastReference: CGFloat = 1.0
    private let snapThreshold: CGFloat = 0.3
    private let minColumns = 3
    private let maxColumns = 12
    private let spacing: CGFloat = 12

    private var currentPreset: ZoomPreset {
        presets[currentPresetIndex]
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                if state.transcriptHistory.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No transcripts yet")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.system(size: 15))
                        Text("Press Option+Space to record")
                            .foregroundColor(.white.opacity(0.25))
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    let columns = calculateColumns(for: geometry.size.width)

                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(state.transcriptHistory, id: \.self) { text in
                            TranscriptCell(
                                baseSize: currentPreset.cellSize,
                                text: text,
                                onDelete: {
                                    state.removeFromHistory(text)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .gesture(magnificationGesture)
    }

    private func moveToPreset(at index: Int) {
        guard presets.indices.contains(index) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            currentPresetIndex = index
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification - lastReference
                gestureAccumulator += delta

                if gestureAccumulator > snapThreshold {
                    if currentPresetIndex < presets.count - 1 {
                        moveToPreset(at: currentPresetIndex + 1)
                    }
                    lastReference = value.magnification
                    gestureAccumulator = 0
                } else if gestureAccumulator < -snapThreshold {
                    if currentPresetIndex > 0 {
                        moveToPreset(at: currentPresetIndex - 1)
                    }
                    lastReference = value.magnification
                    gestureAccumulator = 0
                }
            }
            .onEnded { _ in
                gestureAccumulator = 0
                lastReference = 1.0
            }
    }

    private func calculateColumns(for availableWidth: CGFloat) -> [GridItem] {
        let rawCount = Int(availableWidth / (currentPreset.cellSize + spacing))
        let count = min(max(rawCount, minColumns), maxColumns)
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

}

struct TranscriptCell: View {
    let baseSize: CGFloat
    let text: String
    let onDelete: (() -> Void)?

    @State private var isHovering = false

    private var displayFont: Font {
        switch baseSize {
        case 200...: .largeTitle
        case 130..<200: .title
        case 80..<130: .title2
        default: .title3
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(text)
                .foregroundColor(.black.opacity(0.75))
                .font(displayFont.weight(.medium))
                .fontDesign(.rounded)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            glassPill
                .padding(10)
                .opacity(isHovering ? 1 : 0)
                .scaleEffect(isHovering ? 1 : 0.9)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var glassPill: some View {
        HStack(spacing: 0) {
            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Copy")

            Divider()
                .frame(height: 14)

            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
        .padding(.horizontal, 4)

    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
