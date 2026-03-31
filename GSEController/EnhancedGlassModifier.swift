import SwiftUI

// Re-evaluate after macOS 26.1 — glass material may gain native depth cues
struct EnhancedGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tintColor: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerPhase: CGFloat = 0

    private var shadowOpacity: Double {
        if reduceTransparency { return colorScheme == .dark ? 0.06 : 0.10 }
        return colorScheme == .dark ? 0.15 : 0.25
    }

    private var shadowRadius: CGFloat { reduceTransparency ? 4 : 8 }
    private var shadowY: CGFloat { reduceTransparency ? 2 : 4 }
    private var shouldAnimateShimmer: Bool { !reduceTransparency && !reduceMotion && tintColor != nil }

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background {
                // Depth shadow rendered behind the glass composite
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.black.opacity(0.001))
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)

                // Colored glow halo when a tint is active
                if let tint = tintColor {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.black.opacity(0.001))
                        .shadow(color: tint.opacity(0.35), radius: 14, x: 0, y: 0)
                }
            }
            .overlay {
                if !reduceTransparency {
                    // Specular rim — simulates overhead light catching a glass edge
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.30),
                                    .white.opacity(0.10),
                                    .clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                        .allowsHitTesting(false)

                    // Shimmer sweep — moving specular band simulating reflected light
                    if shouldAnimateShimmer {
                        GeometryReader { geo in
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.08), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.40)
                            .offset(x: shimmerPhase * (geo.size.width * 1.40) - geo.size.width * 0.40)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .allowsHitTesting(false)
                    }

                    // Tint surface wash + colored rim accent
                    if let tint = tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(tint.opacity(0.07))
                            .allowsHitTesting(false)

                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(tint.opacity(0.30), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                }
            }
            .onAppear {
                updateShimmerAnimation()
            }
            .onChange(of: shouldAnimateShimmer) { _, _ in updateShimmerAnimation() }
    }

    private func updateShimmerAnimation() {
        shimmerPhase = 0
        guard shouldAnimateShimmer else { return }
        withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.0
        }
    }
}

extension View {
    func enhancedGlass(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
        modifier(EnhancedGlassModifier(cornerRadius: cornerRadius, tintColor: tint))
    }
}
