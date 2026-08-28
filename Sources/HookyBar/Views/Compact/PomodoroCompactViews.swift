import SwiftUI

struct PomodoroCompactTime: View {
    let remaining: TimeInterval

    var body: some View {
        Text(formatted)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
    }

    private var formatted: String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct PomodoroCompactProgress: View {
    let progress: Double
    let running: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: running ? "flame.fill" : "pause.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(running ? Color.red : Color.white.opacity(0.65))
        }
        .frame(width: 20, height: 20)
    }
}
