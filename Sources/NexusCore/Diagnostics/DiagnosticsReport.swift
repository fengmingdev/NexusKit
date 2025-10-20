//
//  DiagnosticsReport.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Diagnostics Report

/// 诊断报告 - 包含完整的诊断信息
public struct DiagnosticsReport: Sendable, Codable {
    /// 报告生成时间
    public let timestamp: Date
    
    /// 连接ID
    public let connectionId: String
    
    /// 远程主机
    public let remoteHost: String
    
    /// 远程端口
    public let remotePort: Int
    
    /// 连接健康状况
    public let connectionHealth: ConnectionHealth
    
    /// 网络质量
    public let networkQuality: NetworkQuality
    
    /// 性能指标
    public let performance: PerformanceMetrics
    
    /// 诊断问题列表
    public let issues: [DiagnosticIssue]
    
    /// 建议列表
    public let recommendations: [String]
    
    public init(
        timestamp: Date = Date(),
        connectionId: String,
        remoteHost: String,
        remotePort: Int,
        connectionHealth: ConnectionHealth,
        networkQuality: NetworkQuality,
        performance: PerformanceMetrics,
        issues: [DiagnosticIssue] = [],
        recommendations: [String] = []
    ) {
        self.timestamp = timestamp
        self.connectionId = connectionId
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.connectionHealth = connectionHealth
        self.networkQuality = networkQuality
        self.performance = performance
        self.issues = issues
        self.recommendations = recommendations
    }
}

// MARK: - Connection Health

/// 连接健康状况
public struct ConnectionHealth: Sendable, Codable {
    /// 健康状态
    public let status: HealthStatus
    
    /// 连接状态
    public let connectionState: String
    
    /// DNS 解析是否成功
    public let dnsResolved: Bool
    
    /// 端口是否可达
    public let portReachable: Bool
    
    /// TLS 证书是否有效
    public let tlsCertificateValid: Bool?
    
    /// 连接延迟（毫秒）
    public let connectionLatency: Double?
    
    /// 最后一次成功通信时间
    public let lastSuccessfulCommunication: Date?
    
    public init(
        status: HealthStatus,
        connectionState: String,
        dnsResolved: Bool,
        portReachable: Bool,
        tlsCertificateValid: Bool? = nil,
        connectionLatency: Double? = nil,
        lastSuccessfulCommunication: Date? = nil
    ) {
        self.status = status
        self.connectionState = connectionState
        self.dnsResolved = dnsResolved
        self.portReachable = portReachable
        self.tlsCertificateValid = tlsCertificateValid
        self.connectionLatency = connectionLatency
        self.lastSuccessfulCommunication = lastSuccessfulCommunication
    }
}

// MARK: - Health Status

/// 健康状态枚举
public enum HealthStatus: String, Sendable, Codable {
    /// 健康
    case healthy
    
    /// 降级（部分功能受影响）
    case degraded
    
    /// 不健康
    case unhealthy
    
    /// 未知
    case unknown
}

// MARK: - Network Quality

/// 网络质量指标
public struct NetworkQuality: Sendable, Codable {
    /// 带宽（Mbps）
    public let bandwidth: Double?
    
    /// 延迟（毫秒）
    public let latency: Double
    
    /// 丢包率（百分比）
    public let packetLoss: Double
    
    /// 抖动（毫秒）
    public let jitter: Double
    
    /// RTT（往返时间，毫秒）
    public let rtt: Double?
    
    /// 网络类型（WiFi、蜂窝等）
    public let networkType: String?
    
    public init(
        bandwidth: Double? = nil,
        latency: Double,
        packetLoss: Double,
        jitter: Double,
        rtt: Double? = nil,
        networkType: String? = nil
    ) {
        self.bandwidth = bandwidth
        self.latency = latency
        self.packetLoss = packetLoss
        self.jitter = jitter
        self.rtt = rtt
        self.networkType = networkType
    }
}

// MARK: - Performance Metrics

/// 性能指标
public struct PerformanceMetrics: Sendable, Codable {
    /// 吞吐量（消息/秒）
    public let throughput: Double
    
    /// 平均延迟（毫秒）
    public let averageLatency: Double
    
    /// P95 延迟（毫秒）
    public let p95Latency: Double?
    
    /// P99 延迟（毫秒）
    public let p99Latency: Double?
    
    /// 内存使用（字节）
    public let memoryUsage: Int
    
    /// CPU 使用率（百分比）
    public let cpuUsage: Double
    
    /// 缓冲区使用率（百分比）
    public let bufferUtilization: Double?
    
    /// 活跃连接数
    public let activeConnections: Int?
    
    public init(
        throughput: Double,
        averageLatency: Double,
        p95Latency: Double? = nil,
        p99Latency: Double? = nil,
        memoryUsage: Int,
        cpuUsage: Double,
        bufferUtilization: Double? = nil,
        activeConnections: Int? = nil
    ) {
        self.throughput = throughput
        self.averageLatency = averageLatency
        self.p95Latency = p95Latency
        self.p99Latency = p99Latency
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.bufferUtilization = bufferUtilization
        self.activeConnections = activeConnections
    }
}

// MARK: - Diagnostic Issue

/// 诊断问题
public struct DiagnosticIssue: Sendable, Codable {
    /// 问题严重性
    public let severity: IssueSeverity
    
    /// 问题类型
    public let type: IssueType
    
    /// 问题描述
    public let description: String
    
    /// 详细信息
    public let details: String?
    
    /// 影响
    public let impact: String?
    
    /// 可能的解决方案
    public let possibleSolution: String?
    
    public init(
        severity: IssueSeverity,
        type: IssueType,
        description: String,
        details: String? = nil,
        impact: String? = nil,
        possibleSolution: String? = nil
    ) {
        self.severity = severity
        self.type = type
        self.description = description
        self.details = details
        self.impact = impact
        self.possibleSolution = possibleSolution
    }
}

// MARK: - Issue Severity

/// 问题严重性
public enum IssueSeverity: String, Sendable, Codable {
    /// 严重（服务不可用）
    case critical
    
    /// 主要（影响核心功能）
    case major
    
    /// 次要（影响部分功能）
    case minor
    
    /// 警告（可能影响）
    case warning
    
    /// 信息（仅供参考）
    case info
}

// MARK: - Issue Type

/// 问题类型
public enum IssueType: String, Sendable, Codable {
    /// 连接问题
    case connection
    
    /// 网络问题
    case network
    
    /// 性能问题
    case performance
    
    /// 安全问题
    case security
    
    /// 配置问题
    case configuration
    
    /// 资源问题
    case resource
}

// MARK: - Report Extensions

extension DiagnosticsReport {
    /// 导出为 JSON 字符串
    public func toJSON(prettyPrinted: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// 导出为 Markdown 格式
    public func toMarkdown() -> String {
        var markdown = """
        # Diagnostics Report
        
        **Generated**: \(formatDate(timestamp))  
        **Connection ID**: `\(connectionId)`  
        **Endpoint**: `\(remoteHost):\(remotePort)`
        
        ## Connection Health
        
        - **Status**: \(connectionHealth.status.emoji) \(connectionHealth.status.rawValue.capitalized)
        - **Connection State**: \(connectionHealth.connectionState)
        - **DNS Resolved**: \(connectionHealth.dnsResolved ? "✅" : "❌")
        - **Port Reachable**: \(connectionHealth.portReachable ? "✅" : "❌")
        """
        
        if let tlsValid = connectionHealth.tlsCertificateValid {
            markdown += "\n- **TLS Certificate**: \(tlsValid ? "✅ Valid" : "❌ Invalid")"
        }
        
        if let latency = connectionHealth.connectionLatency {
            markdown += "\n- **Connection Latency**: \(String(format: "%.2f", latency)) ms"
        }
        
        markdown += """
        
        
        ## Network Quality
        
        - **Latency**: \(String(format: "%.2f", networkQuality.latency)) ms
        - **Packet Loss**: \(String(format: "%.2f", networkQuality.packetLoss))%
        - **Jitter**: \(String(format: "%.2f", networkQuality.jitter)) ms
        """
        
        if let bandwidth = networkQuality.bandwidth {
            markdown += "\n- **Bandwidth**: \(String(format: "%.2f", bandwidth)) Mbps"
        }
        
        if let rtt = networkQuality.rtt {
            markdown += "\n- **RTT**: \(String(format: "%.2f", rtt)) ms"
        }
        
        markdown += """
        
        
        ## Performance
        
        - **Throughput**: \(String(format: "%.2f", performance.throughput)) msg/s
        - **Average Latency**: \(String(format: "%.2f", performance.averageLatency)) ms
        """
        
        if let p95 = performance.p95Latency {
            markdown += "\n- **P95 Latency**: \(String(format: "%.2f", p95)) ms"
        }
        
        if let p99 = performance.p99Latency {
            markdown += "\n- **P99 Latency**: \(String(format: "%.2f", p99)) ms"
        }
        
        markdown += """
        
        - **Memory Usage**: \(formatBytes(performance.memoryUsage))
        - **CPU Usage**: \(String(format: "%.2f", performance.cpuUsage))%
        """
        
        if !issues.isEmpty {
            markdown += "\n\n## Issues (\(issues.count))\n\n"
            for (index, issue) in issues.enumerated() {
                markdown += """
                ### \(index + 1). \(issue.severity.emoji) \(issue.description)
                
                - **Severity**: \(issue.severity.rawValue.capitalized)
                - **Type**: \(issue.type.rawValue.capitalized)
                
                """
                
                if let details = issue.details {
                    markdown += "**Details**: \(details)\n\n"
                }
                
                if let impact = issue.impact {
                    markdown += "**Impact**: \(impact)\n\n"
                }
                
                if let solution = issue.possibleSolution {
                    markdown += "**Solution**: \(solution)\n\n"
                }
            }
        }
        
        if !recommendations.isEmpty {
            markdown += "\n## Recommendations\n\n"
            for (index, recommendation) in recommendations.enumerated() {
                markdown += "\(index + 1). \(recommendation)\n"
            }
        }
        
        return markdown
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Health Status Extensions

extension HealthStatus {
    var emoji: String {
        switch self {
        case .healthy: return "✅"
        case .degraded: return "⚠️"
        case .unhealthy: return "❌"
        case .unknown: return "❓"
        }
    }
}

// MARK: - Issue Severity Extensions

extension IssueSeverity {
    var emoji: String {
        switch self {
        case .critical: return "🔴"
        case .major: return "🟠"
        case .minor: return "🟡"
        case .warning: return "⚠️"
        case .info: return "ℹ️"
        }
    }
}
