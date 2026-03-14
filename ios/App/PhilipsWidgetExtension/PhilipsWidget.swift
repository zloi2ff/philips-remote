import WidgetKit
import SwiftUI
import AppIntents

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

// MARK: - Timeline Entry

struct PhilipsEntry: TimelineEntry {
    let date: Date
    let tvIp: String?
    let isConfigured: Bool
}

// MARK: - Timeline Provider

struct PhilipsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhilipsEntry {
        PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true)
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
        return PhilipsEntry(
            date: .now,
            tvIp: ip,
            isConfigured: !(ip ?? "").isEmpty
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

// MARK: - Header

private struct WidgetHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tv")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Design.accent)
            Text("PHILIPS REMOTE")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
    }
}

// MARK: - Small Widget (2x2 grid)

private struct SmallWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            WidgetHeader()

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
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                WidgetHeader()
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

// MARK: - Widget Entry View (size-aware)

struct PhilipsWidgetEntryView: View {
    let entry: PhilipsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if !entry.isConfigured {
                NotConfiguredView()
            } else {
                switch family {
                case .systemMedium:
                    MediumWidgetView()
                default:
                    SmallWidgetView()
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
        .configurationDisplayName("Philips TV Remote")
        .description("Control volume and power from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true)
    PhilipsEntry(date: .now, tvIp: nil, isConfigured: false)
}

#Preview("Medium", as: .systemMedium) {
    PhilipsWidget()
} timeline: {
    PhilipsEntry(date: .now, tvIp: "192.168.1.100", isConfigured: true)
    PhilipsEntry(date: .now, tvIp: nil, isConfigured: false)
}
