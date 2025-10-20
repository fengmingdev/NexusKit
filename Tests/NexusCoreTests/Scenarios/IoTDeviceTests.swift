//
//  IoTDeviceTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusCore

/// IoT设备场景测试
///
/// 模拟物联网设备的真实场景，测试设备通信相关功能
///
/// **场景特点**:
/// - 海量设备连接
/// - 低功耗要求（心跳间隔长）
/// - 数据上报频繁但小包
/// - 命令下发实时性要求高
/// - 设备可能频繁离线/上线
/// - 需要TLS加密
///
/// **前置条件**: 启动测试服务器
/// ```bash
/// cd TestServers
/// npm run tcp
/// npm run tls
/// ```
///
@available(iOS 13.0, macOS 10.15, *)
final class IoTDeviceTests: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8888
    private let tlsPort: UInt16 = 8889
    private let connectionTimeout: TimeInterval = 10.0

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        print("\n" + String(repeating: "=", count: 60))
        print("🔌 IoT设备场景测试")
        print(String(repeating: "=", count: 60))
    }

    override func tearDown() async throws {
        print(String(repeating: "=", count: 60))
        print("✅ IoT场景测试完成")
        print(String(repeating: "=", count: 60) + "\n")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await super.tearDown()
    }

    // MARK: - 1. 设备上报场景 (2个测试)

    /// 场景1.1: 传感器数据定时上报
    func testSensorDataReporting() async throws {
        print("\n📊 场景: 传感器数据定时上报 (10个设备，5分钟)")

        let deviceCount = 10
        let reportInterval: TimeInterval = 30 // 每30秒上报一次
        let testDuration: TimeInterval = 300 // 5分钟

        // 创建传感器设备
        print("  创建\(deviceCount)个传感器设备...")
        var devices: [IoTDevice] = []
        for i in 1...deviceCount {
            let device = try await createIoTDevice(
                id: "sensor-\(i)",
                type: .sensor,
                heartbeatInterval: 120 // 2分钟心跳（IoT设备心跳间隔通常较长）
            )
            devices.append(device)
        }

        defer {
            for device in devices {
                Task { await device.disconnect() }
            }
        }

        print("  开始数据上报（5分钟）...")

        let startTime = Date()
        var totalReports = 0
        var failedReports = 0

        // 并发上报
        await withTaskGroup(of: (String, Int, Int).self) { group in
            for device in devices {
                group.addTask {
                    var successCount = 0
                    var failCount = 0

                    while Date().timeIntervalSince(startTime) < testDuration {
                        // 生成传感器数据
                        let sensorData = SensorData(
                            deviceId: await device.id,
                            temperature: Double.random(in: 20...30),
                            humidity: Double.random(in: 40...70),
                            timestamp: Date()
                        )

                        do {
                            try await device.report(sensorData)
                            successCount += 1
                        } catch {
                            failCount += 1
                        }

                        // 等待下次上报
                        try? await Task.sleep(nanoseconds: UInt64(reportInterval * 1_000_000_000))
                    }

                    return (await device.id, successCount, failCount)
                }
            }

            for await (deviceId, success, failed) in group {
                totalReports += success
                failedReports += failed
                print("    \(deviceId): 成功\(success), 失败\(failed)")
            }
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        let successRate = Double(totalReports - failedReports) / Double(totalReports)
        let expectedReports = deviceCount * Int(testDuration / reportInterval)

        print("\n📊 传感器数据上报结果:")
        print("  设备数: \(deviceCount)")
        print("  测试时长: \(String(format: "%.1f", actualDuration / 60))分钟")
        print("  预期上报: ~\(expectedReports)次")
        print("  实际上报: \(totalReports)次")
        print("  失败次数: \(failedReports)")
        print("  成功率: \(String(format: "%.2f", successRate * 100))%")

        XCTAssertGreaterThan(successRate, 0.95, "IoT数据上报成功率应该大于95%")
        XCTAssertGreaterThanOrEqual(totalReports, Int(Double(expectedReports) * 0.9),
                                   "实际上报次数应该接近预期")
    }

    /// 场景1.2: 批量设备状态上报
    func testBatchDeviceStatusReport() async throws {
        print("\n📊 场景: 批量设备状态上报 (100个设备)")

        let deviceCount = 100

        // 创建设备
        print("  创建\(deviceCount)个设备...")
        var devices: [IoTDevice] = []

        for i in 1...deviceCount {
            let device = try await createIoTDevice(
                id: "device-\(i)",
                type: .actuator,
                heartbeatInterval: 0 // 无心跳，节省资源
            )
            devices.append(device)

            if i % 20 == 0 {
                print("    已创建 \(i)/\(deviceCount)")
            }
        }

        defer {
            for device in devices {
                Task { await device.disconnect() }
            }
        }

        // 批量上报状态
        print("\n  批量上报设备状态...")
        let startTime = Date()
        var successCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for device in devices {
                group.addTask {
                    let status = DeviceStatus(
                        deviceId: await device.id,
                        online: true,
                        battery: Int.random(in: 50...100),
                        signal: Int.random(in: -90...(-50)),
                        timestamp: Date()
                    )

                    do {
                        try await device.report(status)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if success {
                    successCount += 1
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let successRate = Double(successCount) / Double(deviceCount)
        let reportsPerSecond = Double(successCount) / duration

        print("\n📊 批量状态上报结果:")
        print("  设备数: \(deviceCount)")
        print("  耗时: \(String(format: "%.2f", duration))秒")
        print("  成功: \(successCount)")
        print("  成功率: \(String(format: "%.2f", successRate * 100))%")
        print("  吞吐量: \(String(format: "%.1f", reportsPerSecond)) 设备/秒")

        XCTAssertGreaterThan(successRate, 0.95, "批量上报成功率应该大于95%")
        XCTAssertGreaterThan(reportsPerSecond, 10, "吞吐量应该大于10设备/秒")
    }

    // MARK: - 2. 命令下发场景 (2个测试)

    /// 场景2.1: 单设备命令控制
    func testSingleDeviceControl() async throws {
        print("\n📊 场景: 单设备命令控制（智能灯开关）")

        let device = try await createIoTDevice(
            id: "smart-light-001",
            type: .actuator,
            heartbeatInterval: 60
        )
        defer { Task { await device.disconnect() } }

        // 发送多个控制命令
        let commands: [(String, Any)] = [
            ("turn_on", true),
            ("set_brightness", 80),
            ("set_color", "#FF5733"),
            ("turn_off", false)
        ]

        print("  发送\(commands.count)个控制命令...")

        var latencies: [TimeInterval] = []

        for (cmd, value) in commands {
            let command = DeviceCommand(
                deviceId: await device.id,
                command: cmd,
                params: ["value": value],
                timestamp: Date()
            )

            let start = Date()
            try await device.executeCommand(command)
            let latency = Date().timeIntervalSince(start)
            latencies.append(latency)

            print("    [\(cmd)] 延迟: \(String(format: "%.2f", latency * 1000))ms")
        }

        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let maxLatency = latencies.max() ?? 0

        print("\n📊 设备控制结果:")
        print("  命令数: \(commands.count)")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("  最大延迟: \(String(format: "%.2f", maxLatency * 1000))ms")

        // IoT命令要求低延迟
        XCTAssertLessThan(avgLatency, 0.15, "IoT命令平均延迟应该小于150ms")
        XCTAssertLessThan(maxLatency, 0.3, "IoT命令最大延迟应该小于300ms")
    }

    /// 场景2.2: 批量设备命令广播
    func testBatchDeviceCommandBroadcast() async throws {
        print("\n📊 场景: 批量设备命令广播（50个设备同时关闭）")

        let deviceCount = 50

        // 创建设备
        print("  创建\(deviceCount)个智能插座...")
        var devices: [IoTDevice] = []
        for i in 1...deviceCount {
            let device = try await createIoTDevice(
                id: "smart-plug-\(i)",
                type: .actuator,
                heartbeatInterval: 0
            )
            devices.append(device)
        }

        defer {
            for device in devices {
                Task { await device.disconnect() }
            }
        }

        // 广播关闭命令
        print("  广播关闭命令到所有设备...")
        let startTime = Date()
        var successCount = 0

        await withTaskGroup(of: (String, Bool, TimeInterval).self) { group in
            for device in devices {
                group.addTask {
                    let command = DeviceCommand(
                        deviceId: await device.id,
                        command: "turn_off",
                        params: [:],
                        timestamp: Date()
                    )

                    let start = Date()
                    do {
                        try await device.executeCommand(command)
                        let latency = Date().timeIntervalSince(start)
                        return (await device.id, true, latency)
                    } catch {
                        return (await device.id, false, 0)
                    }
                }
            }

            var latencies: [TimeInterval] = []
            for await (deviceId, success, latency) in group {
                if success {
                    successCount += 1
                    latencies.append(latency)
                }
            }

            let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
            print("    平均命令延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let successRate = Double(successCount) / Double(deviceCount)

        print("\n📊 批量命令广播结果:")
        print("  设备数: \(deviceCount)")
        print("  总耗时: \(String(format: "%.2f", totalDuration))秒")
        print("  成功数: \(successCount)")
        print("  成功率: \(String(format: "%.2f", successRate * 100))%")

        XCTAssertGreaterThan(successRate, 0.90, "批量命令成功率应该大于90%")
        XCTAssertLessThan(totalDuration, 10.0, "批量命令总耗时应该小于10秒")
    }

    // MARK: - 3. 设备生命周期场景 (2个测试)

    /// 场景3.1: 设备上线离线循环
    func testDeviceOnlineOfflineCycle() async throws {
        print("\n📊 场景: 设备上线离线循环 (20次)")

        let cycles = 20
        var onlineTimes: [TimeInterval] = []
        var successfulCycles = 0

        print("  模拟设备频繁上线/离线...")

        for cycle in 1...cycles {
            // 设备上线
            let onlineStart = Date()
            let device = try await createIoTDevice(
                id: "unstable-device",
                type: .sensor,
                heartbeatInterval: 0
            )
            let onlineTime = Date().timeIntervalSince(onlineStart)
            onlineTimes.append(onlineTime)

            // 上报一次数据
            let data = SensorData(
                deviceId: await device.id,
                temperature: 25.0,
                humidity: 60.0,
                timestamp: Date()
            )

            do {
                try await device.report(data)
                successfulCycles += 1
            } catch {
                print("    循环\(cycle): 上报失败")
            }

            // 设备离线
            await device.disconnect()

            if cycle % 5 == 0 {
                print("    已完成 \(cycle)/\(cycles) 循环")
            }

            // 等待一段时间再上线
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
        }

        let avgOnlineTime = onlineTimes.reduce(0, +) / Double(onlineTimes.count)
        let successRate = Double(successfulCycles) / Double(cycles)

        print("\n📊 上线离线循环结果:")
        print("  总循环数: \(cycles)")
        print("  成功循环: \(successfulCycles)")
        print("  成功率: \(String(format: "%.1f", successRate * 100))%")
        print("  平均上线时间: \(String(format: "%.2f", avgOnlineTime * 1000))ms")

        XCTAssertGreaterThan(successRate, 0.9, "上线离线成功率应该大于90%")
        XCTAssertLessThan(avgOnlineTime, 1.0, "设备上线时间应该小于1秒")
    }

    /// 场景3.2: 设备固件更新
    func testDeviceFirmwareUpdate() async throws {
        print("\n📊 场景: 设备固件更新（OTA升级）")

        let device = try await createIoTDevice(
            id: "device-ota-001",
            type: .actuator,
            heartbeatInterval: 0,
            enableTLS: true // 固件更新需要加密传输
        )
        defer { Task { await device.disconnect() } }

        // 模拟固件文件 (5MB)
        let firmwareSize = 5 * 1024 * 1024
        let chunkSize = 64 * 1024 // 64KB per chunk
        let totalChunks = firmwareSize / chunkSize

        print("  固件大小: \(firmwareSize / 1024 / 1024)MB")
        print("  分块大小: \(chunkSize / 1024)KB")
        print("  总分块数: \(totalChunks)")
        print("\n  开始传输固件...")

        let startTime = Date()
        var transferredChunks = 0

        for chunk in 1...totalChunks {
            let chunkData = Data(repeating: 0x42, count: chunkSize)
            let firmware = FirmwareChunk(
                deviceId: await device.id,
                chunkIndex: chunk,
                totalChunks: totalChunks,
                data: chunkData
            )

            do {
                try await device.uploadFirmware(firmware)
                transferredChunks += 1

                if chunk % 20 == 0 {
                    let progress = Double(chunk) / Double(totalChunks) * 100
                    print("    进度: \(String(format: "%.1f", progress))% (\(chunk)/\(totalChunks))")
                }
            } catch {
                print("    ⚠️ 分块\(chunk)传输失败")
                break
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let transferredMB = Double(transferredChunks * chunkSize) / 1024.0 / 1024.0
        let speedMBps = transferredMB / duration
        let successRate = Double(transferredChunks) / Double(totalChunks)

        print("\n📊 固件更新结果:")
        print("  传输分块: \(transferredChunks)/\(totalChunks)")
        print("  传输大小: \(String(format: "%.2f", transferredMB))MB")
        print("  耗时: \(String(format: "%.2f", duration))秒")
        print("  速度: \(String(format: "%.2f", speedMBps))MB/s")
        print("  成功率: \(String(format: "%.2f", successRate * 100))%")

        XCTAssertGreaterThan(successRate, 0.95, "固件传输成功率应该大于95%")
        XCTAssertGreaterThan(speedMBps, 0.5, "固件传输速度应该大于0.5MB/s")
    }

    // MARK: - 4. 边缘计算场景 (1个测试)

    /// 场景4.1: 边缘网关数据聚合
    func testEdgeGatewayDataAggregation() async throws {
        print("\n📊 场景: 边缘网关数据聚合（1网关聚合20设备）")

        // 创建边缘网关
        let gateway = try await createIoTDevice(
            id: "edge-gateway-001",
            type: .gateway,
            heartbeatInterval: 60,
            enableTLS: true
        )
        defer { Task { await gateway.disconnect() } }

        // 创建末端设备
        let endDeviceCount = 20
        print("  创建\(endDeviceCount)个末端传感器...")
        var endDevices: [IoTDevice] = []
        for i in 1...endDeviceCount {
            let device = try await createIoTDevice(
                id: "end-sensor-\(i)",
                type: .sensor,
                heartbeatInterval: 0
            )
            endDevices.append(device)
        }

        defer {
            for device in endDevices {
                Task { await device.disconnect() }
            }
        }

        // 模拟5分钟的数据聚合
        let testDuration: TimeInterval = 300 // 5分钟
        let aggregationInterval: TimeInterval = 30 // 每30秒聚合一次

        print("  开始数据聚合（5分钟）...")

        let startTime = Date()
        var totalAggregations = 0
        var totalDataPoints = 0

        while Date().timeIntervalSince(startTime) < testDuration {
            // 收集所有末端设备数据
            var aggregatedData: [SensorData] = []

            await withTaskGroup(of: SensorData?.self) { group in
                for device in endDevices {
                    group.addTask {
                        let data = SensorData(
                            deviceId: await device.id,
                            temperature: Double.random(in: 20...30),
                            humidity: Double.random(in: 40...70),
                            timestamp: Date()
                        )
                        return data
                    }
                }

                for await data in group {
                    if let data = data {
                        aggregatedData.append(data)
                    }
                }
            }

            // 网关聚合并上报
            let aggregation = AggregatedData(
                gatewayId: await gateway.id,
                dataPoints: aggregatedData,
                timestamp: Date()
            )

            do {
                try await gateway.report(aggregation)
                totalAggregations += 1
                totalDataPoints += aggregatedData.count

                if totalAggregations % 2 == 0 {
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("    [\(Int(elapsed))s] 已聚合\(totalAggregations)次, 数据点: \(totalDataPoints)")
                }
            } catch {
                print("    ⚠️ 聚合上报失败")
            }

            try await Task.sleep(nanoseconds: UInt64(aggregationInterval * 1_000_000_000))
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        let avgDataPointsPerAggregation = Double(totalDataPoints) / Double(totalAggregations)
        let dataPointsPerSecond = Double(totalDataPoints) / actualDuration

        print("\n📊 边缘网关聚合结果:")
        print("  网关数: 1")
        print("  末端设备: \(endDeviceCount)")
        print("  运行时长: \(String(format: "%.1f", actualDuration / 60))分钟")
        print("  总聚合次数: \(totalAggregations)")
        print("  总数据点: \(totalDataPoints)")
        print("  平均每次聚合: \(String(format: "%.1f", avgDataPointsPerAggregation))个数据点")
        print("  数据吞吐: \(String(format: "%.1f", dataPointsPerSecond))点/秒")

        XCTAssertGreaterThan(totalAggregations, 8, "应该完成至少8次聚合")
        XCTAssertGreaterThan(avgDataPointsPerAggregation, Double(endDeviceCount) * 0.9,
                            "平均聚合数据点应该接近设备数")
    }

    // MARK: - Helper Types & Methods

    /// IoT设备类型
    enum IoTDeviceType {
        case sensor      // 传感器（只上报）
        case actuator    // 执行器（接收命令）
        case gateway     // 网关（双向）
    }

    /// IoT设备
    actor IoTDevice {
        let id: String
        let type: IoTDeviceType
        private let connection: TCPConnection

        var state: ConnectionState {
            get async {
                await connection.state
            }
        }

        var heartbeatStatistics: HeartbeatStatistics {
            get async {
                await connection.heartbeatStatistics
            }
        }

        init(id: String, type: IoTDeviceType, connection: TCPConnection) {
            self.id = id
            self.type = type
            self.connection = connection
        }

        func connect() async throws {
            try await connection.connect()
        }

        func disconnect() async {
            await connection.disconnect()
        }

        func report<T: Encodable>(_ data: T) async throws {
            let jsonData = try JSONEncoder().encode(data)
            try await connection.send(jsonData)
        }

        func executeCommand(_ command: DeviceCommand) async throws {
            let data = try JSONEncoder().encode(command)
            try await connection.send(data)
        }

        func uploadFirmware(_ chunk: FirmwareChunk) async throws {
            try await connection.send(chunk.data)
        }
    }

    /// 传感器数据
    struct SensorData: Codable {
        let deviceId: String
        let temperature: Double
        let humidity: Double
        let timestamp: Date
    }

    /// 设备状态
    struct DeviceStatus: Codable {
        let deviceId: String
        let online: Bool
        let battery: Int // 电量百分比
        let signal: Int  // 信号强度 dBm
        let timestamp: Date
    }

    /// 设备命令
    struct DeviceCommand: Codable {
        let deviceId: String
        let command: String
        let params: [String: Any]
        let timestamp: Date

        enum CodingKeys: String, CodingKey {
            case deviceId, command, timestamp
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(command, forKey: .command)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }

    /// 固件分块
    struct FirmwareChunk {
        let deviceId: String
        let chunkIndex: Int
        let totalChunks: Int
        let data: Data
    }

    /// 聚合数据
    struct AggregatedData: Codable {
        let gatewayId: String
        let dataPoints: [SensorData]
        let timestamp: Date
    }

    /// 创建IoT设备
    private func createIoTDevice(
        id: String,
        type: IoTDeviceType,
        heartbeatInterval: TimeInterval = 0,
        enableTLS: Bool = false
    ) async throws -> IoTDevice {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout

        if heartbeatInterval > 0 {
            config.heartbeatInterval = heartbeatInterval
            config.heartbeatTimeout = heartbeatInterval * 2
        }

        if enableTLS {
            config.enableTLS = true
            config.allowSelfSignedCertificates = true
        }

        let port = enableTLS ? tlsPort : testPort
        let connection = TCPConnection(
            host: testHost,
            port: port,
            configuration: config
        )

        try await connection.connect()

        return IoTDevice(id: id, type: type, connection: connection)
    }
}
