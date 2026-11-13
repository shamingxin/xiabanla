import SwiftUI
import AppKit
import AVFoundation

/// 一次只看当前自然周的轻量幸福小测验。
struct HappinessIndexView: View {
    private enum MeasurementState {
        case invitation
        case measuring(Int)
        case result(HappinessScore.WeeklySummary, HappinessPersona)
    }

    let activity: ActivityStore
    let showScreenTime: () -> Void
    @Environment(\.themeAccent) private var accent
    @Environment(\.settingsPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state: MeasurementState = .invitation
    @State private var invitation = HappinessCopy.openers.randomElement() ?? "本周的你，值得一张下班认证。"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch state {
            case .invitation:
                invitationView
            case .measuring(let step):
                measuringView(step: step)
            case .result(let summary, let persona):
                resultView(summary: summary, persona: persona)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("本周幸福指数")
    }

    private var invitationView: some View {
        VStack(spacing: 0) {
            HappinessMediaCard().frame(height: 178)
            VStack(spacing: 7) {
                Text("本周幸福指数")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(invitation)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 16)
            Button(action: startMeasurement) {
                Label("测一下本周幸福指数", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 17)
                    .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .padding(.top, 22)
            .accessibilityHint("根据本周已封存的实际在岗记录计算")
            Text("只统计已经下班的工作日；休假、漏记和今天都不算。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 22)
    }

    private func measuringView(step: Int) -> some View {
        VStack(spacing: 0) {
            HappinessMediaCard().frame(height: 178)
            VStack(spacing: 8) {
                Text("正在认真测量中")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(HappinessCopy.loading[step])
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .padding(.top, 16)
            ProgressView(value: Double(step + 1), total: Double(HappinessCopy.loading.count))
                .tint(accent)
                .frame(width: 210)
                .padding(.top, 18)
                .accessibilityLabel("幸福指数测量进度")
            Text("本周数据只会留在这台 Mac 上。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 13)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 22)
    }

    private func resultView(summary: HappinessScore.WeeklySummary, persona: HappinessPersona) -> some View {
        VStack(spacing: 16) {
            HappinessResultCard(summary: summary, persona: persona, scheme: scheme)
            HStack(spacing: 10) {
                Button("再测一次") { reroll(summary: summary, current: persona) }
                    .buttonStyle(.bordered)
                Button("查看本周在岗", action: showScreenTime)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            Text("测验只换一句话，不会偷偷篡改你的加班记录。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func startMeasurement() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: weekday == 1 ? -6 : 2 - weekday, to: today)!
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let summary = HappinessScore.weeklySummary(sessions: activity.completedOfficeSessions(from: formatter.string(from: monday), through: formatter.string(from: sunday)))
        withAnimation(reduceMotion ? .linear(duration: 0.15) : .spring(duration: 0.35)) { state = .measuring(0) }
        for (step, delay) in [(1, 0.65), (2, 1.3)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard case .measuring = state else { return }
                withAnimation(reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.25)) { state = .measuring(step) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard case .measuring = state else { return }
            withAnimation(reduceMotion ? .linear(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2)) {
                state = .result(summary, HappinessPersona.allCases.randomElement() ?? .gentle)
            }
        }
    }

    private func reroll(summary: HappinessScore.WeeklySummary, current: HappinessPersona) {
        let choices = HappinessPersona.allCases.filter { $0 != current }
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.3, bounce: 0.25)) {
            state = .result(summary, choices.randomElement() ?? current)
        }
    }
}

private enum HappinessPersona: CaseIterable {
    case gentle, spicy, calm
}

private enum HappinessCopy {
    static let openers = [
        "本周的你，值得一张下班认证。",
        "别紧张，只测工时，不测人生。",
        "收集一下这周被工作偷走的时间。"
    ]
    static let loading = ["正在翻看本周下班记录…", "正在计算被加班偷走的时间…", "正在生成你的幸福小卡…"]
}

private struct HappinessResultCard: View {
    let summary: HappinessScore.WeeklySummary
    let persona: HappinessPersona
    let scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("XIABANLA\nWEEKLY REPORT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.66))
                    .tracking(0.5)
                Spacer()
                Text("THIS WEEK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(ink.opacity(0.56))
            }
            .padding(.bottom, 8)

            if let score = summary.score {
                Text("本周幸福指数")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.72))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(score)")
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                    Text(summary.tier ?? "")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(ink.opacity(0.11)))
                        .foregroundStyle(ink)
                }
                .padding(.bottom, 11)
                HStack(spacing: 0) {
                    HappinessMetric(title: "参与天数", value: "\(summary.days.count) 天", ink: ink)
                    HappinessMetric(title: "准时下班", value: "\(summary.onTimeDays) 天", ink: ink)
                    HappinessMetric(title: "加班时间", value: duration(summary.overtimeSeconds), ink: ink)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.16)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.16)).frame(height: 1) }
                Text(personaText)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 15)
            } else {
                Text("本周还没有\n可测量的幸福记录")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.top, 6)
                Text("等某个工作日下班并封存记录后，再来抽这张卡。")
                    .font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.72))
                    .padding(.top, 10)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(scheme == .dark ? Color(red: 0.21, green: 0.20, blue: 0.17) : Color(red: 0.96, green: 0.92, blue: 0.82))
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(ink.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.12), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.score.map { "本周幸福指数 \($0) 分" } ?? "本周没有可测量的幸福记录")
    }

    private var ink: Color { scheme == .dark ? Color(red: 0.97, green: 0.92, blue: 0.80) : Color(red: 0.13, green: 0.16, blue: 0.19) }
    private var personaText: String {
        switch persona {
        case .gentle: return "准时下班不是偷懒，是把生活还给自己。"
        case .spicy: return summary.overtimeSeconds == 0 ? "公司这周没能占用你的夜晚，继续保持。" : "公司拿走了一点时间，但还没拿走你的周末。"
        case .calm: return "本周 \(summary.days.count) 个有效工作日中，\(summary.onTimeDays) 天未超过计划工时。"
        }
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes == 0 ? "0 分钟" : "\(minutes / 60)小时\(minutes % 60)分"
    }
}

private struct HappinessMetric: View {
    let title: String; let value: String; let ink: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(ink.opacity(0.62))
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(ink).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HappinessMediaCard: View {
    var body: some View {
        HappinessVideoView()
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            .accessibilityLabel("幸福指数循环视频")
    }
}

/// 独立于提醒气泡播放器：仅用于设置页，并永久静音循环。
private struct HappinessVideoView: NSViewRepresentable {
    func makeNSView(context: Context) -> HappinessVideoHost { HappinessVideoHost() }
    func updateNSView(_ nsView: HappinessVideoHost, context: Context) { nsView.playIfVisible() }
}

private final class HappinessVideoHost: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        guard let url = Bundle.main.url(forResource: "幸福指数", withExtension: "mp4", subdirectory: "Videos/幸福指数") else { return }
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        let videoLayer = AVPlayerLayer(player: player)
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer = videoLayer
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        playIfVisible()
    }

    func playIfVisible() { window == nil ? player.pause() : player.play() }
    deinit { player.pause() }
}
