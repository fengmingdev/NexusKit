Pod::Spec.new do |s|
  s.name             = 'NexusKit'
  s.version          = '1.0.0'
  s.summary          = 'The Modern Socket Framework for Swift'
  s.description      = <<-DESC
    NexusKit is a powerful, type-safe socket framework that brings modern Swift
    concurrency to network programming. Built with Swift 5.5+ features like async/await
    and AsyncStream, it provides a clean, intuitive API for TCP, WebSocket, and Socket.IO
    connections with advanced features like connection pooling, middleware system, and
    automatic reconnection.

    Features:
    • Modern Swift with async/await
    • Type-safe with generics and Codable
    • Multi-protocol support (TCP, WebSocket, Socket.IO)
    • Middleware pipeline system
    • Smart reconnection strategies
    • Connection pooling
    • Built-in metrics and logging
    • TLS/SSL and proxy support
  DESC

  s.homepage         = 'https://github.com/yourorg/NexusKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'NexusKit Contributors' => 'nexuskit@example.com' }
  s.source           = {
    :git => 'https://github.com/yourorg/NexusKit.git',
    :tag => s.version.to_s
  }

  s.social_media_url = 'https://twitter.com/nexuskit'
  s.documentation_url = 'https://yourorg.github.io/NexusKit'

  # Platform support
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.tvos.deployment_target = '13.0'
  s.watchos.deployment_target = '6.0'

  s.swift_versions = ['5.5', '5.6', '5.7', '5.8', '5.9']

  # Default subspecs (Core + TCP)
  s.default_subspecs = 'Core', 'TCP'

  # MARK: - Core Module (Required)

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/NexusCore/**/*.swift'
    core.frameworks = 'Foundation'

    core.dependency 'SwiftLog', '~> 1.5'
  end

  # MARK: - TCP Module

  s.subspec 'TCP' do |tcp|
    tcp.source_files = 'Sources/NexusTCP/**/*.swift'
    tcp.dependency 'NexusKit/Core'
    tcp.dependency 'SwiftProtobuf', '~> 1.20'

    tcp.frameworks = 'Foundation'
    tcp.ios.frameworks = 'Network'
  end

  # MARK: - WebSocket Module

  s.subspec 'WebSocket' do |ws|
    ws.source_files = 'Sources/NexusWebSocket/**/*.swift'
    ws.dependency 'NexusKit/Core'

    ws.frameworks = 'Foundation'
  end

  # MARK: - Socket.IO Module

  s.subspec 'IO' do |io|
    io.source_files = 'Sources/NexusIO/**/*.swift'
    io.dependency 'NexusKit/Core'
    io.dependency 'NexusKit/WebSocket'

    io.frameworks = 'Foundation'
  end

  # MARK: - Security Module

  s.subspec 'Secure' do |secure|
    secure.source_files = 'Sources/NexusSecure/**/*.swift'
    secure.dependency 'NexusKit/Core'

    secure.frameworks = 'Foundation', 'Security'
  end

  # MARK: - Middleware: Compression

  s.subspec 'Compression' do |compression|
    compression.source_files = 'Middlewares/NexusMiddlewareCompression/**/*.swift'
    compression.dependency 'NexusKit/Core'

    compression.frameworks = 'Foundation'
    compression.libraries = 'compression'
  end

  # MARK: - Middleware: Encryption

  s.subspec 'Encryption' do |encryption|
    encryption.source_files = 'Middlewares/NexusMiddlewareEncryption/**/*.swift'
    encryption.dependency 'NexusKit/Core'

    encryption.frameworks = 'Foundation', 'CryptoKit'
  end

  # MARK: - Middleware: Logging

  s.subspec 'Logging' do |logging|
    logging.source_files = 'Middlewares/NexusMiddlewareLogging/**/*.swift'
    logging.dependency 'NexusKit/Core'
    logging.dependency 'SwiftLog', '~> 1.5'

    logging.frameworks = 'Foundation'
  end

  # MARK: - Middleware: Metrics

  s.subspec 'Metrics' do |metrics|
    metrics.source_files = 'Middlewares/NexusMiddlewareMetrics/**/*.swift'
    metrics.dependency 'NexusKit/Core'

    metrics.frameworks = 'Foundation'
  end

  # MARK: - Complete Package

  s.subspec 'All' do |all|
    all.dependency 'NexusKit/Core'
    all.dependency 'NexusKit/TCP'
    all.dependency 'NexusKit/WebSocket'
    all.dependency 'NexusKit/IO'
    all.dependency 'NexusKit/Secure'
    all.dependency 'NexusKit/Compression'
    all.dependency 'NexusKit/Encryption'
    all.dependency 'NexusKit/Logging'
    all.dependency 'NexusKit/Metrics'
  end

  # Test spec
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*.swift'
  end
end
