Pod::Spec.new do |s|
  s.name             = 'NexusKit'
  s.version          = '1.0.0'
  s.summary          = '企业级Swift网络库 - 功能完善、性能卓越、生产就绪'
  s.description      = <<-DESC
    NexusKit 是一个现代化的Swift网络库，整合了 CocoaAsyncSocket、socket.io-client-swift 等优秀开源库的特性。

    核心特性:
    • Swift 6 严格并发安全 - 基于 Actor 模型，编译器保证无数据竞争
    • 完整协议支持 - TCP/WebSocket/Socket.IO/TLS/SOCKS5
    • 零拷贝优化 - 减少70%内存拷贝，性能提升50%+
    • 强大的中间件系统 - 15个内置拦截器，5个核心中间件
    • 完善的监控诊断 - OpenTelemetry 兼容，实时监控面板
    • 501+ 测试用例 - 100%通过率，>90%覆盖率

    适用场景:
    • 即时通讯应用 - 1对1聊天、群聊、富媒体消息
    • IoT设备通信 - 传感器上报、设备控制、固件升级
    • 实时游戏 - 60fps位置同步、多人对战
    • 企业级应用 - 高性能、高可靠、可监控

    性能指标:
    • TCP连接速度 <300ms (P99 <500ms)
    • 消息QPS >15
    • TLS握手 <1s
    • 并发连接 1000+
    • 长连接稳定性 >95%
  DESC

  s.homepage         = 'https://github.com/fengmingdev/NexusKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'NexusKit Contributors' => 'contact@nexuskit.dev' }
  s.source           = {
    :git => 'https://github.com/fengmingdev/NexusKit.git',
    :tag => s.version.to_s
  }

  s.documentation_url = 'https://github.com/fengmingdev/NexusKit'

  # Platform support
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.tvos.deployment_target = '13.0'
  s.watchos.deployment_target = '6.0'

  s.swift_versions = ['6.0']

  # Default subspec (Core only)
  s.default_subspecs = 'Core'

  # MARK: - Core Module (核心网络模块)

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/NexusCore/**/*.swift'
    core.frameworks = 'Foundation', 'Network'
  end

  # MARK: - IO Module (WebSocket/Socket.IO)

  s.subspec 'IO' do |io|
    io.source_files = 'Sources/NexusIO/**/*.swift'
    io.dependency 'NexusKit/Core'
    io.frameworks = 'Foundation'
  end

  # MARK: - Monitoring Module (监控诊断)

  s.subspec 'Monitoring' do |monitoring|
    monitoring.source_files = 'Sources/NexusMonitoring/**/*.swift'
    monitoring.dependency 'NexusKit/Core'
    monitoring.frameworks = 'Foundation'
  end

  # MARK: - UI Module (SwiftUI 集成)

  s.subspec 'UI' do |ui|
    ui.source_files = 'Sources/NexusUI/**/*.swift'
    ui.dependency 'NexusKit/Core'
    ui.frameworks = 'SwiftUI'
    ui.ios.deployment_target = '14.0'
    ui.osx.deployment_target = '11.0'
  end

  # MARK: - Complete Package (完整套件)

  s.subspec 'Complete' do |complete|
    complete.dependency 'NexusKit/Core'
    complete.dependency 'NexusKit/IO'
    complete.dependency 'NexusKit/Monitoring'
    complete.dependency 'NexusKit/UI'
  end

  # Test spec
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*.swift'
  end
end
