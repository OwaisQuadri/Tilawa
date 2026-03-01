import SwiftUI

/// A list row representing an in-progress or failed YouTube audio import.
///
/// Layout mirrors the YouTube Downloads UI:
/// - Left: title + coloured status subtitle (no icon/thumbnail)
/// - Right: circular progress ring with stop button (downloading), nothing when failed
struct YouTubeImportRowView: View {

    let task: YouTubeImportTask
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Title + subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(task.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                subtitleView
            }

            Spacer(minLength: 8)

            // Action button
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
                CircularProgressRing(progress: progress)
            }
            .buttonStyle(.plain)
        case .failed:
            EmptyView()
        }
    }
}

// MARK: - Circular progress ring

/// A thin circular ring that fills clockwise from 12 o'clock, with a stop icon in the centre.
private struct CircularProgressRing: View {

    let progress: Double

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 2)

            // Fill arc
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)

            // Stop icon
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 30, height: 30)
    }
}
