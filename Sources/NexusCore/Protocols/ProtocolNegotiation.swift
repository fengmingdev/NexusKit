//
//  ProtocolNegotiation.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Protocol Negotiation

/// 协议协商器 - 处理客户端和服务器之间的协议协商
public actor ProtocolNegotiator {
    
    // MARK: - Properties
    
    /// 本地支持的协议列表
    private let localProtocols: [ProtocolInfo]
    
    /// 协议选择策略
    private let selectionStrategy: ProtocolSelectionStrategy
    
    /// 协商结果回调
    private var negotiationHandler: (@Sendable (NegotiationResult) async -> Void)?
    
    /// 协商统计
    private var statistics = NegotiationStatistics()
    
    // MARK: - Initialization
    
    public init(
        localProtocols: [ProtocolInfo],
        selectionStrategy: ProtocolSelectionStrategy = .highestPriority
    ) {
        self.localProtocols = localProtocols
        self.selectionStrategy = selectionStrategy
    }
    
    // MARK: - Negotiation
    
    /// 协商协议
    /// - Parameter remoteProtocols: 远程支持的协议列表
    /// - Returns: 协商结果
    public func negotiate(with remoteProtocols: [ProtocolInfo]) async -> NegotiationResult {
        let startTime = Date()
        statistics.attemptCount += 1
        
        // 查找兼容的协议
        let compatibleProtocols = findCompatibleProtocols(
            local: localProtocols,
            remote: remoteProtocols
        )
        
        guard !compatibleProtocols.isEmpty else {
            statistics.failureCount += 1
            return .failure(reason: "No compatible protocols found")
        }
        
        // 选择最佳协议
        let selectedProtocol = selectBestProtocol(
            from: compatibleProtocols,
            strategy: selectionStrategy
        )
        
        // 协商版本
        guard let negotiatedVersion = await negotiateVersion(
            protocol: selectedProtocol,
            remoteProtocols: remoteProtocols
        ) else {
            statistics.failureCount += 1
            return .failure(reason: "Version negotiation failed")
        }
        
        let duration = Date().timeIntervalSince(startTime)
        statistics.successCount += 1
        statistics.totalNegotiationTime += duration
        
        let result = NegotiationResult.success(
            protocol: selectedProtocol,
            version: negotiatedVersion,
            capabilities: selectedProtocol.capabilities,
            negotiationTime: duration
        )
        
        // 触发回调
        if let handler = negotiationHandler {
            await handler(result)
        }
        
        return result
    }
    
    /// 设置协商结果回调
    public func onNegotiation(_ handler: @escaping @Sendable (NegotiationResult) async -> Void) {
        self.negotiationHandler = handler
    }
    
    /// 获取协商统计信息
    public func getStatistics() -> NegotiationStatistics {
        statistics
    }
    
    // MARK: - Private Methods
    
    /// 查找兼容的协议
    private func findCompatibleProtocols(
        local: [ProtocolInfo],
        remote: [ProtocolInfo]
    ) -> [ProtocolInfo] {
        var compatible: [ProtocolInfo] = []
        
        for localProto in local {
            for remoteProto in remote {
                // 检查名称是否匹配
                if localProto.name.lowercased() == remoteProto.name.lowercased() {
                    // 检查是否有共同版本
                    let commonVersions = Set(localProto.supportedVersions)
                        .intersection(Set(remoteProto.supportedVersions))
                    
                    if !commonVersions.isEmpty {
                        compatible.append(localProto)
                        break
                    }
                }
            }
        }
        
        return compatible
    }
    
    /// 选择最佳协议
    private func selectBestProtocol(
        from protocols: [ProtocolInfo],
        strategy: ProtocolSelectionStrategy
    ) -> ProtocolInfo {
        switch strategy {
        case .highestPriority:
            return protocols.max(by: { $0.priority < $1.priority }) ?? protocols[0]
            
        case .mostCapabilities:
            return protocols.max(by: { $0.capabilities < $1.capabilities }) ?? protocols[0]
            
        case .newestVersion:
            return protocols.max(by: { compareVersions($0.version, $1.version) }) ?? protocols[0]
            
        case .custom(let selector):
            return selector(protocols)
        }
    }
    
    /// 协商版本
    private func negotiateVersion(
        protocol: ProtocolInfo,
        remoteProtocols: [ProtocolInfo]
    ) async -> String? {
        // 找到对应的远程协议
        guard let remoteProtocol = remoteProtocols.first(where: {
            $0.name.lowercased() == `protocol`.name.lowercased()
        }) else {
            return nil
        }
        
        // 查找最高的公共版本
        let commonVersions = Set(`protocol`.supportedVersions)
            .intersection(Set(remoteProtocol.supportedVersions))
        
        return commonVersions.sorted().last
    }
    
    /// 比较版本号
    private func compareVersions(_ v1: String, _ v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<min(parts1.count, parts2.count) {
            if parts1[i] != parts2[i] {
                return parts1[i] < parts2[i]
            }
        }
        
        return parts1.count < parts2.count
    }
}

// MARK: - Protocol Selection Strategy

/// 协议选择策略
public enum ProtocolSelectionStrategy: Sendable {
    /// 选择优先级最高的协议
    case highestPriority
    
    /// 选择能力最多的协议
    case mostCapabilities
    
    /// 选择最新版本的协议
    case newestVersion
    
    /// 自定义选择器
    case custom(@Sendable ([ProtocolInfo]) -> ProtocolInfo)
}

// MARK: - Negotiation Result

/// 协议协商结果
public enum NegotiationResult: Sendable {
    /// 成功
    case success(
        protocol: ProtocolInfo,
        version: String,
        capabilities: UInt32,
        negotiationTime: TimeInterval
    )
    
    /// 失败
    case failure(reason: String)
    
    /// 是否成功
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    /// 获取协议信息（如果成功）
    public var protocolInfo: ProtocolInfo? {
        if case .success(let proto, _, _, _) = self {
            return proto
        }
        return nil
    }
    
    /// 获取协商版本（如果成功）
    public var version: String? {
        if case .success(_, let version, _, _) = self {
            return version
        }
        return nil
    }
}

// MARK: - Negotiation Statistics

/// 协商统计信息
public struct NegotiationStatistics: Sendable {
    /// 尝试次数
    public var attemptCount: Int = 0
    
    /// 成功次数
    public var successCount: Int = 0
    
    /// 失败次数
    public var failureCount: Int = 0
    
    /// 总协商时间
    public var totalNegotiationTime: TimeInterval = 0
    
    /// 平均协商时间
    public var averageNegotiationTime: TimeInterval {
        guard successCount > 0 else { return 0 }
        return totalNegotiationTime / Double(successCount)
    }
    
    /// 成功率
    public var successRate: Double {
        guard attemptCount > 0 else { return 0 }
        return Double(successCount) / Double(attemptCount)
    }
}

// MARK: - Protocol Switcher

/// 协议切换器 - 处理运行时协议切换
public actor ProtocolSwitcher {
    
    /// 当前协议
    private var currentProtocol: ProtocolInfo
    
    /// 切换历史
    private var switchHistory: [SwitchRecord] = []
    
    /// 切换限制（防止频繁切换）
    private let minSwitchInterval: TimeInterval
    
    /// 最后切换时间
    private var lastSwitchTime: Date?
    
    public init(
        initialProtocol: ProtocolInfo,
        minSwitchInterval: TimeInterval = 5.0
    ) {
        self.currentProtocol = initialProtocol
        self.minSwitchInterval = minSwitchInterval
    }
    
    /// 切换协议
    /// - Parameter newProtocol: 新协议
    /// - Returns: 是否成功切换
    public func switchTo(_ newProtocol: ProtocolInfo) async throws -> Bool {
        // 检查切换间隔
        if let lastSwitch = lastSwitchTime {
            let elapsed = Date().timeIntervalSince(lastSwitch)
            if elapsed < minSwitchInterval {
                throw ProtocolSwitchError.switchTooFrequent(
                    minInterval: minSwitchInterval,
                    elapsed: elapsed
                )
            }
        }
        
        // 记录切换
        let record = SwitchRecord(
            from: currentProtocol,
            to: newProtocol,
            timestamp: Date(),
            success: true
        )
        
        switchHistory.append(record)
        currentProtocol = newProtocol
        lastSwitchTime = Date()
        
        return true
    }
    
    /// 获取当前协议
    public func getCurrentProtocol() -> ProtocolInfo {
        currentProtocol
    }
    
    /// 获取切换历史
    public func getSwitchHistory() -> [SwitchRecord] {
        switchHistory
    }
    
    /// 切换记录
    public struct SwitchRecord: Sendable {
        public let from: ProtocolInfo
        public let to: ProtocolInfo
        public let timestamp: Date
        public let success: Bool
    }
}

// MARK: - Protocol Switch Error

/// 协议切换错误
public enum ProtocolSwitchError: Error, Sendable {
    /// 切换过于频繁
    case switchTooFrequent(minInterval: TimeInterval, elapsed: TimeInterval)
    
    /// 协议不兼容
    case incompatibleProtocol(String)
    
    /// 切换失败
    case switchFailed(reason: String)
}

extension ProtocolSwitchError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .switchTooFrequent(let minInterval, let elapsed):
            return "Switch too frequent: min=\(minInterval)s, elapsed=\(elapsed)s"
        case .incompatibleProtocol(let reason):
            return "Incompatible protocol: \(reason)"
        case .switchFailed(let reason):
            return "Switch failed: \(reason)"
        }
    }
}
