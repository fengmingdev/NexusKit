//
//  RealtimeGameTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusKit

/// 实时游戏场景测试
///
/// 模拟真实的实时在线游戏场景，测试高频率、低延迟的网络通信
///
/// **场景特点**:
/// - 极低延迟要求 (<50ms)
/// - 高频率数据同步 (60fps = 16.7ms/帧)
/// - 多玩家同时在线
/// - 状态一致性要求高
/// - 需要处理丢包和延迟
/// - 短连接和长连接混合
///
/// **前置条件**: 启动测试服务器
/// ```bash
/// cd TestServers
/// npm run tcp
/// ```
///
@available(iOS 13.0, macOS 10.15, *)
final class RealtimeGameTests: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8888
    private let connectionTimeout: TimeInterval = 5.0

    // 游戏帧率配置
    private let targetFPS = 60
    private let frameInterval: TimeInterval = 1.0 / 60.0 // 16.7ms

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        print("\n" + String(repeating: "=", count: 60))
        print("🎮 实时游戏场景测试")
        print(String(repeating: "=", count: 60))
    }

    override func tearDown() async throws {
        print(String(repeating: "=", count: 60))
        print("✅ 游戏场景测试完成")
        print(String(repeating: "=", count: 60) + "\n")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await super.tearDown()
    }

    // MARK: - 1. 游戏大厅场景 (2个测试)

    /// 场景1.1: 玩家匹配系统
    func testPlayerMatchmaking() async throws {
        print("\n📊 场景: 玩家匹配系统（20玩家快速匹配）")

        let playerCount = 20
        let matchSize = 5 // 每局5人

        // 创建等待匹配的玩家
        print("  创建\(playerCount)个玩家...")
        var players: [GamePlayer] = []
        for i in 1...playerCount {
            let player = try await createGamePlayer(
                id: "player-\(i)",
                nickname: "Player\(i)"
            )
            players.append(player)
        }

        defer {
            for player in players {
                Task { await player.disconnect() }
            }
        }

        // 并发发送匹配请求
        print("  所有玩家发送匹配请求...")
        let startTime = Date()

        let results = await withTaskGroup(of: (String, TimeInterval, Bool).self) { group in
            for player in players {
                group.addTask {
                    let request = MatchRequest(
                        playerId: await player.id,
                        gameMode: "classic",
                        rank: Int.random(in: 1000...2000)
                    )

                    let start = Date()
                    do {
                        try await player.sendMatchRequest(request)
                        let duration = Date().timeIntervalSince(start)
                        return (await player.id, duration, true)
                    } catch {
                        return (await player.id, 0, false)
                    }
                }
            }

            var allResults: [(String, TimeInterval, Bool)] = []
            for await result in group {
                allResults.append(result)
            }
            return allResults
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let successfulMatches = results.filter { $0.2 }.count
        let avgMatchTime = results.filter { $0.2 }.map { $0.1 }.reduce(0, +) / Double(max(successfulMatches, 1))

        print("\n📊 玩家匹配结果:")
        print("  玩家数: \(playerCount)")
        print("  总耗时: \(String(format: "%.2f", totalDuration))秒")
        print("  成功匹配: \(successfulMatches)")
        print("  平均匹配时间: \(String(format: "%.2f", avgMatchTime * 1000))ms")
        print("  预期匹配房间数: \(playerCount / matchSize)")

        XCTAssertGreaterThanOrEqual(successfulMatches, playerCount - 2, "大部分玩家应该匹配成功")
        XCTAssertLessThan(avgMatchTime, 0.5, "匹配响应时间应该小于500ms")
    }

    /// 场景1.2: 房间创建和加入
    func testRoomCreationAndJoin() async throws {
        print("\n📊 场景: 房间创建和加入（10个房间，每房间5人）")

        let roomCount = 10
        let playersPerRoom = 5

        print("  创建\(roomCount)个游戏房间...")

        var allPlayers: [GamePlayer] = []
        var roomResults: [(roomId: String, playerCount: Int, createTime: TimeInterval)] = []

        for roomIndex in 1...roomCount {
            let roomId = "room-\(roomIndex)"

            // 创建房主
            let host = try await createGamePlayer(
                id: "host-\(roomIndex)",
                nickname: "Host\(roomIndex)"
            )
            allPlayers.append(host)

            // 房主创建房间
            let createStart = Date()
            try await host.createRoom(roomId: roomId, maxPlayers: playersPerRoom)
            let createTime = Date().timeIntervalSince(createStart)

            // 其他玩家加入
            var joinedCount = 1 // 房主自动加入

            for playerIndex in 2...playersPerRoom {
                let player = try await createGamePlayer(
                    id: "player-\(roomIndex)-\(playerIndex)",
                    nickname: "P\(roomIndex)-\(playerIndex)"
                )
                allPlayers.append(player)

                do {
                    try await player.joinRoom(roomId: roomId)
                    joinedCount += 1
                } catch {
                    print("    ⚠️ \(roomId): 玩家\(playerIndex)加入失败")
                }
            }

            roomResults.append((roomId, joinedCount, createTime))
            print("    [\(roomId)] 玩家数: \(joinedCount)/\(playersPerRoom)")
        }

        defer {
            for player in allPlayers {
                Task { await player.disconnect() }
            }
        }

        let avgCreateTime = roomResults.map { $0.createTime }.reduce(0, +) / Double(roomResults.count)
        let fullRooms = roomResults.filter { $0.playerCount == playersPerRoom }.count
        let totalPlayers = roomResults.map { $0.playerCount }.reduce(0, +)

        print("\n📊 房间创建结果:")
        print("  房间数: \(roomCount)")
        print("  总玩家数: \(totalPlayers)")
        print("  满员房间: \(fullRooms)/\(roomCount)")
        print("  平均创建时间: \(String(format: "%.2f", avgCreateTime * 1000))ms")

        XCTAssertGreaterThanOrEqual(fullRooms, roomCount - 2, "大部分房间应该满员")
        XCTAssertLessThan(avgCreateTime, 0.2, "房间创建时间应该小于200ms")
    }

    // MARK: - 2. 实时对战场景 (3个测试)

    /// 场景2.1: 位置同步（60fps）
    func testPositionSyncAt60FPS() async throws {
        print("\n📊 场景: 位置同步测试（60fps，5秒）")

        let player = try await createGamePlayer(id: "sync-player", nickname: "SyncPlayer")
        defer { Task { await player.disconnect() } }

        let testDuration: TimeInterval = 5.0 // 5秒
        let expectedFrames = Int(testDuration * Double(targetFPS))

        print("  目标帧率: \(targetFPS)fps")
        print("  测试时长: \(Int(testDuration))秒")
        print("  预期帧数: \(expectedFrames)")
        print("\n  开始位置同步...")

        var actualFrames = 0
        var latencies: [TimeInterval] = []
        let startTime = Date()
        var position = GamePosition(x: 0, y: 0, z: 0)

        while Date().timeIntervalSince(startTime) < testDuration {
            let frameStart = Date()

            // 模拟玩家移动
            position.x += 0.1
            position.y += 0.05

            let update = PositionUpdate(
                playerId: await player.id,
                position: position,
                timestamp: Date()
            )

            do {
                try await player.sendPositionUpdate(update)
                let latency = Date().timeIntervalSince(frameStart)
                latencies.append(latency)
                actualFrames += 1
            } catch {
                // 丢帧
            }

            // 等待到下一帧
            let frameTime = Date().timeIntervalSince(frameStart)
            if frameTime < frameInterval {
                let sleepTime = frameInterval - frameTime
                try await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            }
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        let actualFPS = Double(actualFrames) / actualDuration
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let maxLatency = latencies.max() ?? 0
        let frameStability = Double(actualFrames) / Double(expectedFrames)

        print("\n📊 位置同步结果:")
        print("  实际帧数: \(actualFrames)")
        print("  预期帧数: \(expectedFrames)")
        print("  实际FPS: \(String(format: "%.1f", actualFPS))")
        print("  帧稳定性: \(String(format: "%.1f", frameStability * 100))%")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("  最大延迟: \(String(format: "%.2f", maxLatency * 1000))ms")

        // 游戏要求极低延迟
        XCTAssertGreaterThan(frameStability, 0.9, "帧稳定性应该大于90%")
        XCTAssertLessThan(avgLatency, 0.030, "平均延迟应该小于30ms (游戏级别)")
        XCTAssertLessThan(maxLatency, 0.100, "最大延迟应该小于100ms")
    }

    /// 场景2.2: 多人实时对战
    func testMultiplayerRealTimeBattle() async throws {
        print("\n📊 场景: 5人实时对战（30秒，高频同步）")

        let playerCount = 5
        let battleDuration: TimeInterval = 30.0
        let syncInterval: TimeInterval = 0.1 // 每100ms同步一次

        // 创建玩家
        print("  创建\(playerCount)个玩家...")
        var players: [GamePlayer] = []
        for i in 1...playerCount {
            let player = try await createGamePlayer(
                id: "battle-player-\(i)",
                nickname: "BP\(i)"
            )
            players.append(player)
        }

        defer {
            for player in players {
                Task { await player.disconnect() }
            }
        }

        print("  开始\(Int(battleDuration))秒实时对战...")

        let startTime = Date()
        let results = await withTaskGroup(of: (String, Int, Int, Double).self) { group in
            for (index, player) in players.enumerated() {
                group.addTask {
                    var successCount = 0
                    var totalCount = 0
                    var latencies: [TimeInterval] = []
                    var position = GamePosition(
                        x: Double(index) * 10.0,
                        y: 0,
                        z: 0
                    )

                    while Date().timeIntervalSince(startTime) < battleDuration {
                        totalCount += 1

                        // 模拟玩家操作
                        position.x += Double.random(in: -1...1)
                        position.z += Double.random(in: -1...1)

                        let update = PositionUpdate(
                            playerId: await player.id,
                            position: position,
                            timestamp: Date()
                        )

                        let start = Date()
                        do {
                            try await player.sendPositionUpdate(update)
                            let latency = Date().timeIntervalSince(start)
                            latencies.append(latency)
                            successCount += 1
                        } catch {
                            // 同步失败
                        }

                        try? await Task.sleep(nanoseconds: UInt64(syncInterval * 1_000_000_000))
                    }

                    let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
                    return (await player.id, successCount, totalCount, avgLatency)
                }
            }

            var allResults: [(String, Int, Int, Double)] = []
            for await result in group {
                allResults.append(result)
            }
            return allResults
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        let totalUpdates = results.map { $0.1 }.reduce(0, +)
        let totalAttempts = results.map { $0.2 }.reduce(0, +)
        let avgSuccessRate = Double(totalUpdates) / Double(totalAttempts)
        let avgLatency = results.map { $0.3 }.reduce(0, +) / Double(results.count)

        print("\n📊 多人对战结果:")
        print("  玩家数: \(playerCount)")
        print("  对战时长: \(String(format: "%.1f", actualDuration))秒")
        print("  总同步尝试: \(totalAttempts)")
        print("  成功同步: \(totalUpdates)")
        print("  成功率: \(String(format: "%.2f", avgSuccessRate * 100))%")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")

        for (playerId, success, total, latency) in results {
            let rate = Double(success) / Double(total)
            print("    [\(playerId)] \(success)/\(total) (\(String(format: "%.1f", rate * 100))%), 延迟: \(String(format: "%.2f", latency * 1000))ms")
        }

        XCTAssertGreaterThan(avgSuccessRate, 0.95, "多人对战同步成功率应该大于95%")
        XCTAssertLessThan(avgLatency, 0.05, "多人对战平均延迟应该小于50ms")
    }

    /// 场景2.3: 游戏事件广播
    func testGameEventBroadcast() async throws {
        print("\n📊 场景: 游戏事件广播（击杀、拾取等）")

        let playerCount = 10

        // 创建玩家
        print("  创建\(playerCount)个玩家...")
        var players: [GamePlayer] = []
        for i in 1...playerCount {
            let player = try await createGamePlayer(
                id: "event-player-\(i)",
                nickname: "EP\(i)"
            )
            players.append(player)
        }

        defer {
            for player in players {
                Task { await player.disconnect() }
            }
        }

        // 模拟游戏事件
        let events: [GameEvent] = [
            .kill(killer: "event-player-1", victim: "event-player-2"),
            .pickup(player: "event-player-3", item: "MedKit"),
            .kill(killer: "event-player-4", victim: "event-player-5"),
            .achievement(player: "event-player-1", achievement: "FirstBlood"),
            .pickup(player: "event-player-6", item: "WeaponUpgrade")
        ]

        print("  广播\(events.count)个游戏事件...")

        var latencies: [TimeInterval] = []

        for (index, event) in events.enumerated() {
            let start = Date()

            // 向所有玩家广播事件
            await withTaskGroup(of: Void.self) { group in
                for player in players {
                    group.addTask {
                        try? await player.sendEvent(event)
                    }
                }
            }

            let latency = Date().timeIntervalSince(start)
            latencies.append(latency)

            print("    [事件\(index + 1)] \(event.description) - 延迟: \(String(format: "%.2f", latency * 1000))ms")

            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }

        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let maxLatency = latencies.max() ?? 0

        print("\n📊 事件广播结果:")
        print("  玩家数: \(playerCount)")
        print("  事件数: \(events.count)")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("  最大延迟: \(String(format: "%.2f", maxLatency * 1000))ms")

        // 事件广播要求快速
        XCTAssertLessThan(avgLatency, 0.5, "事件广播平均延迟应该小于500ms")
    }

    // MARK: - 3. 游戏结算场景 (1个测试)

    /// 场景3.1: 游戏结算和战绩上传
    func testGameSettlement() async throws {
        print("\n📊 场景: 游戏结算和战绩上传（5人）")

        let playerCount = 5

        // 创建玩家
        var players: [GamePlayer] = []
        for i in 1...playerCount {
            let player = try await createGamePlayer(
                id: "settle-player-\(i)",
                nickname: "SP\(i)"
            )
            players.append(player)
        }

        defer {
            for player in players {
                Task { await player.disconnect() }
            }
        }

        // 模拟游戏结束，上传战绩
        print("  玩家上传战绩...")

        let results = await withTaskGroup(of: (String, TimeInterval, Bool).self) { group in
            for (index, player) in players.enumerated() {
                group.addTask {
                    let stats = GameStats(
                        playerId: await player.id,
                        kills: Int.random(in: 0...10),
                        deaths: Int.random(in: 0...5),
                        assists: Int.random(in: 0...15),
                        damage: Int.random(in: 1000...5000),
                        rank: index + 1
                    )

                    let start = Date()
                    do {
                        try await player.uploadStats(stats)
                        let duration = Date().timeIntervalSince(start)
                        return (await player.id, duration, true)
                    } catch {
                        return (await player.id, 0, false)
                    }
                }
            }

            var allResults: [(String, TimeInterval, Bool)] = []
            for await result in group {
                allResults.append(result)
            }
            return allResults
        }

        let successCount = results.filter { $0.2 }.count
        let avgUploadTime = results.filter { $0.2 }.map { $0.1 }.reduce(0, +) / Double(max(successCount, 1))

        print("\n📊 游戏结算结果:")
        print("  玩家数: \(playerCount)")
        print("  上传成功: \(successCount)")
        print("  平均上传时间: \(String(format: "%.2f", avgUploadTime * 1000))ms")

        for (playerId, duration, success) in results {
            if success {
                print("    [\(playerId)] ✓ \(String(format: "%.2f", duration * 1000))ms")
            } else {
                print("    [\(playerId)] ✗ 失败")
            }
        }

        XCTAssertEqual(successCount, playerCount, "所有玩家战绩应该上传成功")
        XCTAssertLessThan(avgUploadTime, 1.0, "战绩上传时间应该小于1秒")
    }

    // MARK: - Helper Types & Methods

    /// 游戏玩家
    actor GamePlayer {
        let id: String
        let nickname: String
        private let connection: TCPConnection

        init(id: String, nickname: String, connection: TCPConnection) {
            self.id = id
            self.nickname = nickname
            self.connection = connection
        }

        func disconnect() async {
            await connection.disconnect()
        }

        func sendMatchRequest(_ request: MatchRequest) async throws {
            let data = try JSONEncoder().encode(request)
            try await connection.send(data)
        }

        func createRoom(roomId: String, maxPlayers: Int) async throws {
            let data = "CREATE_ROOM:\(roomId):\(maxPlayers)".data(using: .utf8)!
            try await connection.send(data)
        }

        func joinRoom(roomId: String) async throws {
            let data = "JOIN_ROOM:\(roomId)".data(using: .utf8)!
            try await connection.send(data)
        }

        func sendPositionUpdate(_ update: PositionUpdate) async throws {
            let data = try JSONEncoder().encode(update)
            try await connection.send(data)
        }

        func sendEvent(_ event: GameEvent) async throws {
            let data = event.description.data(using: .utf8)!
            try await connection.send(data)
        }

        func uploadStats(_ stats: GameStats) async throws {
            let data = try JSONEncoder().encode(stats)
            try await connection.send(data)
        }
    }

    /// 匹配请求
    struct MatchRequest: Codable {
        let playerId: String
        let gameMode: String
        let rank: Int
    }

    /// 游戏位置
    struct GamePosition: Codable {
        var x: Double
        var y: Double
        var z: Double
    }

    /// 位置更新
    struct PositionUpdate: Codable {
        let playerId: String
        let position: GamePosition
        let timestamp: Date
    }

    /// 游戏事件
    enum GameEvent {
        case kill(killer: String, victim: String)
        case pickup(player: String, item: String)
        case achievement(player: String, achievement: String)

        var description: String {
            switch self {
            case .kill(let killer, let victim):
                return "KILL:\(killer):\(victim)"
            case .pickup(let player, let item):
                return "PICKUP:\(player):\(item)"
            case .achievement(let player, let achievement):
                return "ACHIEVEMENT:\(player):\(achievement)"
            }
        }
    }

    /// 游戏战绩
    struct GameStats: Codable {
        let playerId: String
        let kills: Int
        let deaths: Int
        let assists: Int
        let damage: Int
        let rank: Int
    }

    /// 创建游戏玩家
    private func createGamePlayer(id: String, nickname: String) async throws -> GamePlayer {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout
        config.heartbeatInterval = 30 // 30秒心跳
        config.heartbeatTimeout = 60

        let connection = TCPConnection(
            host: testHost,
            port: testPort,
            configuration: config
        )

        try await connection.connect()

        return GamePlayer(id: id, nickname: nickname, connection: connection)
    }
}
