import SwiftUI

enum EnhancedGlassStyle {
    case primary
    case status
    case nested
}

// Re-evaluate after macOS 26.1 — glass material may gain native depth cues
struct EnhancedGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tintColor: Color?
    var style: EnhancedGlassStyle
    var isActive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerPhase: CGFloat = 0

    private var shadowOpacity: Double {
        if reduceTransparency { return colorScheme == .dark ? 0.06 : 0.10 }
        switch style {
        case .primary: return colorScheme == .dark ? 0.15 : 0.25
        case .status:  return colorScheme == .dark ? 0.10 : 0.16
        case .nested:  return colorScheme == .dark ? 0.06 : 0.10
        }
    }

    private var shadowRadius: CGFloat {
        if reduceTransparency { return 4 }
        switch style {
        case .primary: return 8
        case .status:  return 6
        case .nested:  return 3
        }
    }

    private var shadowY: CGFloat {
        if reduceTransparency { return 2 }
        switch style {
        case .primary: return 4
        case .status:  return 3
        case .nested:  return 1
        }
    }

    private var tintHaloOpacity: Double {
        switch style {
        case .primary: return 0.35
        case .status:  return 0.18
        case .nested:  return 0.12
        }
    }

    private var tintWashOpacity: Double {
        switch style {
        case .primary: return 0.07
        case .status:  return 0.045
        case .nested:  return 0.035
        }
    }

    private var tintStrokeOpacity: Double {
        switch style {
        case .primary: return 0.30
        case .status:  return 0.22
        case .nested:  return 0.16
        }
    }

    private var rimHighlightOpacity: Double {
        switch style {
        case .primary: return 0.30
        case .status:  return 0.24
        case .nested:  return 0.18
        }
    }

    private var fallbackFill: Color {
        switch (style, colorScheme) {
        case (.primary, .dark): return .white.opacity(0.08)
        case (.primary, _):     return .black.opacity(0.04)
        case (.status, .dark):  return .white.opacity(0.07)
        case (.status, _):      return .black.opacity(0.035)
        case (.nested, .dark):  return .white.opacity(0.05)
        case (.nested, _):      return .black.opacity(0.025)
        }
    }

    private var fallbackStroke: Color {
        switch colorScheme {
        case .dark: return .white.opacity(0.18)
        default:    return .black.opacity(0.12)
        }
    }

    private var shouldAnimateShimmer: Bool {
        !reduceTransparency && !reduceMotion && tintColor != nil && isActive && style == .primary
    }

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fallbackFill)
                }

                // Depth shadow rendered behind the glass composite
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.black.opacity(0.001))
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)

                // Colored glow halo when a tint is active
                if let tint = tintColor {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.black.opacity(0.001))
                        .shadow(color: tint.opacity(tintHaloOpacity), radius: style == .primary ? 14 : 9, x: 0, y: 0)
                }
            }
            .overlay {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(fallbackStroke, lineWidth: 0.75)
                        .allowsHitTesting(false)

                    if let tint = tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(tint.opacity(tintStrokeOpacity), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                } else {
                    // Specular rim — simulates overhead light catching a glass edge
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(rimHighlightOpacity),
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
                            .fill(tint.opacity(tintWashOpacity))
                            .allowsHitTesting(false)

                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(tint.opacity(tintStrokeOpacity), lineWidth: 0.75)
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
    func enhancedGlass(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        style: EnhancedGlassStyle = .primary,
        isActive: Bool = false
    ) -> some View {
        modifier(EnhancedGlassModifier(
            cornerRadius: cornerRadius,
            tintColor: tint,
            style: style,
            isActive: isActive
        ))
    }
}
