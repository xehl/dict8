import AVFoundation
import Foundation

enum AudioPlaybackError: Error, Equatable, Sendable {
    case cueCreationFailed
    case previewCreationFailed
    case playbackStartFailed
}

@MainActor
protocol AudioPlaybackProviding: AnyObject {
    func playStartCue() async throws
    func playStopCue() async throws
    func playPreview(at url: URL) async throws
    func stop()
}

@MainActor
final class SystemAudioPlaybackService: AudioPlaybackProviding {
    private var player: AVAudioPlayer?
    private var playbackIdentifier = UUID()

    func playStartCue() async throws {
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: Self.makeCue(frequency: 660))
        } catch {
            throw AudioPlaybackError.cueCreationFailed
        }
        player.volume = 0.35
        try await play(player)
    }

    func playStopCue() async throws {
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: Self.makeCue(frequency: 440))
        } catch {
            throw AudioPlaybackError.cueCreationFailed
        }
        player.volume = 0.35
        try await play(player)
    }

    func playPreview(at url: URL) async throws {
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            throw AudioPlaybackError.previewCreationFailed
        }
        player.volume = 1
        try await play(player)
    }

    func stop() {
        playbackIdentifier = UUID()
        player?.stop()
        player = nil
    }

    private func play(_ newPlayer: AVAudioPlayer) async throws {
        stop()
        let identifier = UUID()
        playbackIdentifier = identifier
        player = newPlayer

        guard newPlayer.prepareToPlay(), newPlayer.play() else {
            player = nil
            throw AudioPlaybackError.playbackStartFailed
        }

        do {
            while newPlayer.isPlaying, playbackIdentifier == identifier {
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch {
            if playbackIdentifier == identifier {
                stop()
            }
            throw error
        }

        if playbackIdentifier == identifier {
            player = nil
        }
    }

    private static func makeCue(frequency: Double) -> Data {
        let sampleRate = 22_050
        let duration = 0.08
        let sampleCount = Int(Double(sampleRate) * duration)
        let dataSize = sampleCount * MemoryLayout<Int16>.size

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendLittleEndian(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * MemoryLayout<Int16>.size))
        data.appendLittleEndian(UInt16(MemoryLayout<Int16>.size))
        data.appendLittleEndian(UInt16(16))
        data.append(contentsOf: "data".utf8)
        data.appendLittleEndian(UInt32(dataSize))

        for index in 0..<sampleCount {
            let envelope = sin(Double.pi * Double(index) / Double(sampleCount))
            let wave = sin(2 * Double.pi * frequency * Double(index) / Double(sampleRate))
            let sample = Int16(Double(Int16.max) * 0.18 * envelope * wave)
            data.appendLittleEndian(sample)
        }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
