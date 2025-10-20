//
//  TestFixtures.swift
//  NexusKit Tests
//
//  Created by NexusKit Contributors
//
//  测试数据和常量

import Foundation

/// 测试固定数据
public enum TestFixtures {

    // MARK: - 测试服务器配置

    public static let tcpHost = "127.0.0.1"
    public static let tcpPort: UInt16 = 8888

    public static let tlsHost = "127.0.0.1"
    public static let tlsPort: UInt16 = 8889

    public static let socks5Host = "127.0.0.1"
    public static let socks5Port: UInt16 = 1080

    // MARK: - 测试消息

    public static let simpleMessage = "Hello NexusKit!".data(using: .utf8)!
    public static let largeMessage = String(repeating: "A", count: 65536).data(using: .utf8)!
    public static let unicodeMessage = "你好世界🚀".data(using: .utf8)!

    // MARK: - BinaryProtocol 测试数据

    public struct BinaryProtocolMessage {
        public let tag: UInt16
        public let ver: UInt16
        public let tp: UInt8
        public let res: UInt8
        public let qid: UInt32
        public let fid: UInt32
        public let code: UInt32
        public let dh: UInt16
        public let body: Data

        public init(
            tag: UInt16 = 0x7A5A,
            ver: UInt16 = 1,
            tp: UInt8 = 0,
            res: UInt8 = 0,
            qid: UInt32 = 0,
            fid: UInt32 = 0,
            code: UInt32 = 0,
            dh: UInt16 = 0,
            body: Data = Data()
        ) {
            self.tag = tag
            self.ver = ver
            self.tp = tp
            self.res = res
            self.qid = qid
            self.fid = fid
            self.code = code
            self.dh = dh
            self.body = body
        }

        /// 编码为二进制格式
        public func encode() -> Data {
            let len = UInt32(20 + body.count)
            var data = Data(capacity: 4 + Int(len))

            // 4字节长度
            data.append(contentsOf: [
                UInt8((len >> 24) & 0xFF),
                UInt8((len >> 16) & 0xFF),
                UInt8((len >> 8) & 0xFF),
                UInt8(len & 0xFF)
            ])

            // 20字节Header
            // Tag (2 bytes)
            data.append(contentsOf: [
                UInt8((tag >> 8) & 0xFF),
                UInt8(tag & 0xFF)
            ])
            // Ver (2 bytes)
            data.append(contentsOf: [
                UInt8((ver >> 8) & 0xFF),
                UInt8(ver & 0xFF)
            ])
            // Tp, Res (2 bytes)
            data.append(contentsOf: [tp, res])
            // Qid (4 bytes)
            data.append(contentsOf: [
                UInt8((qid >> 24) & 0xFF),
                UInt8((qid >> 16) & 0xFF),
                UInt8((qid >> 8) & 0xFF),
                UInt8(qid & 0xFF)
            ])
            // Fid (4 bytes)
            data.append(contentsOf: [
                UInt8((fid >> 24) & 0xFF),
                UInt8((fid >> 16) & 0xFF),
                UInt8((fid >> 8) & 0xFF),
                UInt8(fid & 0xFF)
            ])
            // Code (4 bytes)
            data.append(contentsOf: [
                UInt8((code >> 24) & 0xFF),
                UInt8((code >> 16) & 0xFF),
                UInt8((code >> 8) & 0xFF),
                UInt8(code & 0xFF)
            ])
            // Dh (2 bytes)
            data.append(contentsOf: [
                UInt8((dh >> 8) & 0xFF),
                UInt8(dh & 0xFF)
            ])

            // Body
            data.append(body)

            return data
        }

        /// 从二进制数据解码
        public static func decode(_ data: Data) -> BinaryProtocolMessage? {
            guard data.count >= 24 else { return nil }

            let len = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
            let tag = UInt16(data[4]) << 8 | UInt16(data[5])
            let ver = UInt16(data[6]) << 8 | UInt16(data[7])
            let tp = data[8]
            let res = data[9]
            let qid = UInt32(data[10]) << 24 | UInt32(data[11]) << 16 | UInt32(data[12]) << 8 | UInt32(data[13])
            let fid = UInt32(data[14]) << 24 | UInt32(data[15]) << 16 | UInt32(data[16]) << 8 | UInt32(data[17])
            let code = UInt32(data[18]) << 24 | UInt32(data[19]) << 16 | UInt32(data[20]) << 8 | UInt32(data[21])
            let dh = UInt16(data[22]) << 8 | UInt16(data[23])

            let bodyLength = Int(len) - 20
            let body = data.count > 24 ? data.subdata(in: 24..<min(24 + bodyLength, data.count)) : Data()

            return BinaryProtocolMessage(
                tag: tag,
                ver: ver,
                tp: tp,
                res: res,
                qid: qid,
                fid: fid,
                code: code,
                dh: dh,
                body: body
            )
        }
    }

    // MARK: - 预定义消息

    public static let heartbeatMessage = BinaryProtocolMessage(
        fid: 0xFFFF,
        body: Data()
    ).encode()

    public static let dataMessage = BinaryProtocolMessage(
        qid: 1,
        fid: 1,
        body: "Test Message".data(using: .utf8)!
    ).encode()

    public static let responseMessage = BinaryProtocolMessage(
        res: 1,
        qid: 1,
        fid: 1,
        code: 200,
        body: "Response".data(using: .utf8)!
    ).encode()

    // MARK: - 测试超时

    public static let shortTimeout: TimeInterval = 1.0
    public static let mediumTimeout: TimeInterval = 5.0
    public static let longTimeout: TimeInterval = 30.0
    public static let stabilityTestDuration: TimeInterval = 3600.0 // 1小时

    // MARK: - 性能基准

    public static let benchmarkIterations = 10000
    public static let concurrentConnections = 100
    public static let maxAcceptableLatency: TimeInterval = 0.100 // 100ms
    public static let minAcceptableThroughput = 10000 // 10k QPS

    // MARK: - TLS测试证书路径

    public static let tlsCertificatePath = "TestServers/certs/server-cert.pem"
    public static let tlsKeyPath = "TestServers/certs/server-key.pem"
}

// MARK: - Test Helpers

extension TestFixtures {

    /// 生成随机数据
    public static func randomData(length: Int) -> Data {
        var data = Data(count: length)
        data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            arc4random_buf(baseAddress, length)
        }
        return data
    }

    /// 生成随机字符串
    public static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    /// 等待条件满足（带超时）
    public static func waitFor(
        timeout: TimeInterval,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        throw TestError.timeout
    }
}

// MARK: - Test Error

public enum TestError: Error {
    case timeout
    case serverNotRunning
    case unexpectedResponse
    case invalidData
}
