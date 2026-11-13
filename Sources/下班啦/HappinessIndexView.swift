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
            HappinessResultCard(summary: summary, persona: persona)
            HStack(spacing: 10) {
                Button("再测一次") { reroll(summary: summary, current: persona) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.18 : 0.10)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                    .buttonStyle(.plain)
                Button("查看本周在岗", action: showScreenTime)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent.contrastingText)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(accent))
                    .buttonStyle(.plain)
            }
            .frame(maxWidth: 440)
            Text("重新测量只换一句话，不会偷偷篡改你的加班记录。")
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
        runMeasurement(summary: summary)
    }

    private func runMeasurement(summary: HappinessScore.WeeklySummary, persona: HappinessPersona? = nil) {
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
                state = .result(summary, persona ?? HappinessPersona.allCases.randomElement() ?? .gentle)
            }
        }
    }

    private func reroll(summary: HappinessScore.WeeklySummary, current: HappinessPersona) {
        let choices = HappinessPersona.allCases.filter { $0 != current }
        let nextPersona = choices.randomElement() ?? current
        runMeasurement(summary: summary, persona: nextPersona)
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

/// 将既有 0–100 的幸福分数转换为只用于展示的半星评级。
private func starRating(for score: Int) -> Double {
    (min(100, max(0, Double(score))) / 20 * 2).rounded() / 2
}

private struct HappinessResultCard: View {
    let summary: HappinessScore.WeeklySummary
    let persona: HappinessPersona

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let score = summary.score {
                HappinessVideoView()
                    .frame(height: 156)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            HandDrawnStar(
                                fillAmount: starFill(at: index, rating: starRating(for: score)),
                                tilt: [-0.08, 0.04, -0.03, 0.07, -0.05][index]
                            )
                            .frame(width: 27, height: 27)
                        }
                    }
                    .accessibilityLabel("\(starRating(for: score), specifier: "%.1f") 星评分")

                    Text("本周幸福指数")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.70))
                        .padding(.top, 12)
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text("\(score)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                            .monospacedDigit()
                        Text("分")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ink.opacity(0.74))
                            .padding(.bottom, 10)
                        Text(summary.tier ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .foregroundStyle(ink)
                            .padding(.bottom, 10)
                    }
                    .padding(.top, 2)
                    HStack(spacing: 10) {
                        HappinessMetric(title: "参与天数", value: "\(summary.days.count) 天", ink: ink)
                        HappinessMetric(title: "准时下班", value: "\(summary.onTimeDays) 天", ink: ink)
                        HappinessMetric(title: "加班时间", value: duration(summary.overtimeSeconds), ink: ink)
                    }
                    .padding(.top, 14)
                    Text(personaText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)
                }
                .padding(.top, 16)
            } else {
                Text("本周还没有\n可测量的幸福记录")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text("等某个工作日下班并封存记录后，再来抽这张卡。")
                    .font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.72))
                    .padding(.top, 10)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.15))
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.score.map { "本周幸福指数 \($0) 分" } ?? "本周没有可测量的幸福记录")
    }

    private var ink: Color { Color(red: 0.95, green: 0.96, blue: 0.98) }
    private func starFill(at index: Int, rating: Double) -> CGFloat {
        min(1, max(0, rating - Double(index)))
    }
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

/// 模拟手帐卡上的涂鸦星星：不规则轮廓、紫色描边与半填充评分。
private struct HandDrawnStar: View {
    let fillAmount: CGFloat
    let tilt: CGFloat

    private let fill = Color(red: 1.0, green: 0.78, blue: 0.28)
    private let outline = Color(red: 0.42, green: 0.29, blue: 0.72)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SketchStar(tilt: tilt).fill(fill.opacity(0.12))
                SketchStar(tilt: tilt)
                    .fill(fill)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: proxy.size.width * fillAmount)
                    }
                SketchStar(tilt: tilt).stroke(outline, lineWidth: 2.1)
            }
        }
    }
}

private struct SketchStar: Shape {
    let tilt: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * 0.46
        let innerRadius = outerRadius * 0.44
        let wobble: [CGFloat] = [1.0, 0.96, 1.06, 0.91, 0.98, 1.04, 0.94, 1.02, 0.92, 1.0]
        var path = Path()

        for point in 0..<10 {
            let radius = (point.isMultiple(of: 2) ? outerRadius : innerRadius) * wobble[point]
            let angle = -.pi / 2 + CGFloat(point) * .pi / 5 + tilt * (point.isMultiple(of: 2) ? 1 : 0.45)
            let location = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            point == 0 ? path.move(to: location) : path.addLine(to: location)
        }
        path.closeSubpath()
        return path
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
