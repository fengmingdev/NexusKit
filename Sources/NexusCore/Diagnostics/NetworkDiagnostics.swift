//
//  NetworkDiagnostics.swift
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

// MARK: - Network Diagnostics

/// 网络诊断工具
public actor NetworkDiagnostics {
    
    // MARK: - Properties
    
    private let remoteHost: String
    private let remotePort: Int
    
    // MARK: - Initialization
    
    public init(remoteHost: String, remotePort: Int) {
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }
    
    // MARK: - Public Methods
    
    /// 执行完整的网络诊断
    public func diagnose() async -> NetworkQuality {
        // 1. 测量延迟
        let latency = await measureLatency()
        
        // 2. 测量抖动
        let jitter = await measureJitter()
        
        // 3. 估算丢包率
        let packetLoss = await estimatePacketLoss()
        
        // 4. 测量 RTT
        let rtt = await measureRTT()
        
        // 5. 估算带宽
        let bandwidth = await estimateBandwidth()
        
        // 6. 检测网络类型
        let networkType = await detectNetworkType()
        
        return NetworkQuality(
            bandwidth: bandwidth,
            latency: latency,
            packetLoss: packetLoss,
            jitter: jitter,
            rtt: rtt,
            networkType: networkType
        )
    }
    
    /// 测量网络延迟
    public func measureLatency(samples: Int = 5) async -> Double {
        var latencies: [Double] = []
        
        for _ in 0..<samples {
            let startTime = Date()
            let _ = await pingHost()
            let endTime = Date()
            
            let latency = endTime.timeIntervalSince(startTime) * 1000 // 转换为毫秒
            latencies.append(latency)
            
            // 间隔 100ms
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 返回中位数
        let sorted = latencies.sorted()
        return sorted[sorted.count / 2]
    }
    
    /// 测量网络抖动
    public func measureJitter(samples: Int = 10) async -> Double {
        var latencies: [Double] = []
        
        for _ in 0..<samples {
            let startTime = Date()
            let _ = await pingHost()
            let endTime = Date()
            
            let latency = endTime.timeIntervalSince(startTime) * 1000
            latencies.append(latency)
            
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 计算相邻延迟差的平均值
        guard latencies.count > 1 else { return 0 }
        
        var differences: [Double] = []
        for i in 1..<latencies.count {
            differences.append(abs(latencies[i] - latencies[i - 1]))
        }
        
        return differences.reduce(0, +) / Double(differences.count)
    }
    
    /// 估算丢包率
    public func estimatePacketLoss(samples: Int = 20) async -> Double {
        var successCount = 0
        
        for _ in 0..<samples {
            let success = await pingHost()
            if success {
                successCount += 1
            }
            
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        let lossRate = Double(samples - successCount) / Double(samples) * 100
        return lossRate
    }
    
    /// 测量往返时间 (RTT)
    public func measureRTT(samples: Int = 5) async -> Double {
        var rtts: [Double] = []
        
        for _ in 0..<samples {
            let startTime = Date()
            
            // 发送小数据包并等待响应
            let _ = await pingHost()
            
            let endTime = Date()
            let rtt = endTime.timeIntervalSince(startTime) * 1000
            rtts.append(rtt)
            
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 返回平均 RTT
        return rtts.reduce(0, +) / Double(rtts.count)
    }
    
    /// 估算带宽
    public func estimateBandwidth() async -> Double? {
        // 简化实现：基于延迟估算
        // 实际实现应该发送一定量的数据并测量传输时间
        let latency = await measureLatency(samples: 3)
        
        // 基于延迟的粗略估算
        // 这只是示例，实际带宽测试需要更复杂的实现
        if latency < 10 {
            return 100.0 // 假设 100 Mbps
        } else if latency < 50 {
            return 50.0
        } else if latency < 100 {
            return 10.0
        } else {
            return 1.0
        }
    }
    
    /// 检测网络类型
    public func detectNetworkType() async -> String? {
        // 简化实现：基于延迟特征判断
        let latency = await measureLatency(samples: 3)
        
        if latency < 5 {
            return "Ethernet/WiFi (Local)"
        } else if latency < 50 {
            return "WiFi (Good)"
        } else if latency < 100 {
            return "4G/5G"
        } else if latency < 300 {
            return "3G/Poor WiFi"
        } else {
            return "2G/Poor Connection"
        }
    }
    
    /// 获取网络接口信息
    public func getNetworkInterfaceInfo() async -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            return interfaces
        }
        
        defer {
            freeifaddrs(ifaddr)
        }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            // 跳过回环接口
            if name == "lo0" || name == "lo" {
                continue
            }
            
            // 只处理 IPv4 地址
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                          &hostname, socklen_t(hostname.count),
                          nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(cString: hostname)
                
                interfaces.append(NetworkInterface(
                    name: name,
                    address: address,
                    isUp: (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                    isRunning: (interface.ifa_flags & UInt32(IFF_RUNNING)) != 0
                ))
            }
        }
        
        return interfaces
    }
    
    /// 生成网络诊断问题
    public func generateIssues(quality: NetworkQuality) -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []
        
        // 检查延迟
        if quality.latency > 300 {
            issues.append(DiagnosticIssue(
                severity: .major,
                type: .network,
                description: "Very high network latency",
                details: "Latency is \(String(format: "%.2f", quality.latency)) ms",
                impact: "Severely degraded user experience",
                possibleSolution: "Check network connection or switch to a better network"
            ))
        } else if quality.latency > 150 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .network,
                description: "High network latency",
                details: "Latency is \(String(format: "%.2f", quality.latency)) ms",
                impact: "May affect real-time operations",
                possibleSolution: "Monitor network quality"
            ))
        }
        
        // 检查丢包率
        if quality.packetLoss > 10 {
            issues.append(DiagnosticIssue(
                severity: .major,
                type: .network,
                description: "High packet loss",
                details: "Packet loss is \(String(format: "%.2f", quality.packetLoss))%",
                impact: "Unreliable connection, frequent retransmissions",
                possibleSolution: "Check network stability or switch to a more reliable network"
            ))
        } else if quality.packetLoss > 5 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .network,
                description: "Moderate packet loss",
                details: "Packet loss is \(String(format: "%.2f", quality.packetLoss))%",
                impact: "May cause occasional delays",
                possibleSolution: "Monitor network conditions"
            ))
        }
        
        // 检查抖动
        if quality.jitter > 50 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .network,
                description: "High network jitter",
                details: "Jitter is \(String(format: "%.2f", quality.jitter)) ms",
                impact: "Inconsistent latency, poor real-time performance",
                possibleSolution: "Use QoS settings or switch to a more stable network"
            ))
        }
        
        // 检查带宽
        if let bandwidth = quality.bandwidth, bandwidth < 1.0 {
            issues.append(DiagnosticIssue(
                severity: .warning,
                type: .network,
                description: "Low bandwidth",
                details: "Estimated bandwidth is \(String(format: "%.2f", bandwidth)) Mbps",
                impact: "Slow data transfer, may cause timeouts",
                possibleSolution: "Upgrade network connection or reduce data transfer size"
            ))
        }
        
        return issues
    }
    
    // MARK: - Private Methods
    
    private func pingHost() async -> Bool {
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
                
                let socketFD = socket(addressInfo.pointee.ai_family, addressInfo.pointee.ai_socktype, addressInfo.pointee.ai_protocol)
                guard socketFD >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                
                defer {
                    close(socketFD)
                }
                
                // 设置非阻塞
                var flags = fcntl(socketFD, F_GETFL, 0)
                flags |= O_NONBLOCK
                _ = fcntl(socketFD, F_SETFL, flags)
                
                // 设置超时
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                
                let connectResult = connect(socketFD, addressInfo.pointee.ai_addr, addressInfo.pointee.ai_addrlen)
                
                if connectResult == 0 {
                    continuation.resume(returning: true)
                    return
                }
                
                #if canImport(Darwin)
                let inProgress = errno == EINPROGRESS
                #else
                let inProgress = errno == Int32(EINPROGRESS)
                #endif
                
                continuation.resume(returning: inProgress)
            }
        }
    }
}

// MARK: - Network Interface

/// 网络接口信息
public struct NetworkInterface: Sendable {
    /// 接口名称
    public let name: String
    
    /// IP 地址
    public let address: String
    
    /// 是否启动
    public let isUp: Bool
    
    /// 是否运行中
    public let isRunning: Bool
    
    public init(name: String, address: String, isUp: Bool, isRunning: Bool) {
        self.name = name
        self.address = address
        self.isUp = isUp
        self.isRunning = isRunning
    }
}
