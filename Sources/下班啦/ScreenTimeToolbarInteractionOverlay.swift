import SwiftUI

/// 使用原生标题栏承载日期控件，事件不会被窗口拖拽区截走。
/// 尾部保留与内容区相同的内边距，因此视觉位置和原设置页一致。
struct ScreenTimeToolbarTitlebarAccessory: View {
    @ObservedObject var navigation: SettingsNavigationState
    @ObservedObject var screenTimeState: ScreenTimeState

    var body: some View {
        HStack(spacing: 0) {
            ScreenTimeToolbar(state: screenTimeState)
            Color.clear.frame(width: SettingsMetrics.contentPadding)
        }
        .opacity(navigation.selectedSection == .screenTime ? 1 : 0)
        .allowsHitTesting(navigation.selectedSection == .screenTime)
    }
}
