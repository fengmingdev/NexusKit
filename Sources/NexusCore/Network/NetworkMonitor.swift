//
//  NetworkMonitor.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
import Network

// MARK: - Network Monitor

/// 网络监控器
/// 检测网络状态变化、接口切换,触发快速重连
public actor NetworkMonitor {

    // MARK: - Nested Types

    /// 网络状态
    public struct NetworkStatus: Sendable {
        public let isConnected: Bool
        public let isExpensive: Bool
        public let isConstrained: Bool
        public let interfaceType: NWInterface.InterfaceType?
        public let path: NWPath

        public var description: String {
            var desc = isConnected ? "Connected" : "Disconnected"
            if let type = interfaceType {
                desc += " (\(type))"
            }
            if isExpensive { desc += " [Expensive]" }
            if isConstrained { desc += " [Constrained]" }
            return desc
        }
    }

    /// 网络变化事件
    public enum NetworkChange: Sendable {
        /// 网络连接
        case connected(NetworkStatus)
        /// 网络断开
        case disconnected
        /// 接口切换(如WiFi切换到蜂窝)
        case interfaceChanged(from: NWInterface.InterfaceType?, to: NWInterface.InterfaceType?)
        /// 网络属性变化
        case statusChanged(NetworkStatus)
    }

    // MARK: - Properties

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var currentStatus: NetworkStatus?
    private var continuation: AsyncStream<NetworkChange>.Continuation?
    private var isMonitoring = false

    /// 网络变化流
    public private(set) var changes: AsyncStream<NetworkChange>!

    // MARK: - Initialization

    public init(requiredInterfaceType: NWInterface.InterfaceType? = nil) {
        if let interfaceType = requiredInterfaceType {
            monitor = NWPathMonitor(requiredInterfaceType: interfaceType)
        } else {
            monitor = NWPathMonitor()
        }

        queue = DispatchQueue(
            label: "com.nexuskit.networkmonitor",
            qos: .utility
        )

        // 延迟创建AsyncStream到start()方法中
    }

    // MARK: - Public Methods

    /// 开始监控
    public func start() {
        guard !isMonitoring else { return }

        // 创建AsyncStream（如果尚未创建）
        if changes == nil {
            changes = AsyncStream { continuation in
                self.continuation = continuation
            }
        }

        startMonitoring()
    }

    /// 停止监控
    public func stop() {
        stopMonitoring()
    }

    private func startMonitoring() {
        guard !isMonitoring else { return }

        print("[NexusKit] 开始监控网络状态")
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.handlePathUpdate(path)
            }
        }

        monitor.start(queue: queue)
    }

    private func stopMonitoring() {
        guard isMonitoring else { return }

        print("[NexusKit] 停止监控网络状态")
        isMonitoring = false
        monitor.cancel()
        continuation?.finish()
    }

    /// 获取当前网络状态
    public func currentNetworkStatus() -> NetworkStatus? {
        currentStatus
    }

    /// 检测是否发生接口切换
    public func detectInterfaceChange(from old: NWPath, to new: NWPath) -> Bool {
        let oldInterface = old.availableInterfaces.first?.type
        let newInterface = new.availableInterfaces.first?.type

        return oldInterface != newInterface
    }

    // MARK: - Private Methods

    /// 处理路径更新
    private func handlePathUpdate(_ path: NWPath) {
        let newStatus = NetworkStatus(
            isConnected: path.status == .satisfied,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            interfaceType: path.availableInterfaces.first?.type,
            path: path
        )

        print("[NexusKit] 网络状态更新: \(newStatus.description)")

        // 检测变化类型
        if let oldStatus = currentStatus {
            if oldStatus.isConnected != newStatus.isConnected {
                if newStatus.isConnected {
                    continuation?.yield(.connected(newStatus))
                } else {
                    continuation?.yield(.disconnected)
                }
            } else if oldStatus.interfaceType != newStatus.interfaceType {
                continuation?.yield(.interfaceChanged(
                    from: oldStatus.interfaceType,
                    to: newStatus.interfaceType
                ))
            } else {
                continuation?.yield(.statusChanged(newStatus))
            }
        } else {
            // 首次状态
            if newStatus.isConnected {
                continuation?.yield(.connected(newStatus))
            } else {
                continuation?.yield(.disconnected)
            }
        }

        currentStatus = newStatus
    }

    deinit {
        if isMonitoring {
            monitor.cancel()
        }
    }
}

// MARK: - Global Network Monitor

/// 全局网络监控器实例
public let networkMonitor = NetworkMonitor()
