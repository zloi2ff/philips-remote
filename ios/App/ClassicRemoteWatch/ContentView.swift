import SwiftUI
import WatchKit

// MARK: - Design Tokens

private enum WatchDesign {
    static let volUpColor   = Color(red: 0.18, green: 0.72, blue: 0.45)  // green
    static let volDownColor = Color(red: 0.18, green: 0.72, blue: 0.45)  // green
    static let muteColor    = Color(red: 0.98, green: 0.62, blue: 0.11)  // amber
    static let powerColor   = Color(red: 0.86, green: 0.22, blue: 0.18)  // red
    static let cornerRadius: CGFloat = 14
}

// MARK: - Remote Button

private struct RemoteButton: View {
    let icon: String
    let label: String
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: WatchDesign.cornerRadius)
                .fill(Color.white.opacity(0.07))
        )
    }
}

// MARK: - Status Overlay

private struct StatusOverlay: View {
    let isSending: Bool
    let lastSuccess: Bool
    let lastError: String?

    var body: some View {
        Group {
            if isSending {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.8)
            } else if lastSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if let error = lastError {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSending)
        .animation(.easeInOut(duration: 0.2), value: lastSuccess)
        .animation(.easeInOut(duration: 0.2), value: lastError)
    }
}

// MARK: - Not Configured View

private struct NotConfiguredView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Open iPhone app\nto configure")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WebSocket Brand View

private struct WebSocketBrandView: View {
    let brandName: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.orange)
            Text("\(brandName)\nnot supported on Watch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Use iPhone app")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var controller = TvController()

    var body: some View {
        Group {
            if controller.config == nil {
                NotConfiguredView()
            } else if let cfg = controller.config, cfg.isWebSocketOnly {
                WebSocketBrandView(brandName: cfg.displayBrand)
            } else {
                remoteView
            }
        }
        .onAppear {
            controller.reload()
        }
    }

    // MARK: Remote Grid

    private var remoteView: some View {
        GeometryReader { geo in
            VStack(spacing: 6) {
                // Brand label
                HStack(spacing: 4) {
                    Image(systemName: "tv")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text((controller.config?.displayBrand ?? "").uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(1.5)
                }

                // Status area — fixed height to prevent layout jumps
                ZStack {
                    Color.clear
                    StatusOverlay(
                        isSending: controller.isSending,
                        lastSuccess: controller.lastSuccess,
                        lastError: controller.lastError
                    )
                }
                .frame(height: 22)

                // 2x2 button grid
                let buttonSize = (geo.size.width - 14) / 2  // 6px gap + 2*4px padding

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        RemoteButton(
                            icon: "speaker.plus.fill",
                            label: "VOL +",
                            accentColor: WatchDesign.volUpColor
                        ) {
                            controller.send("VolumeUp")
                        }
                        .frame(width: buttonSize, height: buttonSize)

                        RemoteButton(
                            icon: "speaker.minus.fill",
                            label: "VOL -",
                            accentColor: WatchDesign.volDownColor
                        ) {
                            controller.send("VolumeDown")
                        }
                        .frame(width: buttonSize, height: buttonSize)
                    }

                    HStack(spacing: 6) {
                        RemoteButton(
                            icon: "speaker.slash.fill",
                            label: "MUTE",
                            accentColor: WatchDesign.muteColor
                        ) {
                            controller.send("Mute")
                        }
                        .frame(width: buttonSize, height: buttonSize)

                        RemoteButton(
                            icon: "power",
                            label: "POWER",
                            accentColor: WatchDesign.powerColor
                        ) {
                            controller.send("Standby")
                        }
                        .frame(width: buttonSize, height: buttonSize)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Previews

#Preview("Configured — Philips") {
    ContentView()
}

#Preview("Not Configured") {
    NotConfiguredView()
}

#Preview("Samsung (unsupported)") {
    WebSocketBrandView(brandName: "Samsung")
}
