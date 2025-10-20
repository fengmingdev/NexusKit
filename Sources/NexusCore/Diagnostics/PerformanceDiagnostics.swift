//
//  PerformanceDiagnostics.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Performance Diagnostics

/// 性能诊断工具
public actor PerformanceDiagnostics {
    
    // MARK: - Properties
    
    private let connectionId: String
    private var messageCount: Int64 = 0
    private var totalBytes: Int64 = 0
    private var latencies: [Double] = []
    private let startTime: Date
    
    // MARK: - Initialization
    
    public init(connectionId: String) {
        self.connectionId = connectionId
        self.startTime = Date()
    }
    
    // MARK: - Public Methods
    
    /// 执行完整的性能诊断
    public func diagnose() async -> PerformanceMetrics {
        let throughput = calculateThroughput()
        let avgLatency = calculateAverageLatency()
        let p95Latency = calculatePercentileLatency(percentile: 0.95)
        let p99Latency = calculatePercentileLatency(percentile: 0.99)
        let memoryUsage = await measureMemoryUsage()
        let cpuUsage = await measureCPUUsage()
        let bufferUtil = await measureBufferUtilization()
        
        return PerformanceMetrics(
            throughput: throughput,
            averageLatency: avgLatency,
            p95Latency: p95Latency,
            p99Latency: p99Latency,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            bufferUtilization: bufferUtil
        )
    }
    
    /// 记录消息处理
    public func recordMessage(bytes: Int, latency: Double) {
        messageCount += 1
        totalBytes += Int64(bytes)
        latencies.append(latency)
        
        // 限制历史记录大小
        if latencies.count > 10000 {
            latencies.removeFirst(latencies.count - 10000)
        }
    }
    
    /// 计算吞吐量
    public func calculateThroughput() -> Double {
        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed > 0 else { return 0 }
        return Double(messageCount) / elapsed
    }
    
    /// 计算平均延迟
    public func calculateAverageLatency() -> Double {
        guard !latencies.isEmpty else { return 0 }
        return latencies.reduce(0, +) / Double(latencies.count)
    }
    
    /// 计算百分位延迟
    public func calculatePercentileLatency(percentile: Double) -> Double? {
        guard !latencies.isEmpty else { return nil }
        
        let sorted = latencies.sorted()
        let index = Int(Double(sorted.count) * percentile)
        let clampedIndex = min(index, sorted.count - 1)
        return sorted[clampedIndex]
    }
    
    /// 测量内存使用
    public func measureMemoryUsage() async -> Int {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        if result == KERN_SUCCESS {
            return Int(info.resident_size)
        }
        #endif
        
        return 0
    }
    
    /// 测量 CPU 使用率
    public func measureCPUUsage() async -> Double {
        #if canImport(Darwin)
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        
        guard result == KERN_SUCCESS, let threads = threadList else {
            return 0
        }
        
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount))
        }
        
        var totalCPU: Double = 0
        
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            
            let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }
            
            if infoResult == KERN_SUCCESS {
                let cpuUsage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)
                totalCPU += cpuUsage * 100
            }
        }
        
        return totalCPU
        #else
        return 0
        #endif
    }
    
    /// 测量缓冲区使用率
    public func measureBufferUtilization() async -> Double {
        // 简化实现：基于消息积压估算
        // 实际实现应该查询实际的缓冲区状态
        let throughput = calculateThroughput()
        
        // 假设理想吞吐量为 1000 msg/s
        let idealThroughput = 1000.0
        
        if throughput > idealThroughput * 0.9 {
            return 90.0 // 高使用率
        } else if throughput > idealThroughput * 0.7 {
            return 70.0
        } else if throughput > idealThroughput * 0.5 {
            return 50.0
        } else {
            return 30.0
        }
    }
    
    /// 检测内存泄漏
    public func detectMemoryLeak() async -> Bool {
        // 简化实现：比较当前内存和预期内存
        let currentMemory = await measureMemoryUsage()
        let expectedMemory = Int(messageCount) * 1024 // 假设每消息 1KB
        
        // 如果实际内存使用超过预期的 2 倍，可能存在泄漏
        return currentMemory > expectedMemory * 2
    }
    
    /// 分析 CPU 热点
    public func analyzeCPUHotspots() async -> [String] {
        var hotspots: [String] = []
        
        let cpuUsage = await measureCPUUsage()
        
        if cpuUsage > 80 {
            hotspots.append("Critical CPU usage: \(String(format: "%.2f", cpuUsage))%")
        } else if cpuUsage > 60 {
            hotspots.append("High CPU usage: \(String(format: "%.2f", cpuUsage))%")
        }
        
        let avgLatency = calculateAverageLatency()
        if avgLatency > 100 {
            hotspots.append("High processing latency: \(String(format: "%.2f", avgLatency)) ms")
        }
        
        let throughput = calculateThroughput()
        if throughput < 100 {
            hotspots.append("Low throughput: \(String(format: "%.2f", throughput)) msg/s")
        }
        
        return hotspots
    }
    
    /// 生成性能诊断问题
    public func generateIssues(metrics: PerformanceMetrics) -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []
        
        // 检查吞吐量
        if metrics.throughput < 10 {
            issues.append(DiagnosticIssue(
                severity: .major,
                type: .performance,
                description: "Very low throughput",
                details: "Throughput is only \(String(format: "%.2f", metrics.throughput)) msg/s",
                impact: "System is severely underperforming",
                possibleSolution: "Check for blocking operations or increase concurrency"
            ))
        } else if metrics.throughput < 100 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .performance,
                description: "Low throughput",
                details: "Throughput is \(String(format: "%.2f", metrics.throughput)) msg/s",
                impact: "System may not handle peak load",
                possibleSolution: "Optimize message processing or scale horizontally"
            ))
        }
        
        // 检查延迟
        if metrics.averageLatency > 1000 {
            issues.append(DiagnosticIssue(
                severity: .major,
                type: .performance,
                description: "Very high latency",
                details: "Average latency is \(String(format: "%.2f", metrics.averageLatency)) ms",
                impact: "Poor user experience, timeouts likely",
                possibleSolution: "Reduce processing complexity or optimize critical path"
            ))
        } else if metrics.averageLatency > 500 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .performance,
                description: "High latency",
                details: "Average latency is \(String(format: "%.2f", metrics.averageLatency)) ms",
                impact: "Degraded responsiveness",
                possibleSolution: "Profile and optimize hot code paths"
            ))
        }
        
        // 检查 P99 延迟
        if let p99 = metrics.p99Latency, p99 > 2000 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .performance,
                description: "High P99 latency",
                details: "P99 latency is \(String(format: "%.2f", p99)) ms",
                impact: "1% of requests experience severe delays",
                possibleSolution: "Investigate tail latency causes (GC, I/O blocking, etc.)"
            ))
        }
        
        // 检查内存使用
        let memoryMB = Double(metrics.memoryUsage) / 1024 / 1024
        if memoryMB > 512 {
            issues.append(DiagnosticIssue(
                severity: .major,
                type: .resource,
                description: "High memory usage",
                details: "Memory usage is \(String(format: "%.2f", memoryMB)) MB",
                impact: "Risk of out-of-memory errors",
                possibleSolution: "Check for memory leaks or reduce cache size"
            ))
        } else if memoryMB > 256 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .resource,
                description: "Elevated memory usage",
                details: "Memory usage is \(String(format: "%.2f", memoryMB)) MB",
                impact: "May affect system stability under load",
                possibleSolution: "Monitor memory growth and optimize data structures"
            ))
        }
        
        // 检查 CPU 使用
        if metrics.cpuUsage > 80 {
            issues.append(DiagnosticIssue(
                severity: .major,
                type: .resource,
                description: "Critical CPU usage",
                details: "CPU usage is \(String(format: "%.2f", metrics.cpuUsage))%",
                impact: "System is CPU-bound, may drop requests",
                possibleSolution: "Optimize CPU-intensive operations or scale out"
            ))
        } else if metrics.cpuUsage > 60 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .resource,
                description: "High CPU usage",
                details: "CPU usage is \(String(format: "%.2f", metrics.cpuUsage))%",
                impact: "Limited headroom for traffic spikes",
                possibleSolution: "Profile CPU usage and optimize hot paths"
            ))
        }
        
        // 检查缓冲区使用
        if let bufferUtil = metrics.bufferUtilization, bufferUtil > 90 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .resource,
                description: "High buffer utilization",
                details: "Buffer utilization is \(String(format: "%.2f", bufferUtil))%",
                impact: "Risk of buffer overflow and message loss",
                possibleSolution: "Increase buffer size or improve processing rate"
            ))
        }
        
        return issues
    }
    
    /// 重置统计数据
    public func reset() {
        messageCount = 0
        totalBytes = 0
        latencies.removeAll()
    }
}
