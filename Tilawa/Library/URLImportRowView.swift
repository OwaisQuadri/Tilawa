import SwiftUI

/// A list row representing an in-progress or failed URL audio import.
struct URLImportRowView: View {

    let task: URLImportTask
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                subtitleView
            }

            Spacer(minLength: 8)

            actionButton
                .frame(width: 36, height: 36)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Subtitle

    @ViewBuilder
    private var subtitleView: some View {
        switch task.state {
        case .downloading(let progress):
            Text("Downloading… \(Int(progress * 100))%")
                .font(.subheadline)
                .foregroundStyle(.tint)
        case .failed(let error):
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch task.state {
        case .downloading(let progress):
            Button(action: onStop) {
                URLCircularProgressRing(progress: progress)
            }
            .buttonStyle(.plain)
        case .failed:
            EmptyView()
        }
    }
}

// MARK: - Circular progress ring

private struct URLCircularProgressRing: View {

    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 2)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)

            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 30, height: 30)
    }
}
