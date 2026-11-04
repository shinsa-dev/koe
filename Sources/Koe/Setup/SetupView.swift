import KoeCore
import SwiftUI

/// The first thing Koe shows: one row per permission, each with the one action that moves it forward.
struct SetupView: View {
    let center: PermissionCenter
    let onDone: () -> Void

    var body: some View {
        let checklist = center.checklist
        VStack(spacing: 24) {
            Hero(
                icon: .microphone,
                title: "Set up Koe",
                line: "Koe hears you and sees your screen on this Mac only. Nothing you say or capture leaves it."
            )
            Card {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(
                        permission: permission,
                        status: checklist.status(of: permission),
                        action: checklist.action(for: permission),
                        isNext: checklist.nextStep == permission,
                        perform: { perform(checklist.action(for: permission), on: permission) }
                    )
                }
            }
            VStack(spacing: 8) {
                Button("Done", action: onDone)
                    .buttonStyle(.koe(.primary, size: .large, fullWidth: true))
                    .disabled(!checklist.isReady)
                    .keyboardShortcut(.defaultAction)
                Text(checklist.isReady
                    ? "You can open this again from Koe in the menu bar."
                    : "Allow the microphone and screen recording to start.")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.fg2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 440)
        .background(Palette.canvas)
    }

    private func perform(_ action: SetupAction, on permission: Permission) {
        switch action {
        case .none: break
        case .request: center.request(permission)
        case .openSettings: center.openSettings(for: permission)
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let action: SetupAction
    let isNext: Bool
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconView(icon: permission.icon, size: .small, color: Palette.fg2)
                .padding(.top, 1)
                .frame(maxHeight: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(permission.title).font(Typography.body).foregroundStyle(Palette.fg4)
                    if !permission.isRequired {
                        Text("Optional").font(Typography.meta).foregroundStyle(Palette.fg1)
                    }
                }
                Text(detail)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        status == .denied && permission != .microphone
            ? "\(permission.detail) After you allow it in System Settings, reopen Koe."
            : permission.detail
    }

    @ViewBuilder private var trailing: some View {
        switch action {
        case .none:
            HStack(spacing: 4) {
                IconView(icon: .check, size: .small, color: Tone.green.ink)
                Text("Allowed").font(Typography.label).foregroundStyle(Tone.green.ink)
            }
            .accessibilityLabel("Allowed")
        case .request:
            Button("Allow", action: perform).buttonStyle(.koe(isNext ? .primary : .outline, size: .small))
        case .openSettings:
            Button("Open Settings", action: perform).buttonStyle(.koe(.outline, size: .small))
        }
    }
}

extension Permission {
    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .screenRecording: "Screen recording"
        case .accessibility: "Accessibility"
        }
    }

    var detail: String {
        switch self {
        case .microphone: "To transcribe what you say, on device."
        case .screenRecording: "To take screenshots and record clips while you talk."
        case .accessibility: "To paste the bundle for you when a session ends."
        }
    }

    var icon: Icon {
        switch self {
        case .microphone: .microphone
        case .screenRecording: .screenCapture
        case .accessibility: .cursorClick
        }
    }
}
