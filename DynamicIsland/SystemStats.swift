import Combine
import Darwin
import Foundation

/// Readings for the collapsed pill's side slots. Deliberately cheap: two `host_statistics`
/// calls and one filesystem query every couple of seconds.
@MainActor
final class SystemStats: ObservableObject {
    /// 0...1, averaged across cores since the previous sample.
    @Published private(set) var cpu: Double = 0
    /// Bytes in use: active, wired and compressed pages.
    @Published private(set) var memoryUsed: Double = 0
    /// 0...1 of the boot volume.
    @Published private(set) var diskUsed: Double = 0
    /// Boot volume capacity and what is still available, in bytes. Available counts what
    /// the system can reclaim, which is the figure Finder shows.
    @Published private(set) var diskTotal: Double = 0
    @Published private(set) var diskFree: Double = 0

    let memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)

    private static let interval: TimeInterval = 2

    private var timer: Timer?
    private var previousTicks: (busy: UInt64, total: UInt64)?

    func start() {
        guard timer == nil else { return }
        sample()

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        if let value = sampleCPU() { cpu = value }
        if let value = sampleMemory() { memoryUsed = value }
        sampleDisk()
    }

    /// CPU load is the delta of the tick counters, so the first sample has nothing to
    /// compare against and reports nothing.
    private func sampleCPU() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
            / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // cpu_ticks: user, system, idle, nice.
        let busy = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.1) + UInt64(info.cpu_ticks.3)
        let total = busy + UInt64(info.cpu_ticks.2)

        defer { previousTicks = (busy, total) }
        guard let previous = previousTicks, total > previous.total else { return nil }

        return Double(busy - previous.busy) / Double(total - previous.total)
    }

    private func sampleMemory() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
            / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pages = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        return pages * Double(vm_kernel_page_size)
    }

    private func sampleDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage,
              total > 0 else { return }

        diskTotal = Double(total)
        diskFree = Double(free)
        diskUsed = 1 - Double(free) / Double(total)
    }
}
