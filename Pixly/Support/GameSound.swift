import AVFoundation

/// Pixly's sounds, synthesised at launch so there are no sound files to ship: the menu tick (the
/// click the Apple TV makes as focus moves), a chirp for every jump and a buzz for the crash.
enum GameSound: CaseIterable, Sendable {
    case tick, jump, crash

    static let sampleRate = 44_100

    /// Starts the sound without waiting for it: the press that caused it is never held up.
    func play() {
        SoundPlayer.shared.play(self)
    }

    /// The sound as samples between -1 and 1.
    func samples(sampleRate: Int = GameSound.sampleRate) -> [Double] {
        let rate = Double(sampleRate)
        switch self {
        case .tick:
            return (0..<(sampleRate * 30 / 1_000)).map { index in
                let time = Double(index) / rate
                let tone = sin(2 * .pi * 2_000 * time) * 0.7 + sin(2 * .pi * 3_100 * time) * 0.3
                return tone * exp(-time * 180) * 0.5
            }
        case .jump:
            // A quick upward chirp.
            return Self.sweep(from: 500, to: 1_000, duration: 0.08, rate: rate, noise: 0) { time in
                min(time / 0.004, 1) * exp(-time * 30) * 0.35
            }
        case .crash:
            // A falling, noisy buzz.
            return Self.sweep(from: 400, to: 60, duration: 0.35, rate: rate, noise: 0.45) { time in
                exp(-time * 9) * 0.55
            }
        }
    }

    private static func sweep(
        from start: Double,
        to end: Double,
        duration: Double,
        rate: Double,
        noise: Double,
        envelope: (Double) -> Double
    ) -> [Double] {
        let count = Int(duration * rate)
        var phase = 0.0
        var seed: UInt32 = 0x9E37_79B9
        return (0..<count).map { index in
            let frequency = start * pow(end / start, Double(index) / Double(count))
            phase += 2 * .pi * frequency / rate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let hiss = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            // A touch of the third harmonic gives it a little chiptune bite.
            let tone = sin(phase) * 0.8 + sin(phase * 3) * 0.2
            return (tone * (1 - noise) + hiss * noise) * envelope(Double(index) / rate)
        }
    }
}

/// Plays the sounds on an audio engine that keeps running: each sound is rendered into a buffer
/// once, and a press only schedules that buffer, on a queue of its own, so the main thread (and
/// the frame that shows the jump) never waits for audio.
final class SoundPlayer: @unchecked Sendable {
    static let shared = SoundPlayer()

    // Everything below is only touched on `queue`.
    private let queue = DispatchQueue(label: "ch.pandermatt.pixly.sound", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private var nodes: [GameSound: AVAudioPlayerNode] = [:]
    private var buffers: [GameSound: AVAudioPCMBuffer] = [:]

    private init() {
        queue.async {
            self.setUp()
        }
    }

    func play(_ sound: GameSound) {
        queue.async {
            guard let node = self.nodes[sound], let buffer = self.buffers[sound] else { return }
            // A call, an alarm or unplugged headphones stop the engine; start it again on demand.
            if !self.engine.isRunning {
                try? self.engine.start()
            }
            // A new jump cuts off the last one instead of queueing behind it.
            node.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !node.isPlaying {
                node.play()
            }
        }
    }

    private func setUp() {
        #if !os(macOS)
        // Silent with the ring/silent switch, and mixes with whatever music is playing.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(GameSound.sampleRate), channels: 1) else { return }
        for sound in GameSound.allCases {
            let samples = sound.samples()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0]
            else { continue }
            buffer.frameLength = buffer.frameCapacity
            for (index, sample) in samples.enumerated() {
                channel[index] = Float(sample) * 0.7
            }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes[sound] = node
            buffers[sound] = buffer
        }
        engine.prepare()
        try? engine.start()
    }
}
