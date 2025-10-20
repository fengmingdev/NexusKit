//
//  Span.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Span

/// Span - 表示分布式追踪中的一个操作单元
public final class Span: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Span 名称
    public let name: String
    
    /// 追踪上下文
    public let context: TraceContext
    
    /// Span 类型
    public let kind: SpanKind
    
    /// 开始时间
    public let startTime: Date
    
    /// 结束时间
    public private(set) var endTime: Date?
    
    /// Span 状态
    public private(set) var status: SpanStatus
    
    /// 属性
    private var attributes: [String: AttributeValue]
    
    /// 事件
    private var events: [SpanEvent]
    
    /// 链接
    private var links: [SpanLink]
    
    /// 是否已结束
    public private(set) var isEnded: Bool = false
    
    // 线程安全
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(
        name: String,
        context: TraceContext,
        kind: SpanKind = .internal,
        startTime: Date = Date(),
        attributes: [String: AttributeValue] = [:]
    ) {
        self.name = name
        self.context = context
        self.kind = kind
        self.startTime = startTime
        self.status = .unset
        self.attributes = attributes
        self.events = []
        self.links = []
    }
    
    // MARK: - Attributes
    
    /// 设置属性
    public func setAttribute(key: String, value: AttributeValue) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isEnded else { return }
        attributes[key] = value
    }
    
    /// 批量设置属性
    public func setAttributes(_ attrs: [String: AttributeValue]) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isEnded else { return }
        attributes.merge(attrs) { _, new in new }
    }
    
    /// 获取所有属性
    public func getAttributes() -> [String: AttributeValue] {
        lock.lock()
        defer { lock.unlock() }
        return attributes
    }
    
    // MARK: - Events
    
    /// 添加事件
    public func addEvent(_ name: String, attributes: [String: AttributeValue] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isEnded else { return }
        
        let event = SpanEvent(
            name: name,
            timestamp: Date(),
            attributes: attributes
        )
        events.append(event)
    }
    
    /// 获取所有事件
    public func getEvents() -> [SpanEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
    
    // MARK: - Links
    
    /// 添加链接
    public func addLink(_ link: SpanLink) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isEnded else { return }
        links.append(link)
    }
    
    /// 获取所有链接
    public func getLinks() -> [SpanLink] {
        lock.lock()
        defer { lock.unlock() }
        return links
    }
    
    // MARK: - Status
    
    /// 设置状态
    public func setStatus(_ status: SpanStatus) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isEnded else { return }
        self.status = status
    }
    
    // MARK: - End
    
    /// 结束 Span
    public func end(time: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isEnded else { return }
        
        endTime = time
        isEnded = true
    }
    
    // MARK: - Duration
    
    /// 计算持续时间
    public func duration() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    // MARK: - Export
    
    /// 导出为字典
    public func toDictionary() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        
        var dict: [String: Any] = [
            "name": name,
            "traceId": context.traceId,
            "spanId": context.spanId,
            "kind": kind.rawValue,
            "startTime": startTime.timeIntervalSince1970,
            "status": status.rawValue
        ]
        
        if let parentSpanId = context.parentSpanId {
            dict["parentSpanId"] = parentSpanId
        }
        
        if let end = endTime {
            dict["endTime"] = end.timeIntervalSince1970
            dict["duration"] = end.timeIntervalSince(startTime)
        }
        
        if !attributes.isEmpty {
            dict["attributes"] = attributes.mapValues { $0.stringValue }
        }
        
        if !events.isEmpty {
            dict["events"] = events.map { $0.toDictionary() }
        }
        
        if !links.isEmpty {
            dict["links"] = links.map { $0.toDictionary() }
        }
        
        return dict
    }
}

// MARK: - Span Kind

/// Span 类型
public enum SpanKind: String, Sendable {
    /// 内部操作
    case `internal` = "INTERNAL"
    
    /// 客户端请求
    case client = "CLIENT"
    
    /// 服务端请求
    case server = "SERVER"
    
    /// 生产者（消息队列）
    case producer = "PRODUCER"
    
    /// 消费者（消息队列）
    case consumer = "CONSUMER"
}

// MARK: - Span Status

/// Span 状态
public enum SpanStatus: String, Sendable {
    /// 未设置
    case unset = "UNSET"
    
    /// 成功
    case ok = "OK"
    
    /// 错误
    case error = "ERROR"
}

// MARK: - Attribute Value

/// 属性值
public enum AttributeValue: Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([AttributeValue])
    
    public var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .array(let values):
            return "[\(values.map { $0.stringValue }.joined(separator: ", "))]"
        }
    }
}

// MARK: - Span Event

/// Span 事件
public struct SpanEvent: Sendable {
    public let name: String
    public let timestamp: Date
    public let attributes: [String: AttributeValue]
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        
        if !attributes.isEmpty {
            dict["attributes"] = attributes.mapValues { $0.stringValue }
        }
        
        return dict
    }
}

// MARK: - Span Link

/// Span 链接
public struct SpanLink: Sendable {
    public let context: TraceContext
    public let attributes: [String: AttributeValue]
    
    public init(context: TraceContext, attributes: [String: AttributeValue] = [:]) {
        self.context = context
        self.attributes = attributes
    }
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "traceId": context.traceId,
            "spanId": context.spanId
        ]
        
        if !attributes.isEmpty {
            dict["attributes"] = attributes.mapValues { $0.stringValue }
        }
        
        return dict
    }
}
