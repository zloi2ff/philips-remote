import WidgetKit
import SwiftUI
import AppIntents

#if canImport(Controls)
import Controls
#endif

// MARK: - Design Tokens

private enum Design {
    // Legacy dark theme colors (pre-iOS 26 fallback)
    static let bgPrimary    = Color(red: 0, green: 0, blue: 0)
    static let bgSecondary  = Color(red: 0.071, green: 0.071, blue: 0.102)
    static let btnFrom      = Color(red: 0.102, green: 0.102, blue: 0.157)
    static let btnTo        = Color(red: 0.071, green: 0.071, blue: 0.102)
    static let accent       = Color(red: 0.204, green: 0.596, blue: 0.859)
    static let powerFrom    = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let powerTo      = Color(red: 0.588, green: 0.125, blue: 0.125)
    static let textPrimary  = Color.white
    static let textSecondary = Color(white: 0.533)
    static let textMuted    = Color(white: 0.333)
    static let border       = Color.white.opacity(0.08)
    static let cornerRadius: CGFloat = 12

    // App Group
    static let appGroupID   = "group.com.philips.remote"
}

// MARK: - Brand Metadata
//
// Maps the lowercase brand key stored in UserDefaults to a display name and SF Symbol.
// Kept inside an enum namespace to satisfy AppIntentsSSUTraining build requirements.

private enum BrandInfo {
    struct Meta {
        let displayName: String
        let icon: String    // SF Symbol name
    }

    static func meta(for brand: String) -> Meta {
        switch brand.lowercased() {
        case "philips":  return Meta(displayName: "Philips",  icon: "tv")
        case "sony":     return Meta(displayName: "Sony",     icon: "tv")
        case "samsung":  return Meta(displayName: "Samsung",  icon: "tv")
        case "lg":       return Meta(displayName: "LG",       icon: "tv")
        case "tcl":      return Meta(displayName: "TCL",      icon: "tv")
        case "hisense":  return Meta(displayName: "Hisense",  icon: "tv")
        case "xiaomi":   return Meta(displayName: "Xiaomi",   icon: "tv")
        default:         return Meta(displayName: "Classic",  icon: "tv")
        }
    }
}

// MARK: - Timeline Entry

struct PhilipsEntry: TimelineEntry {
    let date: Date
    let tvIp: String?
    let isConfigured: Bool
    let tvBrand: String     // lowercase brand key, e.g. "philips", "sony"
}

// MARK: - Timeline Provider

struct PhilipsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhilipsEntry {
        PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true, tvBrand: "philips")
    }

    func getSnapshot(in context: Context, completion: @escaping (PhilipsEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhilipsEntry>) -> Void) {
        let entry = makeEntry()
        // .never: config changes trigger reloadAllTimelines() from TvConfigHandler — no periodic refresh needed
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func makeEntry() -> PhilipsEntry {
        let defaults = UserDefaults(suiteName: Design.appGroupID)
        let ip = defaults?.string(forKey: "tvIp")
        let brand = (defaults?.string(forKey: "tvBrand") ?? "philips").lowercased()
        return PhilipsEntry(
            date: .now,
            tvIp: ip,
            isConfigured: !(ip ?? "").isEmpty,
            tvBrand: brand
        )
    }
}

// MARK: - Liquid Glass Button (iOS 26+)

@available(iOS 26.0, *)
private struct GlassButtonView<Intent: AppIntent>: View {
    let icon: String
    let label: String
    let intent: Intent
    let isPower: Bool
    let showLabel: Bool

    init(icon: String, label: String, intent: Intent, isPower: Bool = false, showLabel: Bool = false) {
        self.icon = icon
        self.label = label
        self.intent = intent
        self.isPower = isPower
        self.showLabel = showLabel
    }

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: showLabel ? 24 : 29, weight: .semibold))
                    .foregroundStyle(isPower ? .red : .primary)
                if showLabel {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Design.cornerRadius)
                    .glassEffect(.regular.tint(isPower ? .red.opacity(0.25) : .clear))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy Button (pre-iOS 26)

private struct LegacyButtonView<Intent: AppIntent>: View {
    let icon: String
    let label: String
    let intent: Intent
    let isPower: Bool
    let showLabel: Bool

    init(icon: String, label: String, intent: Intent, isPower: Bool = false, showLabel: Bool = false) {
        self.icon = icon
        self.label = label
        self.intent = intent
        self.isPower = isPower
        self.showLabel = showLabel
    }

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: showLabel ? 24 : 29, weight: .semibold))
                    .foregroundStyle(isPower ? .white : Design.accent)
                if showLabel {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isPower ? .white.opacity(0.9) : Design.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Design.cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: isPower
                                ? [Design.powerFrom, Design.powerTo]
                                : [Design.btnFrom, Design.btnTo],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.cornerRadius)
                    .strokeBorder(isPower ? Color.clear : Design.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Design.cornerRadius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Unified Button (dispatches by OS version)

private struct TvButtonView<Intent: AppIntent>: View {
    let icon: String
    let label: String
    let intent: Intent
    let isPower: Bool
    let showLabel: Bool

    init(icon: String, label: String, intent: Intent, isPower: Bool = false, showLabel: Bool = false) {
        self.icon = icon
        self.label = label
        self.intent = intent
        self.isPower = isPower
        self.showLabel = showLabel
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassButtonView(icon: icon, label: label, intent: intent, isPower: isPower, showLabel: showLabel)
        } else {
            LegacyButtonView(icon: icon, label: label, intent: intent, isPower: isPower, showLabel: showLabel)
        }
    }
}

// MARK: - "Not Configured" placeholder

private struct NotConfiguredView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv.slash")
                .font(.system(size: 28))
                .foregroundStyle(Design.accent)
            Text("Open app to configure")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unsupported Brand (WebSocket-only: Samsung, LG)

private struct UnsupportedBrandView: View {
    let brand: String

    private var brandName: String { BrandInfo.meta(for: brand).displayName }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(Design.accent)
            Text("Widget not available for \(brandName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Design.textSecondary)
                .multilineTextAlignment(.center)
            Text("Use the app instead")
                .font(.system(size: 10))
                .foregroundStyle(Design.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Header

private struct WidgetHeader: View {
    let brand: String   // lowercase brand key

    private var meta: BrandInfo.Meta { BrandInfo.meta(for: brand) }

    /// "CLASSIC REMOTE · PHILIPS", "CLASSIC REMOTE · SONY", etc.
    private var title: String { "CLASSIC REMOTE · \(meta.displayName.uppercased())" }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: meta.icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Design.accent)
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
    }
}

// MARK: - Small Widget (2x2 grid)

private struct SmallWidgetView: View {
    let brand: String

    var body: some View {
        VStack(spacing: 6) {
            WidgetHeader(brand: brand)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                TvButtonView(icon: "speaker.plus.fill",  label: "Vol +",   intent: VolumeUpIntent())
                TvButtonView(icon: "speaker.minus.fill", label: "Vol -",   intent: VolumeDownIntent())
                TvButtonView(icon: "speaker.slash.fill", label: "Mute",    intent: MuteIntent())
                TvButtonView(icon: "power",              label: "Standby", intent: StandbyIntent(), isPower: true)
            }
        }
        .padding(6)
    }
}

// MARK: - Medium Widget (horizontal row with labels)

private struct MediumWidgetView: View {
    let brand: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                WidgetHeader(brand: brand)
                Spacer()
            }

            HStack(spacing: 8) {
                TvButtonView(icon: "speaker.plus.fill",  label: "Vol +",   intent: VolumeUpIntent(),   showLabel: true)
                TvButtonView(icon: "speaker.minus.fill", label: "Vol -",   intent: VolumeDownIntent(), showLabel: true)
                TvButtonView(icon: "speaker.slash.fill", label: "Mute",    intent: MuteIntent(),       showLabel: true)
                TvButtonView(icon: "power",              label: "Standby", intent: StandbyIntent(),    isPower: true, showLabel: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Accessory Circular (Lock Screen — single Power button)

private struct AccessoryCircularView: View {
    var body: some View {
        Button(intent: StandbyIntent()) {
            Image(systemName: "power")
                .font(.system(size: 24, weight: .semibold))
                .widgetAccentable()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accessory Rectangular (Lock Screen — 4 buttons in a row)

private struct AccessoryRectangularView: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: VolumeUpIntent()) {
                Image(systemName: "speaker.plus.fill")
                    .font(.system(size: 16, weight: .medium))
                    .widgetAccentable()
            }
            .buttonStyle(.plain)

            Button(intent: VolumeDownIntent()) {
                Image(systemName: "speaker.minus.fill")
                    .font(.system(size: 16, weight: .medium))
                    .widgetAccentable()
            }
            .buttonStyle(.plain)

            Button(intent: MuteIntent()) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 16, weight: .medium))
                    .widgetAccentable()
            }
            .buttonStyle(.plain)

            Button(intent: StandbyIntent()) {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .medium))
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Accessory Inline (Lock Screen — text with icon)

private struct AccessoryInlineView: View {
    var body: some View {
        Label("Classic Remote", systemImage: "tv")
    }
}

// MARK: - Widget Entry View (size-aware)

struct PhilipsWidgetEntryView: View {
    let entry: PhilipsEntry

    @Environment(\.widgetFamily) private var family

    private var isWebSocketBrand: Bool {
        entry.tvBrand == "samsung" || entry.tvBrand == "lg"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                AccessoryCircularView()
            case .accessoryRectangular:
                AccessoryRectangularView()
            case .accessoryInline:
                AccessoryInlineView()
            default:
                if !entry.isConfigured {
                    NotConfiguredView()
                } else if isWebSocketBrand {
                    UnsupportedBrandView(brand: entry.tvBrand)
                } else {
                    switch family {
                    case .systemMedium:
                        MediumWidgetView(brand: entry.tvBrand)
                    default:
                        SmallWidgetView(brand: entry.tvBrand)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget Bundle Entry Point

@main
struct PhilipsWidgetBundle: WidgetBundle {
    var body: some Widget {
        PhilipsWidget()
        if #available(iOS 18.0, *) {
            VolumeUpControl()
            VolumeDownControl()
            MuteControl()
            PowerControl()
        }
    }
}

// MARK: - Control Center Controls (iOS 18+)

@available(iOS 18.0, *)
struct VolumeUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "VolumeUpControl") {
            ControlWidgetButton(action: VolumeUpIntent()) {
                Label("Volume Up", systemImage: "speaker.plus.fill")
            }
        }
        .displayName("Volume Up")
        .description("Increase TV volume.")
    }
}

@available(iOS 18.0, *)
struct VolumeDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "VolumeDownControl") {
            ControlWidgetButton(action: VolumeDownIntent()) {
                Label("Volume Down", systemImage: "speaker.minus.fill")
            }
        }
        .displayName("Volume Down")
        .description("Decrease TV volume.")
    }
}

@available(iOS 18.0, *)
struct MuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "MuteControl") {
            ControlWidgetButton(action: MuteIntent()) {
                Label("Mute", systemImage: "speaker.slash.fill")
            }
        }
        .displayName("Mute")
        .description("Mute TV audio.")
    }
}

@available(iOS 18.0, *)
struct PowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "PowerControl") {
            ControlWidgetButton(action: StandbyIntent()) {
                Label("Power", systemImage: "power")
            }
        }
        .displayName("Power")
        .description("Turn TV off (standby).")
    }
}

// MARK: - Widget Configuration

struct PhilipsWidget: Widget {
    let kind = "PhilipsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PhilipsProvider()) { entry in
            if #available(iOS 26.0, *) {
                PhilipsWidgetEntryView(entry: entry)
                    .containerBackground(.ultraThinMaterial, for: .widget)
            } else {
                PhilipsWidgetEntryView(entry: entry)
                    .containerBackground(Design.bgPrimary, for: .widget)
            }
        }
        .configurationDisplayName("Classic Remote")
        .description("Control volume and power from Home Screen or Lock Screen.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Previews

#Preview("Small – Philips", as: .systemSmall) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true,  tvBrand: "philips")
    PhilipsEntry(date: .now, tvIp: nil,             isConfigured: false, tvBrand: "philips")
}

#Preview("Small – Sony", as: .systemSmall) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.101", isConfigured: true, tvBrand: "sony")
}

#Preview("Medium – TCL", as: .systemMedium) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.102", isConfigured: true, tvBrand: "tcl")
}

#Preview("Medium – Philips", as: .systemMedium) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true,  tvBrand: "philips")
    PhilipsEntry(date: .now, tvIp: nil,             isConfigured: false, tvBrand: "philips")
}

#Preview("Circular – Power", as: .accessoryCircular) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true, tvBrand: "philips")
}

#Preview("Rectangular – Controls", as: .accessoryRectangular) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true, tvBrand: "philips")
}

#Preview("Inline", as: .accessoryInline) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true, tvBrand: "philips")
}
