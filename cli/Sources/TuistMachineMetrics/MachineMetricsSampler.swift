#if os(macOS)
    import Darwin
    import FileSystem
    import Foundation
    import IOKit
    import Path
    @preconcurrency import TSCBasic
    import TuistEnvironment

    public struct MachineMetricsSampler: Sendable {
        private let metricsFilePath: Path.AbsolutePath
        private let fileLock: TSCBasic.FileLock
        private let fileSystem: FileSysteming
        private let interval: Duration

        public init(
            metricsFilePath: Path.AbsolutePath? = nil,
            interval: Duration = .seconds(1),
            fileSystem: FileSysteming = FileSystem()
        ) {
            let resolvedPath = metricsFilePath ?? MachineMetricsReader.metricsFilePath
            self.metricsFilePath = resolvedPath
            self.interval = interval
            self.fileSystem = fileSystem
            // swiftlint:disable:next force_try
            fileLock = TSCBasic.FileLock(at: try! TSCBasic.AbsolutePath(validating: resolvedPath.pathString + ".lock"))
        }

        public func run() async throws {
            var previousCPUTicks = cpuTicks()
            var previousNetworkBytes = networkBytes()
            var previousDiskBytes = diskBytes()
            var sampleCount = 0

            while !Task.isCancelled {
                try await Task.sleep(for: interval)

                let currentCPUTicks = cpuTicks()
                let currentNetworkBytes = networkBytes()
                let currentDiskBytes = diskBytes()

                let cpuUsage = calculateCPUUsage(previous: previousCPUTicks, current: currentCPUTicks)
                let memory = memoryInfo()

                let sample = MachineMetricSample(
                    timestamp: Date().timeIntervalSince1970,
                    cpuUsagePercent: cpuUsage,
                    memoryUsedBytes: memory.used,
                    memoryTotalBytes: memory.total,
                    networkBytesIn: max(0, currentNetworkBytes.bytesIn - previousNetworkBytes.bytesIn),
                    networkBytesOut: max(0, currentNetworkBytes.bytesOut - previousNetworkBytes.bytesOut),
                    diskBytesRead: max(0, currentDiskBytes.bytesRead - previousDiskBytes.bytesRead),
                    diskBytesWritten: max(0, currentDiskBytes.bytesWritten - previousDiskBytes.bytesWritten)
                )

                previousCPUTicks = currentCPUTicks
                previousNetworkBytes = currentNetworkBytes
                previousDiskBytes = currentDiskBytes

                try await appendSample(sample)

                sampleCount += 1
                if sampleCount % 60 == 0 {
                    try await trimSamples()
                }
            }
        }

        private struct CPUTicks {
            let user: UInt32
            let system: UInt32
            let idle: UInt32
            let nice: UInt32
        }

        private func cpuTicks() -> CPUTicks {
            var loadInfo = host_cpu_load_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
            let hostPort = mach_host_self()
            let result = withUnsafeMutablePointer(to: &loadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
                }
            }
            mach_port_deallocate(mach_task_self_, hostPort)
            guard result == KERN_SUCCESS else {
                return CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
            }
            return CPUTicks(
                user: loadInfo.cpu_ticks.0,
                system: loadInfo.cpu_ticks.1,
                idle: loadInfo.cpu_ticks.2,
                nice: loadInfo.cpu_ticks.3
            )
        }

        private func calculateCPUUsage(previous: CPUTicks, current: CPUTicks) -> Double {
            let userDelta = Double(current.user &- previous.user)
            let systemDelta = Double(current.system &- previous.system)
            let idleDelta = Double(current.idle &- previous.idle)
            let niceDelta = Double(current.nice &- previous.nice)
            let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
            guard totalDelta > 0 else { return 0 }
            return ((userDelta + systemDelta + niceDelta) / totalDelta) * 100.0
        }

        private struct MemoryInfo {
            let used: Int
            let total: Int
        }

        private func memoryInfo() -> MemoryInfo {
            var vmStats = vm_statistics64_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
            let hostPort = mach_host_self()
            let result = withUnsafeMutablePointer(to: &vmStats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
                }
            }
            mach_port_deallocate(mach_task_self_, hostPort)

            let totalMemory = Int(ProcessInfo.processInfo.physicalMemory)
            guard result == KERN_SUCCESS else {
                return MemoryInfo(used: 0, total: totalMemory)
            }

            let pageSize = Int(vm_kernel_page_size)
            let active = Int(vmStats.active_count) * pageSize
            let wired = Int(vmStats.wire_count) * pageSize
            let compressed = Int(vmStats.compressor_page_count) * pageSize
            let used = active + wired + compressed

            return MemoryInfo(used: used, total: totalMemory)
        }

        private struct NetworkBytes {
            let bytesIn: Int
            let bytesOut: Int
        }

        private func networkBytes() -> NetworkBytes {
            var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&ifaddrsPtr) == 0, let firstAddr = ifaddrsPtr else {
                return NetworkBytes(bytesIn: 0, bytesOut: 0)
            }
            defer { freeifaddrs(ifaddrsPtr) }

            var totalIn = 0
            var totalOut = 0
            var current: UnsafeMutablePointer<ifaddrs>? = firstAddr

            while let addr = current {
                if addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                    if let data = addr.pointee.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        totalIn += Int(networkData.ifi_ibytes)
                        totalOut += Int(networkData.ifi_obytes)
                    }
                }
                current = addr.pointee.ifa_next
            }

            return NetworkBytes(bytesIn: totalIn, bytesOut: totalOut)
        }

        private struct DiskBytes {
            let bytesRead: Int
            let bytesWritten: Int
        }

        private func diskBytes() -> DiskBytes {
            var totalRead = 0
            var totalWritten = 0

            let matching = IOServiceMatching("IOBlockStorageDriver")
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                return DiskBytes(bytesRead: 0, bytesWritten: 0)
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = properties?.takeRetainedValue() as? [String: Any],
                   let stats = dict["Statistics"] as? [String: Any]
                {
                    if let bytesRead = stats["Bytes (Read)"] as? Int {
                        totalRead += bytesRead
                    }
                    if let bytesWritten = stats["Bytes (Write)"] as? Int {
                        totalWritten += bytesWritten
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            return DiskBytes(bytesRead: totalRead, bytesWritten: totalWritten)
        }

        private func appendSample(_ sample: MachineMetricSample) async throws {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            guard let data = try? encoder.encode(sample),
                  let line = String(data: data, encoding: .utf8)
            else { return }

            if try await !fileSystem.exists(metricsFilePath.parentDirectory) {
                try await fileSystem.makeDirectory(at: metricsFilePath.parentDirectory)
            }

            try await fileLock.withLock(type: .exclusive) {
                let path = metricsFilePath.pathString

                if try await !fileSystem.exists(metricsFilePath) {
                    try await fileSystem.writeText("", at: metricsFilePath)
                }

                // FileHandle is used directly for O(1) append. FileSystem.writeText does an atomic
                // rewrite of the entire file, which would require reading all content on every 1-second sample.
                guard let handle = FileHandle(forWritingAtPath: path) else { return }
                defer { handle.closeFile() }
                handle.seekToEndOfFile()
                handle.write(Data((line + "\n").utf8))
            }
        }

        private func trimSamples() async throws {
            try await fileLock.withLock(type: .exclusive) {
                guard try await fileSystem.exists(metricsFilePath) else { return }
                let content = try await fileSystem.readTextFile(at: metricsFilePath)

                let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
                let cutoff = Date().timeIntervalSince1970 - 3600

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let recentLines = lines.filter { line in
                    guard let lineData = line.data(using: .utf8),
                          let sample = try? decoder.decode(MachineMetricSample.self, from: lineData)
                    else { return false }
                    return sample.timestamp >= cutoff
                }

                let newContent = recentLines.joined(separator: "\n") + (recentLines.isEmpty ? "" : "\n")
                try await fileSystem.writeText(newContent, at: metricsFilePath)
            }
        }
    }
#endif
