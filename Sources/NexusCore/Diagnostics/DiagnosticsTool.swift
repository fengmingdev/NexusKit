//
//  DiagnosticsTool.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Diagnostics Tool

/// 诊断工具集合 - 统一的诊断入口
public actor DiagnosticsTool {
    
    // MARK: - Properties
    
    private let connectionId: String
    private let remoteHost: String
    private let remotePort: Int
    
    private let connectionDiagnostics: ConnectionDiagnostics
    private let networkDiagnostics: NetworkDiagnostics
    private let performanceDiagnostics: PerformanceDiagnostics
    
    // MARK: - Initialization
    
    public init(connectionId: String, remoteHost: String, remotePort: Int) {
        self.connectionId = connectionId
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        
        self.connectionDiagnostics = ConnectionDiagnostics(
            connectionId: connectionId,
            remoteHost: remoteHost,
            remotePort: remotePort
        )
        self.networkDiagnostics = NetworkDiagnostics(
            remoteHost: remoteHost,
            remotePort: remotePort
        )
        self.performanceDiagnostics = PerformanceDiagnostics(
            connectionId: connectionId
        )
    }
    
    // MARK: - Public Methods
    
    /// 执行完整诊断
    public func runDiagnostics() async -> DiagnosticsReport {
        // 1. 连接诊断
        let connectionHealth = await connectionDiagnostics.diagnose()
        
        // 2. 网络诊断
        let networkQuality = await networkDiagnostics.diagnose()
        
        // 3. 性能诊断
        let performanceMetrics = await performanceDiagnostics.diagnose()
        
        // 4. 收集问题
        var issues: [DiagnosticIssue] = []
        issues.append(contentsOf: await connectionDiagnostics.generateIssues(health: connectionHealth))
        issues.append(contentsOf: await networkDiagnostics.generateIssues(quality: networkQuality))
        issues.append(contentsOf: await performanceDiagnostics.generateIssues(metrics: performanceMetrics))
        
        // 5. 生成建议
        let recommendations = await generateRecommendations(
            connectionHealth: connectionHealth,
            networkQuality: networkQuality,
            performanceMetrics: performanceMetrics,
            issues: issues
        )
        
        return DiagnosticsReport(
            connectionId: connectionId,
            remoteHost: remoteHost,
            remotePort: remotePort,
            connectionHealth: connectionHealth,
            networkQuality: networkQuality,
            performance: performanceMetrics,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    /// 快速健康检查
    public func quickHealthCheck() async -> HealthStatus {
        let connectionHealth = await connectionDiagnostics.diagnose()
        return connectionHealth.status
    }
    
    /// 仅诊断连接
    public func diagnoseConnection() async -> ConnectionHealth {
        await connectionDiagnostics.diagnose()
    }
    
    /// 仅诊断网络
    public func diagnoseNetwork() async -> NetworkQuality {
        await networkDiagnostics.diagnose()
    }
    
    /// 仅诊断性能
    public func diagnosePerformance() async -> PerformanceMetrics {
        await performanceDiagnostics.diagnose()
    }
    
    /// 记录消息处理（用于性能统计）
    public func recordMessage(bytes: Int, latency: Double) async {
        await performanceDiagnostics.recordMessage(bytes: bytes, latency: latency)
    }
    
    /// 导出诊断报告
    public func exportReport(format: ReportFormat = .json) async throws -> Data {
        let report = await runDiagnostics()
        
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(report)
            
        case .markdown:
            let markdown = report.toMarkdown()
            return markdown.data(using: .utf8) ?? Data()
        }
    }
    
    /// 保存诊断报告到文件
    public func saveReport(to url: URL, format: ReportFormat = .json) async throws {
        let data = try await exportReport(format: format)
        try data.write(to: url)
    }
    
    // MARK: - Private Methods
    
    private func generateRecommendations(
        connectionHealth: ConnectionHealth,
        networkQuality: NetworkQuality,
        performanceMetrics: PerformanceMetrics,
        issues: [DiagnosticIssue]
    ) async -> [String] {
        var recommendations: [String] = []
        
        // 基于问题严重性优先排序
        let criticalIssues = issues.filter { $0.severity == .critical }
        let majorIssues = issues.filter { $0.severity == .major }
        
        // 严重问题的建议
        if !criticalIssues.isEmpty {
            recommendations.append("🔴 Critical: Address \(criticalIssues.count) critical issue(s) immediately")
            for issue in criticalIssues {
                if let solution = issue.possibleSolution {
                    recommendations.append("  - \(solution)")
                }
            }
        }
        
        // 主要问题的建议
        if !majorIssues.isEmpty {
            recommendations.append("🟠 Major: Resolve \(majorIssues.count) major issue(s) soon")
            for issue in majorIssues.prefix(3) {
                if let solution = issue.possibleSolution {
                    recommendations.append("  - \(solution)")
                }
            }
        }
        
        // 连接相关建议
        if !connectionHealth.dnsResolved || !connectionHealth.portReachable {
            recommendations.append(contentsOf: await connectionDiagnostics.generateRecommendations(health: connectionHealth))
        }
        
        // 网络质量建议
        if networkQuality.latency > 100 || networkQuality.packetLoss > 5 {
            recommendations.append("Network quality is degraded, consider:")
            if networkQuality.latency > 100 {
                recommendations.append("  - Use a CDN or edge server closer to the client")
            }
            if networkQuality.packetLoss > 5 {
                recommendations.append("  - Enable connection retry and error recovery")
            }
        }
        
        // 性能优化建议
        if performanceMetrics.throughput < 100 {
            recommendations.append("Low throughput detected, optimize:")
            recommendations.append("  - Increase connection pool size")
            recommendations.append("  - Enable pipelining if supported")
            recommendations.append("  - Use batch operations")
        }
        
        if performanceMetrics.averageLatency > 200 {
            recommendations.append("High latency detected, consider:")
            recommendations.append("  - Enable compression for large messages")
            recommendations.append("  - Use connection pooling")
            recommendations.append("  - Optimize message serialization")
        }
        
        // 资源使用建议
        let memoryMB = Double(performanceMetrics.memoryUsage) / 1024 / 1024
        if memoryMB > 256 {
            recommendations.append("High memory usage (\(String(format: "%.0f", memoryMB)) MB):")
            recommendations.append("  - Check for memory leaks")
            recommendations.append("  - Reduce cache sizes")
            recommendations.append("  - Implement memory limits")
        }
        
        if performanceMetrics.cpuUsage > 60 {
            recommendations.append("High CPU usage (\(String(format: "%.1f", performanceMetrics.cpuUsage))%):")
            recommendations.append("  - Profile and optimize hot paths")
            recommendations.append("  - Use asynchronous I/O")
            recommendations.append("  - Consider horizontal scaling")
        }
        
        // 如果一切正常
        if recommendations.isEmpty {
            recommendations.append("✅ All systems operating normally")
            recommendations.append("Continue monitoring for changes")
        }
        
        return recommendations
    }
}

// MARK: - Report Format

/// 报告导出格式
public enum ReportFormat: String, Sendable {
    /// JSON 格式
    case json
    
    /// Markdown 格式
    case markdown
}

// MARK: - Diagnostics Extensions

extension DiagnosticsTool {
    /// 创建针对连接的诊断工具
    public static func forConnection(
        id: String,
        host: String,
        port: Int
    ) -> DiagnosticsTool {
        DiagnosticsTool(
            connectionId: id,
            remoteHost: host,
            remotePort: port
        )
    }
    
    /// 打印诊断报告到控制台
    public func printReport() async {
        let report = await runDiagnostics()
        print(report.toMarkdown())
    }
    
    /// 获取诊断摘要
    public func getSummary() async -> String {
        let status = await quickHealthCheck()
        let networkQuality = await diagnoseNetwork()
        let performance = await diagnosePerformance()
        
        return """
        Diagnostics Summary for \(connectionId)
        ----------------------------------------
        Status: \(status.emoji) \(status.rawValue.capitalized)
        Network Latency: \(String(format: "%.2f", networkQuality.latency)) ms
        Packet Loss: \(String(format: "%.2f", networkQuality.packetLoss))%
        Throughput: \(String(format: "%.2f", performance.throughput)) msg/s
        Avg Latency: \(String(format: "%.2f", performance.averageLatency)) ms
        Memory: \(String(format: "%.2f", Double(performance.memoryUsage) / 1024 / 1024)) MB
        CPU: \(String(format: "%.2f", performance.cpuUsage))%
        """
    }
}
