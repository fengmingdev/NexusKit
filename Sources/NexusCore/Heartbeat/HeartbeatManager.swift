//
//  HeartbeatManager.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Heartbeat Manager

/// 增强的心跳管理器
/// 支持双向检测、自适应调整、丢失统计
public actor HeartbeatManager {

    // MARK: - Nested Types

    /// 心跳状态
    public enum State: Sendable {
        case idle           // 空闲(未启动)
        case active         // 活跃(正常心跳)
        case warning        // 警告(部分丢失)
        case timeout        // 超时(严重丢失)
    }

    /// 心跳统计
    public struct Statistics: Sendable {
        public let totalSent: Int
        public let totalReceived: Int
        public let totalLost: Int
        public let lossRate: Double
        public let avgLatency: TimeInterval
        public let lastHeartbeatTime: Date?
        public let state: State

        public var description: String {
            """
            Heartbeat Statistics:
            - Sent: \(totalSent)
            - Received: \(totalReceived)
            - Lost: \(totalLost) (\(String(format: "%.1f%%", lossRate * 100)))
            - Avg Latency: \(String(format: "%.0fms", avgLatency * 1000))
            - State: \(state)
            """
        }
    }

    /// 心跳配置
    public struct Configuration: Sendable {
        /// 心跳间隔(秒)
        public var interval: TimeInterval

        /// 超时时间(秒)
        public var timeout: TimeInterval

        /// 最大丢失次数(触发超时)
        public var maxLostCount: Int

        /// 是否启用自适应间隔
        public var adaptiveInterval: Bool

        /// 最小间隔(自适应模式)
        public var minInterval: TimeInterval

        /// 最大间隔(自适应模式)
        public var maxInterval: TimeInterval

        /// 是否启用双向检测
        public var bidirectional: Bool

        /// 自定义心跳数据生成器
        public var heartbeatDataProvider: (@Sendable () -> Data)?

        public init(
            interval: TimeInterval = 30.0,
            timeout: TimeInterval = 60.0,
            maxLostCount: Int = 3,
            adaptiveInterval: Bool = true,
            minInterval: TimeInterval = 10.0,
            maxInterval: TimeInterval = 120.0,
            bidirectional: Bool = true,
            heartbeatDataProvider: (@Sendable () -> Data)? = nil
        ) {
            self.interval = interval
            self.timeout = timeout
            self.maxLostCount = maxLostCount
            self.adaptiveInterval = adaptiveInterval
            self.minInterval = minInterval
            self.maxInterval = maxInterval
            self.bidirectional = bidirectional
            self.heartbeatDataProvider = heartbeatDataProvider
        }

        public static let `default` = Configuration()
    }

    // MARK: - Properties

    private let configuration: Configuration
    private var state: State = .idle

    // 统计信息
    private var sentCount: Int = 0
    private var receivedCount: Int = 0
    private var lostCount: Int = 0
    private var consecutiveLostCount: Int = 0
    private var latencies: [TimeInterval] = []
    private var lastSentTime: Date?
    private var lastReceivedTime: Date?

    // 定时器
    private var timer: Task<Void, Never>?

    // 当前间隔(自适应)
    private var currentInterval: TimeInterval

    // 回调
    private var onHeartbeatNeeded: (@Sendable (Data) async throws -> Void)?
    private var onTimeout: (@Sendable () async -> Void)?
    private var onStateChanged: (@Sendable (State) async -> Void)?

    // MARK: - Initialization

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.currentInterval = configuration.interval
    }

    // MARK: - Public Methods

    /// 启动心跳
    public func start(
        onHeartbeatNeeded: @escaping @Sendable (Data) async throws -> Void,
        onTimeout: @escaping @Sendable () async -> Void,
        onStateChanged: (@Sendable (State) async -> Void)? = nil
    ) {
        guard timer == nil else { return }

        self.onHeartbeatNeeded = onHeartbeatNeeded
        self.onTimeout = onTimeout
        self.onStateChanged = onStateChanged

        updateState(.active)
        startTimer()

        print("[NexusKit] 已启动 (间隔: \(currentInterval)s)")
    }

    /// 停止心跳
    public func stop() {
        timer?.cancel()
        timer = nil
        updateState(.idle)

        print("[NexusKit] 已停止")
    }

    /// 记录心跳响应
    public func recordHeartbeatResponse() {
        guard let sentTime = lastSentTime else { return }

        let now = Date()
        let latency = now.timeIntervalSince(sentTime)

        receivedCount += 1
        consecutiveLostCount = 0
        lastReceivedTime = now

        // 记录延迟
        latencies.append(latency)
        if latencies.count > 100 {
            latencies.removeFirst()
        }

        // 自适应间隔调整
        if configuration.adaptiveInterval {
            adjustInterval(basedOnLatency: latency)
        }

        // 更新状态
        if state != .active {
            updateState(.active)
        }

        print("[NexusKit] 心跳响应 (延迟: \(Int(latency * 1000))ms)")
    }

    /// 重置统计
    public func resetStatistics() {
        sentCount = 0
        receivedCount = 0
        lostCount = 0
        consecutiveLostCount = 0
        latencies.removeAll()
        lastSentTime = nil
        lastReceivedTime = nil
    }

    /// 获取统计信息
    public func statistics() -> Statistics {
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let lossRate = sentCount > 0 ? Double(lostCount) / Double(sentCount) : 0

        return Statistics(
            totalSent: sentCount,
            totalReceived: receivedCount,
            totalLost: lostCount,
            lossRate: lossRate,
            avgLatency: avgLatency,
            lastHeartbeatTime: lastReceivedTime,
            state: state
        )
    }

    // MARK: - Private Methods

    /// 启动定时器
    private func startTimer() {
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(currentInterval * 1_000_000_000))

                guard !Task.isCancelled else { break }

                await sendHeartbeat()
            }
        }
    }

    /// 发送心跳
    private func sendHeartbeat() async {
        // 检查上次心跳响应
        checkLastHeartbeat()

        // 生成心跳数据
        let heartbeatData = configuration.heartbeatDataProvider?() ?? createDefaultHeartbeatData()

        // 发送
        do {
            try await onHeartbeatNeeded?(heartbeatData)

            sentCount += 1
            lastSentTime = Date()

            print("[NexusKit] 心跳已发送 (#\(sentCount))")
        } catch {
            print("[NexusKit] 心跳发送失败: \(error)")
            handleHeartbeatFailure()
        }
    }

    /// 检查上次心跳
    private func checkLastHeartbeat() {
        guard let lastSent = lastSentTime else { return }

        let timeSinceLastResponse = Date().timeIntervalSince(lastReceivedTime ?? lastSent)

        // 检查是否超时
        if timeSinceLastResponse > configuration.timeout {
            consecutiveLostCount += 1
            lostCount += 1

            // 更新状态
            if consecutiveLostCount >= configuration.maxLostCount {
                updateState(.timeout)
                Task {
                    await onTimeout?()
                }
            } else if consecutiveLostCount > 0 {
                updateState(.warning)
            }

            print("[NexusKit] 心跳丢失 (连续: \(consecutiveLostCount))")
        }
    }

    /// 处理心跳发送失败
    private func handleHeartbeatFailure() {
        consecutiveLostCount += 1
        lostCount += 1

        if consecutiveLostCount >= configuration.maxLostCount {
            updateState(.timeout)
            Task {
                await onTimeout?()
            }
        } else {
            updateState(.warning)
        }
    }

    /// 自适应调整间隔
    private func adjustInterval(basedOnLatency latency: TimeInterval) {
        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)

        // 根据延迟调整
        if avgLatency < 0.1 {
            // 延迟很低,可以缩短间隔
            currentInterval = max(configuration.minInterval, currentInterval * 0.9)
        } else if avgLatency > 0.5 {
            // 延迟较高,延长间隔
            currentInterval = min(configuration.maxInterval, currentInterval * 1.1)
        }

        // 重启定时器以应用新间隔
        timer?.cancel()
        startTimer()

        print("[NexusKit] 间隔调整为: \(String(format: \"%.1fs\", currentInterval))")
    }

    /// 更新状态
    private func updateState(_ newState: State) {
        guard state != newState else { return }

        let oldState = state
        state = newState

        print("[NexusKit] 状态变化: \(oldState) → \(newState)")

        Task {
            await onStateChanged?(newState)
        }
    }

    /// 创建默认心跳数据
    private func createDefaultHeartbeatData() -> Data {
        var data = Data()
        // 简单的心跳标记
        data.append(contentsOf: "HEARTBEAT".utf8)
        // 添加时间戳
        let timestamp = Date().timeIntervalSince1970
        withUnsafeBytes(of: timestamp.bitPattern) { data.append(contentsOf: $0) }
        return data
    }

    deinit {
        timer?.cancel()
    }
}

// MARK: - Heartbeat Configuration Extensions

extension HeartbeatManager.Configuration {

    /// 快速配置: 默认设置
    public static var standard: Self {
        HeartbeatManager.Configuration(
            interval: 30.0,
            timeout: 60.0,
            maxLostCount: 3,
            adaptiveInterval: true
        )
    }

    /// 快速配置: 激进模式(快速检测)
    public static var aggressive: Self {
        HeartbeatManager.Configuration(
            interval: 10.0,
            timeout: 20.0,
            maxLostCount: 2,
            adaptiveInterval: true,
            minInterval: 5.0,
            maxInterval: 30.0
        )
    }

    /// 快速配置: 保守模式(减少流量)
    public static var conservative: Self {
        HeartbeatManager.Configuration(
            interval: 60.0,
            timeout: 120.0,
            maxLostCount: 5,
            adaptiveInterval: false
        )
    }

    /// 快速配置: 移动网络优化
    public static var mobileOptimized: Self {
        HeartbeatManager.Configuration(
            interval: 45.0,
            timeout: 90.0,
            maxLostCount: 4,
            adaptiveInterval: true,
            minInterval: 30.0,
            maxInterval: 120.0
        )
    }
}
