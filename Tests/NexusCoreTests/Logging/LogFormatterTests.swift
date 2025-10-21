//
//  LogFormatterTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusCore

final class LogFormatterTests: XCTestCase {
    
    private let testMessage = LogMessage(
        level: .info,
        message: "Test message",
        timestamp: Date(timeIntervalSince1970: 1640995200), // 2022-01-01 00:00:00 UTC
        file: "TestFile.swift",
        function: "testFunction",
        line: 42,
        metadata: ["key": "value"],
        error: nil
    )
    
    // MARK: - DefaultLogFormatter Tests
    
    func testDefaultLogFormatterWithUnifiedPrefix() throws {
        let formatter = DefaultLogFormatter(prefix: "NexusKit")
        let result = formatter.format(testMessage)
        
        XCTAssertTrue(result.contains("[NexusKit]"), "应包含统一前缀 [NexusKit]")
        XCTAssertTrue(result.contains("[INFO]"), "应包含日志级别")
        XCTAssertTrue(result.contains("Test message"), "应包含消息内容")
    }
    
    func testDefaultLogFormatterCustomPrefix() throws {
        let formatter = DefaultLogFormatter(prefix: "CustomPrefix")
        let result = formatter.format(testMessage)
        
        XCTAssertTrue(result.contains("[CustomPrefix]"), "应包含自定义前缀")
        XCTAssertFalse(result.contains("[NexusKit]"), "不应包含默认前缀")
    }
    
    // MARK: - CompactLogFormatter Tests
    
    func testCompactLogFormatterWithUnifiedPrefix() throws {
        let formatter = CompactLogFormatter(prefix: "NexusKit")
        let result = formatter.format(testMessage)
        
        XCTAssertEqual(result, "[NexusKit] [INFO] Test message")
        XCTAssertTrue(result.hasPrefix("[NexusKit]"), "应以统一前缀开头")
    }
    
    func testCompactLogFormatterDefaultPrefix() throws {
        let formatter = CompactLogFormatter()
        let result = formatter.format(testMessage)
        
        XCTAssertTrue(result.hasPrefix("[NexusKit]"), "默认应使用 NexusKit 前缀")
    }
    
    // MARK: - DetailedLogFormatter Tests
    
    func testDetailedLogFormatterWithUnifiedPrefix() throws {
        let formatter = DetailedLogFormatter(prefix: "NexusKit")
        let result = formatter.format(testMessage)
        
        let lines = result.components(separatedBy: .newlines)
        XCTAssertTrue(lines.first?.contains("[NexusKit]") == true, "第一行应包含统一前缀")
        XCTAssertTrue(lines.count >= 2, "应包含多行输出")
        XCTAssertTrue(result.contains("File: TestFile.swift:42"), "应包含文件位置信息")
    }
    
    // MARK: - TemplateLogFormatter Tests
    
    func testTemplateLogFormatterWithUnifiedPrefix() throws {
        let formatter = TemplateLogFormatter(prefix: "NexusKit")
        let result = formatter.format(testMessage)
        
        XCTAssertTrue(result.contains("[NexusKit]"), "应包含统一前缀")
        XCTAssertTrue(result.contains("[INFO]"), "应包含日志级别")
        XCTAssertTrue(result.contains("Test message"), "应包含消息内容")
    }
    
    func testTemplateLogFormatterCustomTemplate() throws {
        let customTemplate = "[{prefix}] {level}: {message}"
        let formatter = TemplateLogFormatter(template: customTemplate, prefix: "NexusKit")
        let result = formatter.format(testMessage)
        
        XCTAssertEqual(result, "[NexusKit] INFO: Test message")
    }
    
    // MARK: - ColorLogFormatter Tests
    
    func testColorLogFormatterWithUnifiedPrefix() throws {
        let formatter = ColorLogFormatter(prefix: "NexusKit")
        let result = formatter.format(testMessage)
        
        XCTAssertTrue(result.contains("[NexusKit]"), "应包含统一前缀")
        XCTAssertTrue(result.contains("[INFO]"), "应包含日志级别")
        XCTAssertTrue(result.contains("Test message"), "应包含消息内容")
        // 颜色代码测试
        XCTAssertTrue(result.contains("\u{001B}[32m"), "INFO 级别应使用绿色")
        XCTAssertTrue(result.contains("\u{001B}[0m"), "应包含重置颜色代码")
    }
    
    // MARK: - JSONLogFormatter Tests
    
    func testJSONLogFormatterStructure() throws {
        let formatter = JSONLogFormatter()
        let result = formatter.format(testMessage)
        
        // 验证是否为有效 JSON
        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertNotNil(json["timestamp"], "应包含时间戳")
        XCTAssertEqual(json["level"] as? String, "info", "应包含正确的日志级别")
        XCTAssertEqual(json["message"] as? String, "Test message", "应包含消息内容")
        
        let location = json["location"] as? [String: Any]
        XCTAssertNotNil(location, "应包含位置信息")
        XCTAssertEqual(location?["file"] as? String, "TestFile.swift")
        XCTAssertEqual(location?["line"] as? Int, 42)
    }
    
    // MARK: - 统一前缀验证测试
    
    func testAllFormattersUseUnifiedPrefix() throws {
        let formatters: [(String, LogFormatter)] = [
            ("DefaultLogFormatter", DefaultLogFormatter(prefix: "NexusKit")),
            ("CompactLogFormatter", CompactLogFormatter(prefix: "NexusKit")),
            ("DetailedLogFormatter", DetailedLogFormatter(prefix: "NexusKit")),
            ("TemplateLogFormatter", TemplateLogFormatter(prefix: "NexusKit")),
            ("ColorLogFormatter", ColorLogFormatter(prefix: "NexusKit"))
        ]
        
        for (name, formatter) in formatters {
            let result = formatter.format(testMessage)
            XCTAssertTrue(result.contains("[NexusKit]"), "\(name) 应包含统一前缀 [NexusKit]")
        }
    }
    
    func testPrefixFiltering() throws {
        // 模拟日志筛选场景
        let formatters: [LogFormatter] = [
            DefaultLogFormatter(prefix: "NexusKit"),
            CompactLogFormatter(prefix: "NexusKit"),
            DetailedLogFormatter(prefix: "NexusKit")
        ]
        
        var allLogs: [String] = []
        
        for formatter in formatters {
            allLogs.append(formatter.format(testMessage))
        }
        
        // 模拟 grep '[NexusKit]' 筛选
        let nexusKitLogs = allLogs.filter { $0.contains("[NexusKit]") }
        
        XCTAssertEqual(nexusKitLogs.count, allLogs.count, "所有日志都应该可以通过 [NexusKit] 前缀筛选")
        
        // 验证筛选结果
        for log in nexusKitLogs {
            XCTAssertTrue(log.contains("[NexusKit]"), "筛选出的日志应包含 [NexusKit] 前缀")
        }
    }
}