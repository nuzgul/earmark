import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    EarmarkControls.perform = Self.performControl
    LiveActivity.endLeftovers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EarmarkEngine") {
      EngineHost.install(messenger: registrar.messenger())
    }
  }

  /// Live Activity buttons and the Control Center control run here, in the app process, even
  /// when the Flutter UI is not on screen.
  private static func performControl(_ action: String) async throws {
    let engine = RecorderEngine.shared
    switch action {
    case "mark":
      _ = try? engine.mark(source: "live_activity")
    case "toggle":
      await MainActor.run { _ = engine.snapshot().state == .paused ? engine.resume() : engine.pause() }
    case "stop":
      _ = await engine.stop()
    case "record_or_mark":
      if engine.isActive {
        _ = try engine.mark(source: "control")
      } else {
        guard AVAudioApplication.shared.recordPermission == .granted else {
          throw EngineError("Open Earmark once and allow the microphone.")
        }
        _ = try await MainActor.run { try engine.start() }
      }
    default:
      break
    }
  }
}
