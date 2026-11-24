import ActivityKit
import Foundation

/// The lock-screen and Dynamic Island view of a session. Updated only when its state or mark
/// count changes (the timer is drawn by the system). Main thread only.
enum LiveActivity {
  private static var current: Activity<RecordingAttributes>?

  static func show(_ snap: EngineSnapshot) {
    guard snap.state != .idle else { return end() }
    let state = RecordingAttributes.ContentState(
      running: snap.state == .recording, label: label(snap), elapsedMs: snap.positionMs, at: Date(),
      marks: Int(snap.markCount))
    let content = ActivityContent(state: state, staleDate: nil)
    if let a = current {
      Task { await a.update(content) }
    } else if ActivityAuthorizationInfo().areActivitiesEnabled {
      current = try? Activity<RecordingAttributes>.request(attributes: RecordingAttributes(), content: content, pushType: nil)
    }
  }

  static func end() {
    guard let a = current else { return }
    current = nil
    Task { await a.end(nil, dismissalPolicy: .immediate) }
  }

  /// A session never outlives the process, so any activity found at launch is left over from a crash.
  static func endLeftovers() {
    for a in Activity<RecordingAttributes>.activities {
      Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
  }

  private static func label(_ s: EngineSnapshot) -> String {
    switch s.state {
    case .recording: return "Recording"
    case .paused: return "Paused"
    case .interrupted: return s.interruption == "call" ? "Paused: call" : "Checking microphone…"
    case .finalizing: return "Saving"
    default: return "Starting"
    }
  }
}
