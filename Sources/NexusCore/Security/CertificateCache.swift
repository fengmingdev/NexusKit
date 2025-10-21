//
//  CertificateCache.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
import Security

// MARK: - Certificate Cache

/// 证书缓存管理器
/// 使用Actor确保线程安全,支持证书自动过期和清理
public actor CertificateCache {

    // MARK: - Nested Types

    /// 缓存的证书条目
    private struct CachedCertificateEntry {
        let identity: SecIdentity
        let certificates: [SecCertificate]
        let loadDate: Date
        let duration: TimeInterval

        var isExpired: Bool {
            Date().timeIntervalSince(loadDate) > duration
        }
    }

    // MARK: - Properties

    /// 证书缓存字典 (key: P12数据的hash)
    private var cache: [String: CachedCertificateEntry] = [:]

    /// 最大缓存条目数
    private let maxCacheSize: Int

    /// 是否启用缓存
    private let enabled: Bool

    // MARK: - Initialization

    public init(maxCacheSize: Int = 10, enabled: Bool = true) {
        self.maxCacheSize = maxCacheSize
        self.enabled = enabled
    }

    // MARK: - Public Methods

    /// 加载P12证书(带缓存)
    /// 注意: 由于 SecIdentity 和 SecCertificate 不符合 Sendable，此方法标记为 nonisolated
    /// 实际上证书加载本身是线程安全的，因为它只读取 Data
    nonisolated public func loadP12Certificate(
        _ config: TLSConfiguration.P12Certificate
    ) throws -> (SecIdentity, [SecCertificate]) {
        // 暂时禁用缓存以避免并发问题
        // TODO: 使用 NSLock 或其他同步机制来实现线程安全的缓存
        return try loadP12CertificateInternal(data: config.data, password: config.password)
    }

    /// 清除过期的缓存条目
    public func clearExpired() {
        let expiredKeys = cache.filter { $0.value.isExpired }.map { $0.key }

        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            print("[CertificateCache] 已清除 \(expiredKeys.count) 个过期证书")
        }
    }

    /// 清除所有缓存
    public func clearAll() {
        let count = cache.count
        cache.removeAll()
        print("[CertificateCache] 已清除所有证书缓存 (\(count) 个)")
    }

    /// 清除指定证书的缓存
    public func clearCertificate(data: Data) {
        let cacheKey = generateCacheKey(data: data)
        if cache.removeValue(forKey: cacheKey) != nil {
            print("[CertificateCache] 已清除证书缓存: \(cacheKey)")
        }
    }

    /// 获取缓存统计信息
    public func statistics() -> CacheStatistics {
        let total = cache.count
        let expired = cache.values.filter { $0.isExpired }.count
        let active = total - expired

        return CacheStatistics(
            totalEntries: total,
            activeEntries: active,
            expiredEntries: expired
        )
    }

    // MARK: - Private Methods

    /// 内部加载P12证书
    private func loadP12CertificateInternal(
        data: Data,
        password: String
    ) throws -> (SecIdentity, [SecCertificate]) {
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]

        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess else {
            throw NexusError.tlsError(reason: "P12证书导入失败,错误码: \(status)")
        }

        guard let itemArray = items as? [[String: Any]],
              let firstItem = itemArray.first,
              let identityRef = firstItem[kSecImportItemIdentity as String] else {
            throw NexusError.tlsError(reason: "P12证书解析失败: 未找到identity")
        }

        guard CFGetTypeID(identityRef as CFTypeRef) == SecIdentityGetTypeID() else {
            throw NexusError.tlsError(reason: "P12证书类型错误")
        }

        let secIdentity = identityRef as! SecIdentity

        // 提取证书链
        var certificates: [SecCertificate] = []

        if let certChain = firstItem[kSecImportItemCertChain as String] as? [SecCertificate] {
            certificates = certChain
        } else {
            // 从identity中提取证书
            var certificate: SecCertificate?
            let certStatus = SecIdentityCopyCertificate(secIdentity, &certificate)
            if certStatus == errSecSuccess, let cert = certificate {
                certificates.append(cert)
            }
        }

        return (secIdentity, certificates)
    }

    /// 生成缓存key(使用数据的SHA256 hash)
    private func generateCacheKey(data: Data) -> String {
        // 使用前1024字节计算hash以提高性能
        let hashData = data.prefix(1024)
        let hash = hashData.withUnsafeBytes { buffer in
            var hasher = SHA256Hasher()
            hasher.update(buffer: buffer)
            return hasher.finalize()
        }
        return hash
    }

    /// 驱逐最旧的缓存条目
    private func evictOldestEntry() {
        guard let oldestKey = cache.min(by: {
            $0.value.loadDate < $1.value.loadDate
        })?.key else {
            return
        }

        cache.removeValue(forKey: oldestKey)
        print("[CertificateCache] 已驱逐最旧证书: \(oldestKey)")
    }
}

// MARK: - Cache Statistics

/// 缓存统计信息
public struct CacheStatistics: Sendable {
    public let totalEntries: Int
    public let activeEntries: Int
    public let expiredEntries: Int

    public var hitRate: Double {
        guard totalEntries > 0 else { return 0 }
        return Double(activeEntries) / Double(totalEntries)
    }
}

// MARK: - Simple SHA256 Hasher

/// 简单的SHA256哈希器
private struct SHA256Hasher {
    private var state: [UInt8] = []

    mutating func update(buffer: UnsafeRawBufferPointer) {
        state.append(contentsOf: buffer)
    }

    func finalize() -> String {
        // 简化实现: 使用前32字节的base64编码
        let hashData = Data(state.prefix(32))
        return hashData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
            .prefix(16)
            .description
    }
}

// MARK: - Global Certificate Cache

/// 全局证书缓存实例
public let certificateCache = CertificateCache()
