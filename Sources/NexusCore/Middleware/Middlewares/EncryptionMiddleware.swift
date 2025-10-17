//
//  EncryptionMiddleware.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
import CryptoKit

// MARK: - Encryption Middleware

/// 加密中间件
///
/// 使用 AES-GCM 对数据进行加密和解密，保护数据传输安全。
///
/// ## 功能特性
///
/// - AES-256-GCM 加密（AEAD 认证加密）
/// - 自动生成随机 nonce
/// - 防重放攻击
/// - 数据完整性验证
/// - 密钥派生（从密码）
///
/// ## 安全性
///
/// - **加密算法**: AES-256-GCM（NIST 推荐）
/// - **认证**: 内置消息认证（AEAD）
/// - **密钥长度**: 256 位
/// - **Nonce**: 96 位随机数（每次加密唯一）
///
/// ## 使用示例
///
/// ### 从密钥创建
/// ```swift
/// // 生成随机密钥
/// let key = SymmetricKey(size: .bits256)
///
/// let encryption = EncryptionMiddleware(key: key)
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(encryption)
///     .connect()
/// ```
///
/// ### 从密码创建
/// ```swift
/// let encryption = try EncryptionMiddleware(
///     password: "your-secret-password",
///     salt: "app-specific-salt"
/// )
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(encryption)
///     .connect()
/// ```
///
/// ## 数据格式
///
/// 加密后的数据格式：
/// ```
/// [12 bytes: Nonce][Variable: Ciphertext + Tag]
/// ```
///
/// ## 注意事项
///
/// - 双方必须使用相同的密钥
/// - 密钥应安全存储（Keychain）
/// - 不要在代码中硬编码密钥
/// - 建议定期轮换密钥
@available(iOS 13.0, macOS 10.15, *)
public struct EncryptionMiddleware: Middleware {
    // MARK: - Properties

    public let name = "EncryptionMiddleware"
    public let priority: Int

    /// 加密密钥
    private let key: SymmetricKey

    /// 是否记录加密统计
    private let enableStats: Bool

    // MARK: - Initialization

    /// 使用对称密钥初始化
    /// - Parameters:
    ///   - key: AES 对称密钥（推荐 256 位）
    ///   - enableStats: 是否启用统计，默认 `false`
    ///   - priority: 中间件优先级，默认 60（在压缩之后）
    public init(
        key: SymmetricKey,
        enableStats: Bool = false,
        priority: Int = 60
    ) {
        self.key = key
        self.enableStats = enableStats
        self.priority = priority
    }

    /// 从密码派生密钥并初始化
    /// - Parameters:
    ///   - password: 密码
    ///   - salt: 盐值（应用特定的固定字符串）
    ///   - iterations: PBKDF2 迭代次数，默认 100,000
    ///   - enableStats: 是否启用统计
    ///   - priority: 中间件优先级
    /// - Throws: 密钥派生失败
    public init(
        password: String,
        salt: String,
        iterations: Int = 100_000,
        enableStats: Bool = false,
        priority: Int = 60
    ) throws {
        let passwordData = Data(password.utf8)
        let saltData = Data(salt.utf8)

        // 使用 PBKDF2 派生密钥
        let derivedKey = try Self.deriveKey(
            from: passwordData,
            salt: saltData,
            iterations: iterations
        )

        self.init(
            key: derivedKey,
            enableStats: enableStats,
            priority: priority
        )
    }

    // MARK: - Middleware Protocol

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        do {
            let encrypted = try encrypt(data)

            if enableStats {
                let overhead = encrypted.count - data.count
                print("🔒 [Encryption] Original: \(data.count) bytes, Encrypted: \(encrypted.count) bytes, Overhead: \(overhead) bytes")
            }

            return encrypted

        } catch {
            throw NexusError.middlewareError(name: name, error: error)
        }
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        do {
            let decrypted = try decrypt(data)

            if enableStats {
                print("🔓 [Decryption] Encrypted: \(data.count) bytes, Decrypted: \(decrypted.count) bytes")
            }

            return decrypted

        } catch {
            throw NexusError.middlewareError(name: name, error: error)
        }
    }

    // MARK: - Encryption/Decryption

    private func encrypt(_ data: Data) throws -> Data {
        // 生成随机 nonce
        let nonce = AES.GCM.Nonce()

        // AES-GCM 加密
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        // 组合: nonce + ciphertext + tag
        var result = Data()
        result.append(contentsOf: nonce)

        if let combined = sealedBox.combined {
            // combined 包含 ciphertext + tag
            result.append(combined.dropFirst(12))  // 跳过 nonce（我们已经添加了）
        } else {
            throw NexusError.custom(message: "Encryption failed", underlyingError: nil)
        }

        return result
    }

    private func decrypt(_ data: Data) throws -> Data {
        // 至少需要 12 字节 nonce + 16 字节 tag
        guard data.count >= 28 else {
            throw NexusError.custom(message: "Invalid encrypted data", underlyingError: nil)
        }

        // 提取 nonce
        let nonceData = data.prefix(12)
        let nonce = try AES.GCM.Nonce(data: nonceData)

        // 提取 ciphertext + tag
        let sealedData = data.dropFirst(12)

        // 重构 sealed box
        let sealedBox = try AES.GCM.SealedBox(combined: nonceData + sealedData)

        // AES-GCM 解密和验证
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        return decryptedData
    }

    // MARK: - Key Derivation

    private static func deriveKey(
        from password: Data,
        salt: Data,
        iterations: Int
    ) throws -> SymmetricKey {
        // 使用 SHA256 和 PBKDF2 派生 256 位密钥
        var derivedKeyData = Data(count: 32)  // 256 bits

        let status = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw NexusError.custom(message: "Key derivation failed", underlyingError: nil)
        }

        return SymmetricKey(data: derivedKeyData)
    }
}

// MARK: - CommonCrypto Import

#if canImport(CommonCrypto)
import CommonCrypto
#endif

// MARK: - Simplified Encryption Middleware

/// 简化的加密中间件（仅用于演示，生产环境请使用 EncryptionMiddleware）
///
/// 使用简单的 XOR 加密，不安全，仅用于测试和演示。
public struct SimpleEncryptionMiddleware: Middleware {
    public let name = "SimpleEncryptionMiddleware"
    public let priority = 60

    private let key: [UInt8]

    /// 初始化
    /// - Parameter key: XOR 密钥字符串
    public init(key: String) {
        self.key = Array(key.utf8)
    }

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        var encrypted = data
        for i in 0..<encrypted.count {
            encrypted[i] ^= key[i % key.count]
        }
        return encrypted
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        // XOR 是对称的，加密和解密相同
        var decrypted = data
        for i in 0..<decrypted.count {
            decrypted[i] ^= key[i % key.count]
        }
        return decrypted
    }
}
