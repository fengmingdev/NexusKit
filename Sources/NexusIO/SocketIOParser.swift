//
//  SocketIOParser.swift
//  NexusIO
//
//  Created by NexusKit Contributors
//

import Foundation

/// Socket.IO 协议解析器
public actor SocketIOParser {
    
    /// 解析错误
    public enum ParseError: Error {
        case invalidPacketFormat
        case invalidPacketType(Int)
        case invalidJSON
        case missingEventName
        case invalidNamespace
    }
    
    public init() {}
    
    // MARK: - 编码
    
    /// 编码Socket.IO包为字符串
    /// - Parameter packet: Socket.IO包
    /// - Returns: 编码后的字符串
    /// - Throws: 编码错误
    public func encode(_ packet: SocketIOPacket) throws -> String {
        var encoded = "\(packet.type.rawValue)"
        
        // 二进制附件数量
        if let attachments = packet.attachments {
            encoded += "\(attachments)-"
        }
        
        // 命名空间
        if packet.namespace != "/" {
            encoded += packet.namespace + ","
        }
        
        // 确认ID
        if let id = packet.id {
            encoded += "\(id)"
        }
        
        // 数据负载
        if let data = packet.data, !data.isEmpty {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                encoded += jsonString
            } else {
                throw ParseError.invalidJSON
            }
        }
        
        return encoded
    }
    
    // MARK: - 解码
    
    /// 解码字符串为Socket.IO包
    /// - Parameter string: 编码的字符串
    /// - Returns: Socket.IO包
    /// - Throws: 解析错误
    public func decode(_ string: String) throws -> SocketIOPacket {
        guard !string.isEmpty else {
            throw ParseError.invalidPacketFormat
        }
        
        var index = string.startIndex
        
        // 1. 解析包类型
        guard let typeChar = string.first,
              let typeValue = Int(String(typeChar)),
              let type = SocketIOPacketType(rawValue: typeValue) else {
            throw ParseError.invalidPacketFormat
        }
        index = string.index(after: index)
        
        // 2. 解析附件数量（如果有）
        var attachments: Int?
        if index < string.endIndex {
            let remaining = String(string[index...])
            if let dashIndex = remaining.firstIndex(of: "-") {
                let attachmentStr = String(remaining[..<dashIndex])
                attachments = Int(attachmentStr)
                index = string.index(index, offsetBy: attachmentStr.count + 1)
            }
        }
        
        // 3. 解析命名空间（如果有）
        var namespace = "/"
        if index < string.endIndex, string[index] == "/" {
            if let commaIndex = string[index...].firstIndex(of: ",") {
                namespace = String(string[index..<commaIndex])
                index = string.index(after: commaIndex)
            }
        }
        
        // 4. 解析确认ID（如果有）
        var id: Int?
        if index < string.endIndex {
            let remaining = String(string[index...])
            var idStr = ""
            for char in remaining {
                if char.isNumber {
                    idStr.append(char)
                } else {
                    break
                }
            }
            if !idStr.isEmpty {
                id = Int(idStr)
                index = string.index(index, offsetBy: idStr.count)
            }
        }
        
        // 5. 解析数据负载（如果有）
        var data: [Any]?
        if index < string.endIndex {
            let jsonString = String(string[index...])
            if !jsonString.isEmpty {
                guard let jsonData = jsonString.data(using: .utf8),
                      let parsedData = try? JSONSerialization.jsonObject(with: jsonData) as? [Any] else {
                    throw ParseError.invalidJSON
                }
                data = parsedData
            }
        }
        
        return SocketIOPacket(
            type: type,
            namespace: namespace,
            data: data,
            id: id,
            attachments: attachments
        )
    }
    
    // MARK: - 辅助方法
    
    /// 提取事件名称
    /// - Parameter packet: Socket.IO包
    /// - Returns: 事件名称
    nonisolated public func extractEventName(from packet: SocketIOPacket) -> String? {
        guard packet.type == .event || packet.type == .binaryEvent else {
            return nil
        }
        
        guard let data = packet.data,
              !data.isEmpty,
              let eventName = data[0] as? String else {
            return nil
        }
        
        return eventName
    }
    
    /// 提取事件数据
    /// - Parameter packet: Socket.IO包
    /// - Returns: 事件数据
    nonisolated public func extractEventData(from packet: SocketIOPacket) -> [Any] {
        guard packet.type == .event || packet.type == .binaryEvent else {
            return []
        }
        
        guard let data = packet.data, data.count > 1 else {
            return []
        }
        
        return Array(data.dropFirst())
    }
}
