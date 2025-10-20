//
//  ConnectionDiagnostics.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Helper Functions

private func fdZero(_ set: inout fd_set) {
    #if canImport(Darwin)
    set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    #else
    set.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    #endif
}

private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    let mask = Int32(1 << bitOffset)
    
    #if canImport(Darwin)
    withUnsafeMutableBytes(of: &set.fds_bits) { bufferPointer in
        var ints = bufferPointer.bindMemory(to: Int32.self)
        ints[intOffset] |= mask
    }
    #else
    withUnsafeMutableBytes(of: &set.__fds_bits) { bufferPointer in
        var ints = bufferPointer.bindMemory(to: Int.self)
        ints[intOffset] |= Int(mask)
    }
    #endif
}

// MARK: - Connection Diagnostics

/// 连接诊断工具
public actor ConnectionDiagnostics {
    
    // MARK: - Properties
    
    private let connectionId: String
    private let remoteHost: String
    private let remotePort: Int
    
    // MARK: - Initialization
    
    public init(connectionId: String, remoteHost: String, remotePort: Int) {
        self.connectionId = connectionId
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }
    
    // MARK: - Public Methods
    
    /// 执行完整的连接诊断
    public func diagnose() async -> ConnectionHealth {
        var issues: [String] = []
        var status: HealthStatus = .healthy
        
        // 1. DNS 解析检查
        let dnsResolved = await checkDNSResolution()
        if !dnsResolved {
            issues.append("DNS resolution failed")
            status = .unhealthy
        }
        
        // 2. 端口可达性检查
        let portReachable = await checkPortReachability()
        if !portReachable {
            issues.append("Port is not reachable")
            status = .unhealthy
        }
        
        // 3. 连接延迟测量
        let latency = await measureConnectionLatency()
        
        // 4. TLS 证书验证（如果是 HTTPS/WSS）
        let tlsValid = await validateTLSCertificate()
        if let isValid = tlsValid, !isValid {
            issues.append("TLS certificate is invalid")
            if status == .healthy {
                status = .degraded
            }
        }
        
        // 评估整体状态
        if latency != nil && latency! > 500 {
            if status == .healthy {
                status = .degraded
            }
            issues.append("High connection latency")
        }
        
        return ConnectionHealth(
            status: status,
            connectionState: "connected", // TODO: Get actual state
            dnsResolved: dnsResolved,
            portReachable: portReachable,
            tlsCertificateValid: tlsValid,
            connectionLatency: latency,
            lastSuccessfulCommunication: Date()
        )
    }
    
    /// 检查 DNS 解析
    public func checkDNSResolution() async -> Bool {
        await withCheckedContinuation { continuation in
            Task.detached {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(self.remoteHost, String(self.remotePort), &hints, &result)
                
                defer {
                    if let result = result {
                        freeaddrinfo(result)
                    }
                }
                
                continuation.resume(returning: status == 0)
            }
        }
    }
    
    /// 检查端口可达性
    public func checkPortReachability() async -> Bool {
        await withCheckedContinuation { continuation in
            Task.detached {
                let result = await self.attemptConnection(timeout: 5.0)
                continuation.resume(returning: result)
            }
        }
    }
    
    /// 测量连接延迟
    public func measureConnectionLatency() async -> Double? {
        let startTime = Date()
        let reachable = await checkPortReachability()
        
        if reachable {
            let endTime = Date()
            return endTime.timeIntervalSince(startTime) * 1000 // 转换为毫秒
        }
        
        return nil
    }
    
    /// 验证 TLS 证书
    public func validateTLSCertificate() async -> Bool? {
        // 检查端口是否为 HTTPS/WSS 常用端口
        guard remotePort == 443 || remotePort == 8443 else {
            return nil // 非 TLS 连接
        }
        
        // TODO: 实现 TLS 证书验证
        // 这需要使用 Security framework (macOS/iOS) 或 OpenSSL (Linux)
        return true
    }
    
    /// 生成连接诊断建议
    public func generateRecommendations(health: ConnectionHealth) -> [String] {
        var recommendations: [String] = []
        
        if !health.dnsResolved {
            recommendations.append("Check DNS server configuration")
            recommendations.append("Verify the hostname '\(remoteHost)' is correct")
            recommendations.append("Try using IP address directly instead of hostname")
        }
        
        if !health.portReachable {
            recommendations.append("Verify the server is running on port \(remotePort)")
            recommendations.append("Check firewall rules allow connection to port \(remotePort)")
            recommendations.append("Ensure no network proxy is blocking the connection")
        }
        
        if let latency = health.connectionLatency, latency > 200 {
            recommendations.append("Connection latency is high (\(String(format: "%.2f", latency)) ms)")
            recommendations.append("Consider using a geographically closer server")
            recommendations.append("Check network quality and bandwidth")
        }
        
        if let tlsValid = health.tlsCertificateValid, !tlsValid {
            recommendations.append("TLS certificate is invalid or expired")
            recommendations.append("Update server certificate")
            recommendations.append("Verify certificate chain is complete")
        }
        
        if health.status == .healthy && recommendations.isEmpty {
            recommendations.append("Connection is healthy, no issues detected")
        }
        
        return recommendations
    }
    
    /// 生成诊断问题列表
    public func generateIssues(health: ConnectionHealth) -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []
        
        if !health.dnsResolved {
            issues.append(DiagnosticIssue(
                severity: .critical,
                type: .connection,
                description: "DNS resolution failed",
                details: "Unable to resolve hostname '\(remoteHost)' to IP address",
                impact: "Connection cannot be established",
                possibleSolution: "Check DNS configuration and hostname spelling"
            ))
        }
        
        if !health.portReachable {
            issues.append(DiagnosticIssue(
                severity: .critical,
                type: .network,
                description: "Port is not reachable",
                details: "Cannot connect to \(remoteHost):\(remotePort)",
                impact: "Service is unavailable",
                possibleSolution: "Verify server is running and firewall allows connections"
            ))
        }
        
        if let latency = health.connectionLatency {
            if latency > 500 {
                issues.append(DiagnosticIssue(
                    severity: .major,
                    type: .performance,
                    description: "High connection latency",
                    details: "Connection latency is \(String(format: "%.2f", latency)) ms",
                    impact: "Poor user experience and slow response times",
                    possibleSolution: "Use a closer server or improve network quality"
                ))
            } else if latency > 200 {
                issues.append(DiagnosticIssue(
                    severity: .warning,
                    type: .performance,
                    description: "Elevated connection latency",
                    details: "Connection latency is \(String(format: "%.2f", latency)) ms",
                    impact: "May affect real-time operations",
                    possibleSolution: "Monitor network conditions"
                ))
            }
        }
        
        if let tlsValid = health.tlsCertificateValid, !tlsValid {
            issues.append(DiagnosticIssue(
                severity: .major,
                type: .security,
                description: "Invalid TLS certificate",
                details: "The server's TLS certificate is invalid or expired",
                impact: "Security vulnerability, man-in-the-middle attacks possible",
                possibleSolution: "Update server certificate or fix certificate chain"
            ))
        }
        
        return issues
    }
    
    // MARK: - Private Methods
    
    private func attemptConnection(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            Task.detached {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(self.remoteHost, String(self.remotePort), &hints, &result)
                
                guard status == 0, let addressInfo = result else {
                    if let result = result {
                        freeaddrinfo(result)
                    }
                    continuation.resume(returning: false)
                    return
                }
                
                defer {
                    freeaddrinfo(addressInfo)
                }
                
                // 创建 socket
                let socketFD = socket(addressInfo.pointee.ai_family, addressInfo.pointee.ai_socktype, addressInfo.pointee.ai_protocol)
                guard socketFD >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                
                defer {
                    close(socketFD)
                }
                
                // 设置非阻塞模式
                var flags = fcntl(socketFD, F_GETFL, 0)
                flags |= O_NONBLOCK
                _ = fcntl(socketFD, F_SETFL, flags)
                
                // 尝试连接
                let connectResult = connect(socketFD, addressInfo.pointee.ai_addr, addressInfo.pointee.ai_addrlen)
                
                if connectResult == 0 {
                    // 立即连接成功
                    continuation.resume(returning: true)
                    return
                }
                
                #if canImport(Darwin)
                let inProgress = errno == EINPROGRESS
                #else
                let inProgress = errno == Int32(EINPROGRESS)
                #endif
                
                guard inProgress else {
                    continuation.resume(returning: false)
                    return
                }
                
                // 使用 select 等待连接完成
                var readSet = fd_set()
                var writeSet = fd_set()
                fdZero(&readSet)
                fdZero(&writeSet)
                fdSet(socketFD, &writeSet)
                
                var timeoutVal = timeval(tv_sec: Int(timeout), tv_usec: 0)
                let selectResult = select(socketFD + 1, &readSet, &writeSet, nil, &timeoutVal)
                
                if selectResult > 0 {
                    // 检查 socket 错误
                    var error: Int32 = 0
                    var errorLen = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &errorLen)
                    
                    continuation.resume(returning: error == 0)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
}
