import AVFoundation
import Foundation

// The approach is adapted from kulikov0/whitelist-bypass (MIT).
// See THIRD_PARTY_NOTICES.md. This app is intended for sideloading: using
// silent audio only to keep networking alive is not suitable for App Store review.
@MainActor
final class BackgroundKeepAlive {
    private var player: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private var shouldRun = false

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverAfterMediaServicesReset() }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() throws {
        shouldRun = true
        try activateAndPlay()
    }

    private func activateAndPlay() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
        try session.setActive(true)

        if let player {
            guard player.play() else {
                throw backgroundError()
            }
            return
        }

        let data = makeSilentWave()
        let audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer.numberOfLoops = -1
        audioPlayer.volume = 0
        audioPlayer.prepareToPlay()
        guard audioPlayer.play() else {
            throw backgroundError()
        }
        player = audioPlayer
    }

    func stop() {
        shouldRun = false
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func handleInterruption(_ notification: Notification) {
        guard shouldRun,
              let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawType) == .ended else {
            return
        }
        scheduleRecovery()
    }

    private func recoverAfterMediaServicesReset() {
        guard shouldRun else { return }
        player = nil
        scheduleRecovery()
    }

    private func scheduleRecovery() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.shouldRun else { return }
            try? self.activateAndPlay()
        }
    }

    private func makeSilentWave() -> Data {
        let sampleRate = 8_000
        let channels = 1
        let bitsPerSample = 16
        let sampleCount = sampleRate
        let payloadSize = sampleCount * channels * bitsPerSample / 8
        var data = Data()

        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36 + payloadSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(channels))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * channels * bitsPerSample / 8))
        data.appendLittleEndian(UInt16(channels * bitsPerSample / 8))
        data.appendLittleEndian(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(UInt32(payloadSize))
        data.append(Data(count: payloadSize))
        return data
    }

    private func backgroundError() -> NSError {
        NSError(
            domain: "OlcrtcIOS.BackgroundKeepAlive",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Не удалось запустить фоновый режим"]
        )
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
