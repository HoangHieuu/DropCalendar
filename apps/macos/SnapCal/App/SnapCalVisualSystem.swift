import AppKit
import SwiftUI

/// Shared colors for SnapCal's original washi-and-ink visual language.
///
/// The colors are backed by dynamic `NSColor` values so callers do not need to
/// branch on `ColorScheme`. High-contrast appearances receive a stronger line
/// color while retaining the same visual identity.
enum SnapCalPalette {
    static let paper = adaptive(
        light: 0xF7F1D8,
        dark: 0x0E2529,
        highContrastLight: 0xFFFBEA,
        highContrastDark: 0x071719
    )

    static let paperRaised = adaptive(
        light: 0xFFFBEA,
        dark: 0x162F33,
        highContrastLight: 0xFFFFFF,
        highContrastDark: 0x1B383D
    )

    static let ink = adaptive(
        light: 0x103F46,
        dark: 0xF1E8CA,
        highContrastLight: 0x082E34,
        highContrastDark: 0xFFFBEA
    )

    static let inkMuted = adaptive(
        light: 0x536966,
        dark: 0xB5B9A8,
        highContrastLight: 0x3F5552,
        highContrastDark: 0xD8D8C6
    )

    static let teal = adaptive(
        light: 0x134D55,
        dark: 0x8DBFC0,
        highContrastLight: 0x083C43,
        highContrastDark: 0xA9D8D8
    )

    static let vermilion = adaptive(
        light: 0xC44726,
        dark: 0xE2734C,
        highContrastLight: 0xA93218,
        highContrastDark: 0xF28A65
    )

    static let sage = adaptive(
        light: 0x6F8A72,
        dark: 0xA7B99E,
        highContrastLight: 0x526E56,
        highContrastDark: 0xC2D1B8
    )

    static let line = adaptive(
        light: 0xB7B49C,
        dark: 0x3D585C,
        highContrastLight: 0x787A69,
        highContrastDark: 0x739094
    )

    private static func adaptive(
        light: UInt32,
        dark: UInt32,
        highContrastLight: UInt32,
        highContrastDark: UInt32
    ) -> Color {
        let color = NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .darkAqua,
                .accessibilityHighContrastAqua,
                .aqua
            ]) {
            case .accessibilityHighContrastDarkAqua:
                return nsColor(hex: highContrastDark)
            case .darkAqua:
                return nsColor(hex: dark)
            case .accessibilityHighContrastAqua:
                return nsColor(hex: highContrastLight)
            default:
                return nsColor(hex: light)
            }
        }
        return Color(nsColor: color)
    }

    private static func nsColor(hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Full-bleed paper canvas with subtle, deterministic fibers and ink motifs.
///
/// Place this at the back of a `ZStack`. It ignores the safe area and never
/// participates in hit testing or the accessibility tree.
struct WashiCanvas: View {
    let showsMotifs: Bool

    init(showsMotifs: Bool = true) {
        self.showsMotifs = showsMotifs
    }

    var body: some View {
        GeometryReader { proxy in
            let rippleSize = min(max(proxy.size.width * 0.30, 220), 480)
            let waveWidth = min(max(proxy.size.width * 0.42, 320), 720)

            ZStack {
                SnapCalPalette.paper

                LinearGradient(
                    colors: [
                        SnapCalPalette.paperRaised.opacity(0.72),
                        SnapCalPalette.paper.opacity(0.18),
                        SnapCalPalette.sage.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                WashiFiberField()

                if showsMotifs {
                    RippleMotif(color: SnapCalPalette.teal)
                        .frame(width: rippleSize, height: rippleSize)
                        .position(
                            x: proxy.size.width * 0.08,
                            y: proxy.size.height * 0.88
                        )

                    WaveMotif(color: SnapCalPalette.teal)
                        .frame(width: waveWidth, height: max(180, proxy.size.height * 0.34))
                        .position(
                            x: proxy.size.width * 0.84,
                            y: proxy.size.height * 0.14
                        )

                    Circle()
                        .fill(SnapCalPalette.vermilion.opacity(0.10))
                        .frame(width: 92, height: 92)
                        .position(
                            x: proxy.size.width * 0.72,
                            y: proxy.size.height * 0.80
                        )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An abstract calendar-orbit mark built entirely from SwiftUI shapes.
struct OrbitCalendarMark: View {
    let size: CGFloat

    init(size: CGFloat = 112) {
        self.size = max(size, 32)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(SnapCalPalette.teal)

            ForEach(1..<4, id: \.self) { index in
                Circle()
                    .stroke(
                        SnapCalPalette.paper.opacity(0.22),
                        lineWidth: max(0.75, size * 0.008)
                    )
                    .padding(size * CGFloat(index) * 0.075)
            }

            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(
                    cornerRadius: max(1.5, size * 0.022),
                    style: .continuous
                )
                .fill(SnapCalPalette.paperRaised)
                .frame(width: size * 0.17, height: size * 0.09)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(SnapCalPalette.vermilion)
                        .frame(width: size * 0.025)
                        .padding(.vertical, size * 0.017)
                        .padding(.leading, size * 0.018)
                }
                .offset(y: -size * 0.34)
                .rotationEffect(.degrees(Double(index) * 120))
            }

            Circle()
                .fill(SnapCalPalette.vermilion)
                .frame(width: size * 0.30, height: size * 0.30)

            Image(systemName: "calendar")
                .font(.system(size: size * 0.14, weight: .bold))
                .foregroundStyle(SnapCalPalette.paperRaised)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A compact editorial kicker with a vermilion seal.
struct SealLabel: View {
    let kicker: String

    init(kicker: String) {
        self.kicker = kicker
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(SnapCalPalette.vermilion)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .fill(SnapCalPalette.paperRaised.opacity(0.88))
                        .frame(width: 3, height: 3)
                }
                .accessibilityHidden(true)

            Text(kicker)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.15)
                .foregroundStyle(SnapCalPalette.inkMuted)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

/// A reusable raised paper container.
struct PaperCard<Content: View>: View {
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let content: Content

    init(
        padding: CGFloat = 20,
        cornerRadius: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .snapCalCard(cornerRadius: cornerRadius)
    }
}

/// A `GroupBoxStyle` that gives native group boxes the shared paper-card
/// treatment while preserving their labels and semantic grouping.
struct SnapCalGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.headline)
                .foregroundStyle(SnapCalPalette.ink)

            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .snapCalCard(cornerRadius: 18)
    }
}

extension View {
    /// Adds content padding and applies the shared raised-paper surface.
    func snapCalCard(
        padding: CGFloat,
        cornerRadius: CGFloat = 20,
        showsShadow: Bool = true
    ) -> some View {
        self
            .padding(padding)
            .modifier(SnapCalCardModifier(
                cornerRadius: cornerRadius,
                showsShadow: showsShadow
            ))
    }

    /// Applies the shared raised-paper surface without adding content padding.
    func snapCalCard(
        cornerRadius: CGFloat = 20,
        showsShadow: Bool = true
    ) -> some View {
        modifier(SnapCalCardModifier(
            cornerRadius: cornerRadius,
            showsShadow: showsShadow
        ))
    }
}

/// Decorative concentric ink rings. Size this view with `frame`.
struct RippleMotif: View {
    let color: Color

    init(color: Color = SnapCalPalette.teal) {
        self.color = color
    }

    var body: some View {
        Canvas { context, size in
            let shortestSide = min(size.width, size.height)
            guard shortestSide > 0 else { return }

            for index in 0..<6 {
                let inset = shortestSide * (0.045 + CGFloat(index) * 0.070)
                let verticalInset = inset * (0.88 + CGFloat(index % 2) * 0.05)
                let rect = CGRect(
                    x: inset,
                    y: verticalInset,
                    width: max(0, size.width - inset * 2),
                    height: max(0, size.height - verticalInset * 2)
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(0.10 + Double(index) * 0.018)),
                    lineWidth: index == 0 ? 1.15 : 0.8
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Decorative flowing linework. Size this view with `frame`.
struct WaveMotif: View {
    let color: Color
    let lineCount: Int

    init(
        color: Color = SnapCalPalette.teal,
        lineCount: Int = 8
    ) {
        self.color = color
        self.lineCount = max(1, lineCount)
    }

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            for index in 0..<lineCount {
                let fraction = CGFloat(index) / CGFloat(max(1, lineCount - 1))
                let startY = size.height * (0.14 + fraction * 0.58)
                let separation = size.height * (0.08 + fraction * 0.04)
                var path = Path()
                path.move(to: CGPoint(x: -size.width * 0.04, y: startY))
                path.addCurve(
                    to: CGPoint(x: size.width * 0.53, y: startY + separation),
                    control1: CGPoint(
                        x: size.width * 0.18,
                        y: startY - size.height * 0.18
                    ),
                    control2: CGPoint(
                        x: size.width * 0.36,
                        y: startY + size.height * 0.20
                    )
                )
                path.addCurve(
                    to: CGPoint(x: size.width * 1.04, y: startY - separation * 0.35),
                    control1: CGPoint(
                        x: size.width * 0.68,
                        y: startY + size.height * 0.24
                    ),
                    control2: CGPoint(
                        x: size.width * 0.86,
                        y: startY - size.height * 0.19
                    )
                )
                context.stroke(
                    path,
                    with: .color(color.opacity(0.08 + Double(index) * 0.012)),
                    lineWidth: index % 3 == 0 ? 1.1 : 0.7
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SnapCalCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    let cornerRadius: CGFloat
    let showsShadow: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        SnapCalPalette.paperRaised.opacity(
                            reduceTransparency ? 1 : 0.97
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SnapCalPalette.line.opacity(0.72), lineWidth: 1)
            }
            .shadow(
                color: showsShadow ? Color.black.opacity(0.09) : .clear,
                radius: showsShadow ? 16 : 0,
                y: showsShadow ? 8 : 0
            )
    }
}

private struct WashiFiberField: View {
    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            for index in 0..<44 {
                let seed = CGFloat(index)
                let startX = (seed * seed * 19)
                    .truncatingRemainder(dividingBy: size.width)
                let startY = (seed * 43)
                    .truncatingRemainder(dividingBy: size.height)
                let length = 22 + (seed * 17).truncatingRemainder(dividingBy: 74)
                let rise = (seed * 7).truncatingRemainder(dividingBy: 9) - 4

                var path = Path()
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(
                    x: min(size.width, startX + length),
                    y: min(size.height, max(0, startY + rise))
                ))
                context.stroke(
                    path,
                    with: .color(SnapCalPalette.ink.opacity(0.025)),
                    lineWidth: index % 5 == 0 ? 0.8 : 0.45
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
