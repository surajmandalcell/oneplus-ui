import SwiftUI

public struct OnePlusAppletTitlebar<Title: View, Actions: View>: View {
    let title: Title
    let actions: Actions
    let clearsTrafficLights: Bool
    private var titleText = ""
    @Environment(\.onePlusZoomTrailingX) private var zoomTrailingX
    @Environment(\.displayScale) private var displayScale
    public init(clearsTrafficLights: Bool = true, @ViewBuilder title: () -> Title, @ViewBuilder actions: () -> Actions) {
        self.clearsTrafficLights = clearsTrafficLights; self.title = title(); self.actions = actions()
    }
    public var body: some View {
        HStack(spacing: 8) {
            OnePlusHeaderTitleLayout(text: titleText, pointSize: OnePlusTextRole.sidebarTitle.size(for: .regular),
                                     height: 24, scale: displayScale, centersCaps: true) {
                title.onePlusText(.sidebarTitle).lineLimit(1)
            }
            Spacer(minLength: 12)
            OnePlusHeaderActions { actions }
        }
        .frame(height: OnePlusMetrics.compactControlHeight)
        .padding(.top, OnePlusMetrics.top(of: OnePlusMetrics.compactControlHeight,
                                        centerline: OnePlusMetrics.appletCenterline))
        .padding(.leading, clearsTrafficLights ? OnePlusMetrics.titleStart(afterZoom: zoomTrailingX) : 16)
        .padding(.trailing, 16).frame(height: OnePlusMetrics.appletTitlebar, alignment: .top)
        .background(OnePlusWindowDragArea())
    }
}

public extension OnePlusAppletTitlebar where Title == Text {
    init(title: String, @ViewBuilder actions: () -> Actions) {
        self.init(title: { Text(title) }, actions: actions)
        titleText = title
    }
}

/// Titlebar action that toggles an applet between its home page and its settings page.
public struct OnePlusAppletSettingsButton: View {
    let active: Bool
    let label: String
    let action: () -> Void
    @Environment(\.onePlusTimingWindow) private var timingWindow
    public init(isActive: Bool, help: String? = nil, action: @escaping () -> Void) {
        active = isActive; label = help ?? (isActive ? "Back to home" : "Settings"); self.action = action
    }
    public var body: some View {
        Button {
            if !timingWindow.isEmpty {
                OnePlusPanelTimings.shared.begin(panel: timingWindow, operation: .pageSwitch,
                                                tab: active ? "content" : "settings", input: "settings-button")
            }
            action()
        } label: {
            Image(systemName: active ? "gearshape.fill" : "gearshape")
        }
        .buttonStyle(OnePlusButtonStyle(.icon, size: .small, selected: active))
        .help(label).accessibilityLabel(label)
    }
}
