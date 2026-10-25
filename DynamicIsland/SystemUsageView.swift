import SwiftUI

/// Detailed readings under the widgets: a bar and a figure per metric.
struct SystemUsageView: View {
    let metrics: [SystemMetric]
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(spacing: IslandMetrics.usageRowSpacing) {
            ForEach(metrics) { metric in
                row(metric)
            }
        }
    }

    private func row(_ metric: SystemMetric) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: symbol(metric))
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
                Text(metric.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 62, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(.white.opacity(0.75))
                        .frame(width: max(proxy.size.width * fraction(metric), 3))
                }
            }
            .frame(height: 4)

            Text(detail(metric))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: 130, alignment: .trailing)
        }
        .frame(height: IslandMetrics.usageRowHeight)
    }

    private func symbol(_ metric: SystemMetric) -> String {
        switch metric {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        }
    }

    private func fraction(_ metric: SystemMetric) -> CGFloat {
        let value: Double
        switch metric {
        case .cpu: value = stats.cpu
        case .memory: value = stats.memoryTotal > 0 ? stats.memoryUsed / stats.memoryTotal : 0
        case .disk: value = stats.diskUsed
        }
        return CGFloat(min(max(value, 0), 1))
    }

    /// Memory shows used of total. Disk shows what is left of the whole, since that is
    /// the number that decides whether anything more fits.
    private func detail(_ metric: SystemMetric) -> String {
        switch metric {
        case .cpu:
            return "\(Int((stats.cpu * 100).rounded()))%"
        case .memory:
            return "\(gigabytes(stats.memoryUsed, binary: true)) / \(gigabytes(stats.memoryTotal, binary: true))"
        case .disk:
            return "\(gigabytes(stats.diskFree, binary: false)) left / \(gigabytes(stats.diskTotal, binary: false))"
        }
    }

    /// Memory is counted in binary gigabytes, as Activity Monitor does; disks in decimal
    /// ones, as Finder does. Terabytes once the figure gets that large.
    private func gigabytes(_ bytes: Double, binary: Bool) -> String {
        let gigabyte = binary ? 1_073_741_824.0 : 1_000_000_000.0
        let value = bytes / gigabyte
        if value >= 1000 {
            return String(format: "%.2f TB", value / (binary ? 1024 : 1000))
        }
        return String(format: value >= 100 ? "%.0f GB" : "%.1f GB", value)
    }
}
