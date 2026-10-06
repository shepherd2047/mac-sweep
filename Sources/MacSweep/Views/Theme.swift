import AppKit
import SwiftUI

extension Category {
    /// Two-stop gradient used for the category's icon tile; `tint` is the darker stop.
    var colors: [Color] {
        switch self {
        case .caches: [Color(red: 0.38, green: 0.70, blue: 1.00), Color(red: 0.13, green: 0.47, blue: 0.96)]
        case .orphans: [Color(red: 0.78, green: 0.52, blue: 1.00), Color(red: 0.53, green: 0.28, blue: 0.93)]
        case .apps: [Color(red: 1.00, green: 0.72, blue: 0.30), Color(red: 0.98, green: 0.47, blue: 0.16)]
        case .large: [Color(red: 0.33, green: 0.87, blue: 0.74), Color(red: 0.07, green: 0.62, blue: 0.58)]
        case .dev: [Color(red: 1.00, green: 0.50, blue: 0.62), Color(red: 0.90, green: 0.24, blue: 0.44)]
        }
    }

    var tint: Color { colors[1] }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// Rounded gradient square with a white SF Symbol, like System Settings.
struct IconTile: View {
    let symbol: String
    let gradient: LinearGradient
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: size * 0.06, y: size * 0.03)
    }
}

extension IconTile {
    init(_ c: Category, size: CGFloat = 28) {
        self.init(symbol: c.icon, gradient: c.gradient, size: size)
    }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(_ url: URL) -> NSImage {
        if let i = cache[url.path] { return i }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = i
        return i
    }
}

/// The app's real icon when there is one, otherwise a tile with a symbol for what the item is.
struct ItemIcon: View {
    let item: SweepItem
    var size: CGFloat = 34

    private var symbol: String {
        if item.id.hasPrefix("wt:") { return "arrow.triangle.branch" }
        if item.id.hasPrefix("brew:") { return "mug.fill" }
        if item.title.hasPrefix("node_modules") { return "shippingbox.fill" }
        if item.title.hasPrefix("日志") { return "doc.text.fill" }
        if item.title.contains("扩展") { return "puzzlepiece.extension.fill" }
        if item.title.contains("模型") { return "cpu.fill" }
        if item.paths.first?.pathExtension == "dmg" || item.paths.first?.pathExtension == "pkg" { return "opticaldiscdrive.fill" }
        if ["zip", "rar", "7z"].contains(item.paths.first?.pathExtension ?? "") { return "doc.zipper" }
        switch item.category {
        case .caches: return "archivebox.fill"
        case .orphans: return "questionmark.folder.fill"
        case .apps: return "app.fill"
        case .large: return "externaldrive.fill"
        case .dev: return "hammer.fill"
        }
    }

    var body: some View {
        if let url = item.iconURL {
            Image(nsImage: IconCache.icon(url))
                .resizable()
                .interpolation(.high)
                .frame(width: size + 4, height: size + 4)
        } else {
            IconTile(symbol: symbol, gradient: item.category.gradient, size: size)
                .saturation(0.85)
        }
    }
}

struct RiskBadge: View {
    let risk: Risk

    private var symbol: String {
        switch risk {
        case .safe: "checkmark.shield.fill"
        case .review: "eye.fill"
        case .careful: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        Label(risk.title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .foregroundStyle(risk.color)
            .background(risk.color.opacity(0.14), in: Capsule())
    }
}

/// Horizontal bar of rounded segments; values are fractions of the whole.
struct SegmentBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let fill: AnyShapeStyle
    }

    let segments: [Segment]
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { s in
                    Rectangle()
                        .fill(s.fill)
                        .frame(width: max(s.value > 0 ? 3 : 0, geo.size.width * s.value))
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        }
        .frame(height: height)
    }
}

/// Card surface that reads well on the window background in light and dark mode.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

extension View {
    func card(radius: CGFloat = 14) -> some View { modifier(CardBackground(radius: radius)) }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
