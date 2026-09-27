import SwiftUI

/// Applies macOS 26 Liquid Glass to a view with a graceful fallback to
/// material fills on earlier systems.
struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    var shape: S
    var cornerRadius: CGFloat = 24
    /// Tints the glass (e.g. a highlight while a drag hovers a drop target).
    var tint: Color? = nil
    /// Real Liquid Glass's pointer/touch-reactive highlight (macOS 26+ only;
    /// no-op in the material fallback).
    var interactive: Bool = false
    var fallbackOpacity: Double = 0.16

    /// `ViewModifier.body` is `@ViewBuilder`, which cannot host imperative
    /// `var`/`if let` mutation — build the `Glass` value here instead.
    @available(macOS 26.0, *)
    private func resolvedGlass() -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(resolvedGlass(), in: shape)
        } else {
            content
                .background(
                    shape.fill(.ultraThinMaterial)
                )
                .background(
                    shape.fill((tint ?? .white).opacity(fallbackOpacity))
                )
                .overlay(
                    shape.strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
        }
    }
}

extension View {
    /// Liquid Glass surface for rounded-rectangle containers (folders, popups).
    func liquidGlass(
        cornerRadius: CGFloat = 24,
        tint: Color? = nil,
        interactive: Bool = false,
        fallbackOpacity: Double = 0.16
    ) -> some View {
        modifier(LiquidGlassModifier(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            cornerRadius: cornerRadius,
            tint: tint,
            interactive: interactive,
            fallbackOpacity: fallbackOpacity
        ))
    }

    /// Liquid Glass surface for capsule shapes (search field).
    func liquidGlassCapsule(tint: Color? = nil, fallbackOpacity: Double = 0.16) -> some View {
        modifier(LiquidGlassModifier(
            shape: Capsule(),
            tint: tint,
            fallbackOpacity: fallbackOpacity
        ))
    }
}
