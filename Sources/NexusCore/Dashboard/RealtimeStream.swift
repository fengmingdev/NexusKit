//
//  RealtimeStream.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Realtime Stream

/// 实时数据流 - 管理实时数据推送
public actor RealtimeStream {
    
    // MARK: - Properties
    
    private let configuration: DashboardConfiguration
    private let aggregator: MetricsAggregator
    private var subscribers: [String: StreamSubscriber] = [:]
    private var streamTask: Task<Void, Never>?
    private var isStreaming = false
    
    // MARK: - Initialization
    
    public init(
        configuration: DashboardConfiguration = .production,
        aggregator: MetricsAggregator
    ) {
        self.configuration = configuration
        self.aggregator = aggregator
    }
    
    // MARK: - Public Methods
    
    /// 开始流式传输
    public func startStreaming() {
        guard !isStreaming else { return }
        isStreaming = true
        
        streamTask = Task {
            while !Task.isCancelled && isStreaming {
                await broadcastUpdate()
                
                let intervalNs = UInt64(configuration.updateInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }
    }
    
    /// 停止流式传输
    public func stopStreaming() {
        isStreaming = false
        streamTask?.cancel()
        streamTask = nil
    }
    
    /// 订阅数据流
    public func subscribe(id: String, handler: @escaping @Sendable (AggregatedMetrics) async -> Void) -> Bool {
        guard subscribers.count < configuration.maxClients else {
            return false
        }
        
        let subscriber = StreamSubscriber(
            id: id,
            subscribedAt: Date(),
            handler: handler
        )
        
        subscribers[id] = subscriber
        return true
    }
    
    /// 取消订阅
    public func unsubscribe(id: String) {
        subscribers.removeValue(forKey: id)
    }
    
    /// 获取订阅者数量
    public func getSubscriberCount() -> Int {
        subscribers.count
    }
    
    /// 获取所有订阅者 ID
    public func getSubscriberIds() -> [String] {
        Array(subscribers.keys)
    }
    
    /// 发送单次更新给指定订阅者
    public func sendUpdate(to subscriberId: String) async {
        guard let subscriber = subscribers[subscriberId] else { return }
        
        let metrics = await aggregator.aggregate()
        await subscriber.handler(metrics)
    }
    
    /// 广播更新给所有订阅者
    public func broadcastUpdate() async {
        let metrics = await aggregator.aggregate()
        
        await withTaskGroup(of: Void.self) { group in
            for subscriber in subscribers.values {
                group.addTask {
                    await subscriber.handler(metrics)
                }
            }
        }
    }
    
    /// 清理过期订阅者
    public func cleanupStaleSubscribers(maxAge: TimeInterval = 3600) {
        let now = Date()
        let staleIds = subscribers.filter { _, subscriber in
            now.timeIntervalSince(subscriber.subscribedAt) > maxAge
        }.map(\.key)
        
        for id in staleIds {
            subscribers.removeValue(forKey: id)
        }
    }
}

// MARK: - Stream Subscriber

/// 流订阅者
struct StreamSubscriber: Sendable {
    let id: String
    let subscribedAt: Date
    let handler: @Sendable (AggregatedMetrics) async -> Void
}

// MARK: - Stream Event

/// 流事件
public enum StreamEvent: Sendable {
    /// 数据更新
    case dataUpdate(AggregatedMetrics)
    
    /// 连接建立
    case connected
    
    /// 连接关闭
    case disconnected
    
    /// 错误发生
    case error(String)
    
    /// 心跳
    case heartbeat
}

// MARK: - Stream Statistics

/// 流统计信息
public struct StreamStatistics: Sendable, Codable {
    /// 当前订阅者数
    public let subscriberCount: Int
    
    /// 总发送更新数
    public let totalUpdatesSent: Int64
    
    /// 平均推送延迟（毫秒）
    public let averagePushLatency: Double
    
    /// 流启动时间
    public let streamStartTime: Date?
    
    /// 流运行时间
    public let uptime: TimeInterval
    
    public init(
        subscriberCount: Int,
        totalUpdatesSent: Int64,
        averagePushLatency: Double,
        streamStartTime: Date?,
        uptime: TimeInterval
    ) {
        self.subscriberCount = subscriberCount
        self.totalUpdatesSent = totalUpdatesSent
        self.averagePushLatency = averagePushLatency
        self.streamStartTime = streamStartTime
        self.uptime = uptime
    }
}
