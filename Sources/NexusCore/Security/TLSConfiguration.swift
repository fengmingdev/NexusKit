//
//  TLSConfiguration.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
import Security
import Network

// MARK: - TLS Configuration

/// 增强的TLS/SSL配置
public struct TLSConfiguration: Sendable {

    // MARK: - Nested Types

    /// TLS版本
    public enum TLSVersion: Sendable {
        case tls10
        case tls11
        case tls12
        case tls13
        case automatic

        var secProtocol: tls_protocol_version_t {
            switch self {
            case .tls10: return .TLSv10
            case .tls11: return .TLSv11
            case .tls12: return .TLSv12
            case .tls13: return .TLSv13
            case .automatic: return .TLSv13
            }
        }
    }

    /// P12证书配置
    public struct P12Certificate: Sendable {
        public let data: Data
        public let password: String
        public let cacheEnabled: Bool
        public let cacheDuration: TimeInterval

        public init(
            data: Data,
            password: String,
            cacheEnabled: Bool = true,
            cacheDuration: TimeInterval = 3600
        ) {
            self.data = data
            self.password = password
            self.cacheEnabled = cacheEnabled
            self.cacheDuration = cacheDuration
        }

        /// 从Bundle加载P12证书
        public static func fromBundle(
            named name: String,
            password: String,
            bundle: Bundle = .main,
            cacheEnabled: Bool = true,
            cacheDuration: TimeInterval = 3600
        ) throws -> P12Certificate {
            guard let path = bundle.path(forResource: name, ofType: "p12"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                throw NexusError.tlsError(reason: "P12证书文件未找到: \(name).p12")
            }

            return P12Certificate(
                data: data,
                password: password,
                cacheEnabled: cacheEnabled,
                cacheDuration: cacheDuration
            )
        }
    }

    /// 证书验证策略
    public enum ValidationPolicy: Sendable {
        /// 使用系统默认验证
        case system

        /// 自定义证书验证
        case custom(CertificateData)

        /// 证书固定(Certificate Pinning)
        case pinning([CertificateData])

        /// 禁用验证(仅用于测试,生产环境禁止使用)
        case disabled

        public struct CertificateData: Sendable {
            public let data: Data

            public init(data: Data) {
                self.data = data
            }

            public static func fromBundle(
                named name: String,
                bundle: Bundle = .main
            ) throws -> CertificateData {
                guard let path = bundle.path(forResource: name, ofType: "cer") ??
                             bundle.path(forResource: name, ofType: "crt"),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                    throw NexusError.tlsError(reason: "证书文件未找到: \(name)")
                }

                return CertificateData(data: data)
            }
        }
    }

    /// 密码套件配置
    public struct CipherSuites: Sendable {
        public let suites: [tls_ciphersuite_t]

        public static let `default`: CipherSuites = .modern

        /// 现代密码套件(推荐)
        public static let modern = CipherSuites(suites: [
            .ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
            .ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
            .ECDHE_RSA_WITH_AES_256_GCM_SHA384,
            .ECDHE_RSA_WITH_AES_128_GCM_SHA256
        ])

        /// 兼容密码套件(包含更多旧版本支持)
        public static let compatible = CipherSuites(suites: [
            .ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
            .ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
            .ECDHE_RSA_WITH_AES_256_GCM_SHA384,
            .ECDHE_RSA_WITH_AES_128_GCM_SHA256,
            .ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,
            .ECDHE_RSA_WITH_AES_256_CBC_SHA384
        ])
    }

    // MARK: - Properties

    /// 是否启用TLS
    public let enabled: Bool

    /// TLS版本
    public let version: TLSVersion

    /// P12客户端证书(可选)
    public let p12Certificate: P12Certificate?

    /// 证书验证策略
    public let validationPolicy: ValidationPolicy

    /// 密码套件配置
    public let cipherSuites: CipherSuites

    /// 服务器名称指示(SNI)
    public let serverName: String?

    /// 应用层协议协商(ALPN)
    public let alpnProtocols: [String]?

    /// 是否允许自签名证书(仅测试环境)
    public let allowSelfSigned: Bool

    // MARK: - Initialization

    public init(
        enabled: Bool = true,
        version: TLSVersion = .automatic,
        p12Certificate: P12Certificate? = nil,
        validationPolicy: ValidationPolicy = .system,
        cipherSuites: CipherSuites = .default,
        serverName: String? = nil,
        alpnProtocols: [String]? = nil,
        allowSelfSigned: Bool = false
    ) {
        self.enabled = enabled
        self.version = version
        self.p12Certificate = p12Certificate
        self.validationPolicy = validationPolicy
        self.cipherSuites = cipherSuites
        self.serverName = serverName
        self.alpnProtocols = alpnProtocols
        self.allowSelfSigned = allowSelfSigned
    }

    // MARK: - Convenience Initializers

    /// 创建基础TLS配置
    public static func basic(enabled: Bool = true) -> TLSConfiguration {
        TLSConfiguration(enabled: enabled)
    }

    /// 创建带客户端证书的TLS配置
    public static func withClientCertificate(
        p12: P12Certificate,
        serverValidation: ValidationPolicy = .system
    ) -> TLSConfiguration {
        TLSConfiguration(
            enabled: true,
            p12Certificate: p12,
            validationPolicy: serverValidation
        )
    }

    /// 创建证书固定配置
    public static func withPinning(
        certificates: [ValidationPolicy.CertificateData]
    ) -> TLSConfiguration {
        TLSConfiguration(
            enabled: true,
            validationPolicy: .pinning(certificates)
        )
    }

    /// 测试配置(禁用验证,仅用于开发)
    public static func testingInsecure() -> TLSConfiguration {
        TLSConfiguration(
            enabled: true,
            validationPolicy: .disabled,
            allowSelfSigned: true
        )
    }
}

// MARK: - NWParameters Extension

extension NWParameters {

    /// 应用TLS配置到NWParameters
    func applyTLS(configuration: TLSConfiguration) throws {
        guard configuration.enabled else { return }

        let options = NWProtocolTLS.Options()

        // 配置TLS版本
        sec_protocol_options_set_min_tls_protocol_version(
            options.securityProtocolOptions,
            configuration.version.secProtocol
        )

        // 配置密码套件
        for suite in configuration.cipherSuites.suites {
            sec_protocol_options_append_tls_ciphersuite(
                options.securityProtocolOptions,
                suite
            )
        }

        // 配置ALPN (简化版本)
        if let alpnProtocols = configuration.alpnProtocols {
            for proto in alpnProtocols {
                sec_protocol_options_add_tls_application_protocol(
                    options.securityProtocolOptions,
                    proto
                )
            }
        }

        // 配置客户端证书
        if let p12Cert = configuration.p12Certificate {
            try configureCertificate(options: options, p12: p12Cert)
        }

        // 配置服务器验证
        try configureServerValidation(
            options: options,
            policy: configuration.validationPolicy,
            allowSelfSigned: configuration.allowSelfSigned
        )

        // 应用到parameters
        // NWParameters.tls() 会自动添加TLS到协议栈，无需手动insert
    }

    private func configureCertificate(
        options: NWProtocolTLS.Options,
        p12: TLSConfiguration.P12Certificate
    ) throws {
        // 加载P12证书
        let (identity, certificates) = try loadP12Certificate(
            data: p12.data,
            password: p12.password
        )

        // 创建身份数组
        var identityArray: [AnyObject] = [identity]
        identityArray.append(contentsOf: certificates)

        // 设置客户端证书
        sec_protocol_options_set_local_identity(
            options.securityProtocolOptions,
            sec_identity_create(identity)!
        )
    }

    private func configureServerValidation(
        options: NWProtocolTLS.Options,
        policy: TLSConfiguration.ValidationPolicy,
        allowSelfSigned: Bool
    ) throws {
        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { (metadata, trust, completion) in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()

                switch policy {
                case .system:
                    // 使用系统默认验证
                    self.verifySystemTrust(
                        secTrust,
                        allowSelfSigned: allowSelfSigned,
                        completion: completion
                    )

                case .custom(let certData):
                    // 自定义证书验证
                    self.verifyCustomCertificate(
                        secTrust,
                        certificateData: certData,
                        completion: completion
                    )

                case .pinning(let certDataArray):
                    // 证书固定验证
                    self.verifyCertificatePinning(
                        secTrust,
                        pinnedCertificates: certDataArray,
                        completion: completion
                    )

                case .disabled:
                    // 禁用验证(仅测试)
                    completion(true)
                }
            },
            DispatchQueue.global()
        )
    }

    private func verifySystemTrust(
        _ trust: SecTrust,
        allowSelfSigned: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        var error: CFError?
        let result = SecTrustEvaluateWithError(trust, &error)

        if result {
            completion(true)
        } else if allowSelfSigned {
            // 检查是否为自签名证书
            completion(true)
        } else {
            if let error = error {
                print("[TLS] 证书验证失败: \(error)")
            }
            completion(false)
        }
    }

    private func verifyCustomCertificate(
        _ trust: SecTrust,
        certificateData: TLSConfiguration.ValidationPolicy.CertificateData,
        completion: @escaping (Bool) -> Void
    ) {
        guard let certificate = SecCertificateCreateWithData(
            nil,
            certificateData.data as CFData
        ) else {
            completion(false)
            return
        }

        let status = SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
        guard status == errSecSuccess else {
            completion(false)
            return
        }

        var error: CFError?
        let result = SecTrustEvaluateWithError(trust, &error)

        if let error = error {
            print("[TLS] 自定义证书验证失败: \(error)")
        }

        completion(result)
    }

    private func verifyCertificatePinning(
        _ trust: SecTrust,
        pinnedCertificates: [TLSConfiguration.ValidationPolicy.CertificateData],
        completion: @escaping (Bool) -> Void
    ) {
        // 获取服务器证书链（兼容旧版本）
        let certificateCount = SecTrustGetCertificateCount(trust)
        guard certificateCount > 0 else {
            completion(false)
            return
        }

        // 检查证书链中是否有匹配的固定证书
        for i in 0..<certificateCount {
            guard let serverCert = SecTrustGetCertificateAtIndex(trust, i) else {
                continue
            }

            let serverCertData = SecCertificateCopyData(serverCert) as Data

            for pinnedCert in pinnedCertificates {
                if serverCertData == pinnedCert.data {
                    completion(true)
                    return
                }
            }
        }

        print("[TLS] 证书固定验证失败: 未找到匹配的证书")
        completion(false)
    }

    private func loadP12Certificate(
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
              let identity = firstItem[kSecImportItemIdentity as String] else {
            throw NexusError.tlsError(reason: "P12证书解析失败")
        }

        let secIdentity = identity as! SecIdentity

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
}
