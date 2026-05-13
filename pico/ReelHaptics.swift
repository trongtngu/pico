//
//  ReelHaptics.swift
//  pico
//
//  Created by OpenAI on 13/5/2026.
//

import CoreHaptics
import Combine
import UIKit

@MainActor
final class ReelHaptics: ObservableObject {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var fallbackGenerator: UIImpactFeedbackGenerator?
    private var fallbackTimer: Timer?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if !startContinuousBuzz() {
            startFallbackBuzz()
        }
    }

    func stop() {
        isRunning = false
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop(completionHandler: nil)
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        fallbackGenerator = nil
    }

    private func startContinuousBuzz() -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return false
        }

        do {
            let engine = try configuredEngine()
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.46),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.22)
                ],
                relativeTime: 0,
                duration: 1.4
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)

            self.player = player
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            player = nil
            engine?.stop(completionHandler: nil)
            return false
        }
    }

    private func configuredEngine() throws -> CHHapticEngine {
        if let engine {
            try engine.start()
            return engine
        }

        let engine = try CHHapticEngine()
        try engine.start()
        self.engine = engine
        return engine
    }

    private func startFallbackBuzz() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.44)
        fallbackGenerator = generator

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                generator.impactOccurred(intensity: 0.36)
                generator.prepare()
            }
        }
    }
}
