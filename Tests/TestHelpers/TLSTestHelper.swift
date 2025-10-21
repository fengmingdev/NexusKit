//
//  TLSTestHelper.swift
//  NexusKit Tests
//
//  Created by NexusKit Contributors
//
//  TLS测试辅助工具

import Foundation
import Security

/// TLS测试辅助类
public enum TLSTestHelper {

    // MARK: - 证书管理

    /// 加载测试用的自签名证书
    public static func loadTestCertificate() throws -> SecCertificate {
        let certPath = certificatePath()
        let certData = try Data(contentsOf: URL(fileURLWithPath: certPath))

        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw TLSTestError.failedToLoadCertificate
        }

        return certificate
    }

    /// 加载测试用的证书数据（用于证书固定）
    public static func loadTestCertificateData() throws -> Data {
        let certPath = certificatePath()
        return try Data(contentsOf: URL(fileURLWithPath: certPath))
    }

    /// 创建用于证书固定的TLS配置
    public static func createPinningConfiguration() throws -> TLSConfiguration {
        let certData = try loadTestCertificateData()
        let pinnedCert = TLSConfiguration.ValidationPolicy.CertificateData(data: certData)

        return TLSConfiguration(
            enabled: true,
            version: .automatic,
            p12Certificate: nil,
            validationPolicy: .pinning([pinnedCert]),
            cipherSuites: .default,
            serverName: nil,
            alpnProtocols: nil,
            allowSelfSigned: false
        )
    }

    /// 创建允许自签名证书的TLS配置
    public static func createInsecureConfiguration() -> TLSConfiguration {
        TLSConfiguration(
            enabled: true,
            version: .automatic,
            p12Certificate: nil,
            validationPolicy: .disabled,
            cipherSuites: .default,
            serverName: nil,
            alpnProtocols: nil,
            allowSelfSigned: true
        )
    }

    /// 创建系统默认验证的TLS配置
    public static func createSystemConfiguration() -> TLSConfiguration {
        TLSConfiguration(
            enabled: true,
            version: .automatic,
            p12Certificate: nil,
            validationPolicy: .system,
            cipherSuites: .default,
            serverName: nil,
            alpnProtocols: nil,
            allowSelfSigned: false
        )
    }

    // MARK: - P12证书（如果有的话）

    /// 加载P12客户端证书（用于双向认证测试）
    public static func loadP12Certificate(password: String) throws -> TLSConfiguration.P12Certificate {
        // 注意：实际项目中需要先生成P12证书
        // openssl pkcs12 -export -out client.p12 -inkey client-key.pem -in client-cert.pem -password pass:testpass

        let p12Path = p12CertificatePath()

        guard FileManager.default.fileExists(atPath: p12Path) else {
            throw TLSTestError.p12CertificateNotFound
        }

        let p12Data = try Data(contentsOf: URL(fileURLWithPath: p12Path))

        return TLSConfiguration.P12Certificate(
            data: p12Data,
            password: password,
            cacheEnabled: true,
            cacheDuration: 3600
        )
    }

    // MARK: - 路径辅助

    private static func certificatePath() -> String {
        // 优先使用项目根目录的证书
        let projectRoot = FileManager.default.currentDirectoryPath
        let certPath = "\(projectRoot)/TestServers/certs/server-cert.pem"

        if FileManager.default.fileExists(atPath: certPath) {
            return certPath
        }

        // 回退到相对路径
        return "TestServers/certs/server-cert.pem"
    }

    private static func p12CertificatePath() -> String {
        let projectRoot = FileManager.default.currentDirectoryPath
        let p12Path = "\(projectRoot)/TestServers/certs/client.p12"

        if FileManager.default.fileExists(atPath: p12Path) {
            return p12Path
        }

        return "TestServers/certs/client.p12"
    }

    // MARK: - 证书验证辅助

    /// 验证证书是否有效
    public static func verifyCertificate(_ certificate: SecCertificate) -> Bool {
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            [certificate] as CFArray,
            policy,
            &trust
        )

        guard status == errSecSuccess, let trust = trust else {
            return false
        }

        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }

    /// 获取证书信息
    public static func getCertificateInfo(_ certificate: SecCertificate) -> CertificateInfo? {
        let summary = SecCertificateCopySubjectSummary(certificate) as String?
        let data = SecCertificateCopyData(certificate) as Data

        return CertificateInfo(
            summary: summary ?? "Unknown",
            dataSize: data.count
        )
    }

    public struct CertificateInfo {
        public let summary: String
        public let dataSize: Int
    }
}

// MARK: - TLS Test Error

public enum TLSTestError: Error {
    case failedToLoadCertificate
    case p12CertificateNotFound
    case invalidCertificate
}

// MARK: - Test Utilities

extension TLSTestHelper {

    /// 检查TLS测试服务器是否运行
    public static func isTLSServerRunning() async -> Bool {
        do {
            let socket = try await NexusKit.shared
                .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
                .tls(createInsecureConfiguration())
                .timeout(2.0)
                .connect()

            await socket.disconnect(reason: .clientInitiated)
            return true
        } catch {
            return false
        }
    }

    /// 等待TLS服务器启动
    public static func waitForTLSServer(timeout: TimeInterval = 10.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await isTLSServerRunning() {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        throw TestError.serverNotRunning
    }
}
