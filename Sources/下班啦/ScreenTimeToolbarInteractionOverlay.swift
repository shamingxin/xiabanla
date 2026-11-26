import SwiftUI
import AppKit

/// 使用原生标题栏承载日期控件，事件不会被窗口拖拽区截走。
/// 日期控件保持内容区的常规边距；提醒 Tab 更靠近窗口右侧，避免顶栏留白失衡。
struct SettingsToolbarTitlebarAccessory: View {
    @ObservedObject var navigation: SettingsNavigationState
    @ObservedObject var screenTimeState: ScreenTimeState
    @ObservedObject var model: WorkTimerModel

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                ScreenTimeToolbar(state: screenTimeState, currentWorkday: WorkTimerModel.workdayBase(for: model.now))
                    .opacity(navigation.selectedSection == .screenTime ? 1 : 0)
                    .allowsHitTesting(navigation.selectedSection == .screenTime)
                ReminderTabTitlebarAccessory(navigation: navigation, isDark: model.background == .dark)
            }
            .frame(width: 260, alignment: .trailing)
            Color.clear.frame(width: navigation.selectedSection == .reminderAnimations ? 10 : SettingsMetrics.contentPadding)
        }
    }
}

/// 由原生标题栏附件承载，避免窗口拖拽区截获 Tab 的点击。
struct ReminderTabTitlebarAccessory: View {
    @ObservedObject var navigation: SettingsNavigationState
    let isDark: Bool

    var body: some View {
        ReminderTabControl(
            selection: Binding(
                get: { navigation.selectedReminderTab },
                set: { navigation.selectedReminderTab = $0 }
            ),
            isDark: isDark
        )
        .opacity(navigation.selectedSection == .reminderAnimations ? 1 : 0)
        .allowsHitTesting(navigation.selectedSection == .reminderAnimations)
    }
}

/// 参考 macOS 日历的分段控件：深色毛玻璃底、选中时浮起，激活项旁不保留分隔线。
struct ReminderTabControl: View {
    @Binding var selection: ReminderTab
    let isDark: Bool
    @State private var hovering: ReminderTab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReminderTab.allCases, id: \.self) { tab in
                let selected = selection == tab
                Button { selection = tab } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(width: 68, height: 30)
                        .background(Capsule().fill(selected ? selectedFill : (hovering == tab ? hoverFill : .clear)))
                        .overlay(Capsule().strokeBorder(selected ? selectedStroke : .clear, lineWidth: 0.8))
                        .shadow(color: selected ? selectedShadow : .clear, radius: 3, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    hovering = inside ? tab : (hovering == tab ? nil : hovering)
                }
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])

                if nextTab(after: tab) != nil {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 16)
                        .opacity(shouldShowDivider(after: tab) ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(3)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(tabSurface)
        }
        .overlay(Capsule().strokeBorder(tabOuterStroke, lineWidth: 1))
        .overlay(Capsule().inset(by: 1).strokeBorder(tabInnerStroke, lineWidth: 0.6))
        .shadow(color: .black.opacity(isDark ? 0.12 : 0.06), radius: 4, y: 1)
        .animation(.easeOut(duration: 0.14), value: selection)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("提醒类别")
    }

    private var tabSurface: Color { Color.black.opacity(isDark ? 0.30 : 0.10) }
    private var tabOuterStroke: Color { Color.white.opacity(isDark ? 0.18 : 0.58) }
    private var tabInnerStroke: Color { Color.black.opacity(isDark ? 0.48 : 0.10) }
    private var selectedFill: Color { Color.white.opacity(isDark ? 0.16 : 0.48) }
    private var selectedStroke: Color { Color.white.opacity(isDark ? 0.22 : 0.72) }
    private var selectedShadow: Color { Color.black.opacity(isDark ? 0.28 : 0.12) }
    private var hoverFill: Color { Color.white.opacity(isDark ? 0.08 : 0.24) }

    private func shouldShowDivider(after tab: ReminderTab) -> Bool {
        guard let next = nextTab(after: tab) else { return false }
        return !isActive(tab) && !isActive(next)
    }

    private func isActive(_ tab: ReminderTab) -> Bool { selection == tab || hovering == tab }

    private func nextTab(after tab: ReminderTab) -> ReminderTab? {
        switch tab {
        case .water: .rest
        case .rest: .offWork
        case .offWork: nil
        }
    }
}
