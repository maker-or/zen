import SwiftUI

struct GridView: View {
    @Environment(\.zenTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: ZenState = .shared
    @Namespace private var zoomNamespace
    @State private var currentPresetIndex = MemoGridZoom.sizes.count - 1
    @State private var pinchAnchor: UnitPoint = .center
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.38, dampingFraction: 0.88)))
    private var pinchMagnification: CGFloat = 1

    private var cellSize: CGFloat { MemoGridZoom.sizes[currentPresetIndex] }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                if state.transcriptHistory.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 36))
                            .foregroundColor(theme.foreground.opacity(0.7))
                        Text("No transcripts yet")
                            .foregroundColor(theme.foreground)
                            .font(.system(size: 15))
                        Text("Press \(state.recordingShortcut.displayString) to record")
                            .foregroundColor(theme.foreground.opacity(0.7))
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    let columns = calculateColumns(for: geometry.size.width)

                    LazyVGrid(columns: columns, spacing: MemoGridZoom.spacing) {
                        ForEach(state.transcriptHistory) { memo in
                            TranscriptCell(
                                baseSize: cellSize,
                                text: memo.text,
                                onDelete: {
                                    state.removeMemo(id: memo.id)
                                }
                            )
                            .matchedGeometryEffect(id: memo.id, in: zoomNamespace, anchor: .topLeading)
                        }
                    }
                    .padding(MemoGridZoom.padding)
                }
            }
        }
        // Only transform the rendered grid during a pinch. Reflow once on
        // release, rather than rebuilding column layouts on every gesture tick.
        .scaleEffect(
            reduceMotion ? 1 : MemoGridZoom.previewScale(magnification: pinchMagnification, from: currentPresetIndex),
            anchor: pinchAnchor
        )
        .clipped()
        .gesture(magnificationGesture)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchMagnification) { value, magnification, transaction in
                // Follow the fingers directly; spring only when settling.
                transaction.animation = nil
                magnification = value.magnification
            }
            .onChanged { value in
                pinchAnchor = value.startAnchor
            }
            .onEnded { value in
                let index = MemoGridZoom.presetIndex(magnification: value.magnification, from: currentPresetIndex)
                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)) {
                    currentPresetIndex = index
                }
            }
    }

    private func calculateColumns(for availableWidth: CGFloat) -> [GridItem] {
        let count = MemoGridZoom.columnCount(width: availableWidth, size: cellSize)
        return Array(repeating: GridItem(.flexible(), spacing: MemoGridZoom.spacing), count: count)
    }

}

struct TranscriptCell: View {
    @Environment(\.zenTheme) private var theme
    let baseSize: CGFloat
    let text: String
    let onDelete: (() -> Void)?

    @State private var isHovering = false
    @State private var copied = false
    @State private var deleteBounce = false

    // Everything scales linearly off the cell size so every zoom level reads
    // like the X-Large view, just smaller: the characters-per-line stays
    // roughly constant instead of collapsing to 1–2 words as the cell shrinks.
    private var fontSize: CGFloat { max(baseSize * 0.095, 9) }
    private var cellPadding: CGFloat { max(baseSize * 0.045, 6) }
    private var cornerRadius: CGFloat { max(baseSize * 0.05, 6) }
    private var lineSpacing: CGFloat { fontSize * 0.16 }
    // The hover pill's controls have a fixed minimum size; below this the cell
    // is too small to host them without overwhelming the text.
    private var showsPill: Bool { baseSize >= 120 }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(text)
                .foregroundColor(theme.foreground)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .lineSpacing(lineSpacing)
                .lineLimit(12)
                .truncationMode(.tail)
                .padding(cellPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if showsPill {
                // Keep the action row in the layout even when hidden, so long
                // transcripts never draw beneath it or shift on hover.
                glassPill
                    .padding(10)
                    .opacity(isHovering ? 1 : 0)
                    .scaleEffect(isHovering ? 1 : 0.9)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
        }
        .background(theme.surface, in: .rect(cornerRadius: cornerRadius))
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(theme.foreground.opacity(0.15), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var glassPill: some View {
        HStack(spacing: 0) {
            Button(action: {
                copied = true
                copyToClipboard()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    copied = false
                }
            }) {
                Group {
                    if copied {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "doc.on.doc")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.foreground)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Copy")

            Divider()
                .frame(height: 14)

            if let onDelete = onDelete {
                Button(action: {
                    deleteBounce.toggle()
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.foreground)
                        .symbolEffect(.bounce, options: .speed(1.5), value: deleteBounce)
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
