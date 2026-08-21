import AVFoundation
import Foundation

nonisolated enum TemporaryAudioMaintenanceError: Error, Equatable, Sendable {
    case cleanupFailed
}

nonisolated protocol TemporaryAudioMaintaining: Sendable {
    func sweepStaleRecordings(olderThan cutoff: Date) async throws -> Int
}

actor SystemTemporaryAudioMaintenance: TemporaryAudioMaintaining {
    nonisolated static let v0StaleRecordingAge: TimeInterval = 15 * 60

    private let fileManager: FileManager
    private let temporaryRoot: URL

    init(
        fileManager: FileManager = .default,
        temporaryRoot: URL? = nil
    ) {
        self.fileManager = fileManager
        self.temporaryRoot = temporaryRoot ?? fileManager.temporaryDirectory
    }

    func sweepStaleRecordings(olderThan cutoff: Date) async throws -> Int {
        let directory = temporaryRoot.appending(
            component: "dict8-recordings",
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }

        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .isRegularFileKey,
                ],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            throw TemporaryAudioMaintenanceError.cleanupFailed
        }

        var removedCount = 0
        for candidate in candidates where candidate.pathExtension.lowercased() == "m4a" {
            let values: URLResourceValues
            do {
                values = try candidate.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                )
            } catch {
                throw TemporaryAudioMaintenanceError.cleanupFailed
            }
            guard values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff else { continue }

            var removed = false
            for _ in 0..<2 {
                do {
                    try fileManager.removeItem(at: candidate)
                    removed = true
                    removedCount += 1
                    break
                } catch {
                    continue
                }
            }
            if !removed {
                throw TemporaryAudioMaintenanceError.cleanupFailed
            }
        }
        return removedCount
    }
}

nonisolated struct NoOpTemporaryAudioMaintenance: TemporaryAudioMaintaining {
    func sweepStaleRecordings(olderThan cutoff: Date) async throws -> Int { 0 }
}

enum AudioRecordingError: Error, Equatable, Sendable {
    case microphonePermissionRequired
    case alreadyRecording
    case noActiveRecording
    case temporaryDirectoryCreationFailed
    case recorderCreationFailed
    case recordingStartFailed
    case encodingFailed
    case invalidRecording
    case temporaryFileCleanupFailed
}

nonisolated struct RecordedAudioFile: Equatable, Sendable {
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: Int
    let bitRate: Int
}

@MainActor
protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    var elapsedTime: TimeInterval { get }
    var onMaximumDurationReached: ((Result<RecordedAudioFile, AudioRecordingError>) -> Void)? {
        get set
    }

    func prewarm()
    func start() throws
    func stop() throws -> RecordedAudioFile
    func cancel() throws
    func delete(_ recording: RecordedAudioFile) throws
}

extension AudioRecording {
    func prewarm() {}
}

@MainActor
protocol AudioRecorderDriving: AnyObject {
    var elapsedTime: TimeInterval { get }
    var onFinished: ((Bool) -> Void)? { get set }

    func prepareToRecord() -> Bool
    func record(forDuration duration: TimeInterval) -> Bool
    func stop()
}

@MainActor
final class SystemAudioRecordingService: AudioRecording {
    typealias RecorderFactory = (URL, [String: Any]) throws -> any AudioRecorderDriving

    static let maximumDuration: TimeInterval = 180
    /// Recordings shorter than this are treated as an accidental/near-instant
    /// chord tap rather than real speech. Below this duration there is
    /// essentially no speech signal, and sending the near-silent audio to
    /// the STT model reliably produces filler hallucinations (e.g. Whisper
    /// returning "Thank you" for silence) that would otherwise get pasted.
    /// Lowered to 0.7s (2026-08-17 per Eric's request) to support quick brief dictation
    /// phrases while filtering out accidental micro-taps.
    static let minimumDuration: TimeInterval = 0.7
    static let sampleRate = 16_000.0
    static let channelCount = 1
    static let bitRate = 32_000

    private struct ActiveRecording {
        let identifier: UUID
        let url: URL
        let driver: any AudioRecorderDriving
    }

    private struct PrewarmedRecorder {
        let identifier: UUID
        let url: URL
        let driver: any AudioRecorderDriving
    }

    var onMaximumDurationReached: ((Result<RecordedAudioFile, AudioRecordingError>) -> Void)?

    private let fileManager: FileManager
    private let temporaryRoot: URL
    private let permissionStatus: () -> MicrophonePermissionStatus
    private let recorderFactory: RecorderFactory
    private var activeRecording: ActiveRecording?
    private var prewarmedRecorder: PrewarmedRecorder?

    init(
        fileManager: FileManager = .default,
        temporaryRoot: URL? = nil,
        permissionStatus: @escaping () -> MicrophonePermissionStatus = {
            SystemMicrophonePermissionService().status
        },
        recorderFactory: @escaping RecorderFactory = { url, settings in
            try AVAudioRecorderDriver(url: url, settings: settings)
        }
    ) {
        self.fileManager = fileManager
        self.temporaryRoot = temporaryRoot ?? fileManager.temporaryDirectory
        self.permissionStatus = permissionStatus
        self.recorderFactory = recorderFactory
    }

    func prewarm() {
        guard permissionStatus() == .granted, activeRecording == nil, prewarmedRecorder == nil else {
            return
        }
        let directory = temporaryRoot.appending(
            component: "dict8-recordings",
            directoryHint: .isDirectory
        )
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appending(component: UUID().uuidString)
            .appendingPathExtension("m4a")
        guard let driver = try? recorderFactory(url, Self.settings),
              driver.prepareToRecord() else {
            try? removeIfPresent(url)
            return
        }
        prewarmedRecorder = PrewarmedRecorder(
            identifier: UUID(),
            url: url,
            driver: driver
        )
    }

    var isRecording: Bool {
        activeRecording != nil
    }

    var elapsedTime: TimeInterval {
        activeRecording?.driver.elapsedTime ?? 0
    }

    func start() throws {
        guard permissionStatus() == .granted else {
            throw AudioRecordingError.microphonePermissionRequired
        }
        guard activeRecording == nil else {
            throw AudioRecordingError.alreadyRecording
        }

        let identifier: UUID
        let url: URL
        let driver: any AudioRecorderDriving

        if let prewarmed = prewarmedRecorder {
            prewarmedRecorder = nil
            identifier = prewarmed.identifier
            url = prewarmed.url
            driver = prewarmed.driver
        } else {
            let directory = temporaryRoot.appending(
                component: "dict8-recordings",
                directoryHint: .isDirectory
            )
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                throw AudioRecordingError.temporaryDirectoryCreationFailed
            }

            url = directory
                .appending(component: UUID().uuidString)
                .appendingPathExtension("m4a")
            do {
                driver = try recorderFactory(url, Self.settings)
            } catch {
                try removeIfPresent(url)
                throw AudioRecordingError.recorderCreationFailed
            }
            identifier = UUID()
            guard driver.prepareToRecord() else {
                try removeIfPresent(url)
                throw AudioRecordingError.recordingStartFailed
            }
        }

        driver.onFinished = { [weak self] succeeded in
            self?.handleAutomaticFinish(identifier: identifier, succeeded: succeeded)
        }

        guard driver.record(forDuration: Self.maximumDuration) else {
            driver.onFinished = nil
            driver.stop()
            try removeIfPresent(url)
            throw AudioRecordingError.recordingStartFailed
        }

        activeRecording = ActiveRecording(
            identifier: identifier,
            url: url,
            driver: driver
        )
    }

    func stop() throws -> RecordedAudioFile {
        guard let activeRecording else {
            throw AudioRecordingError.noActiveRecording
        }

        let duration = activeRecording.driver.elapsedTime
        self.activeRecording = nil
        activeRecording.driver.onFinished = nil
        activeRecording.driver.stop()

        do {
            return try artifact(at: activeRecording.url, duration: duration)
        } catch {
            try removeIfPresent(activeRecording.url)
            throw error
        }
    }

    func cancel() throws {
        if let prewarmed = prewarmedRecorder {
            prewarmedRecorder = nil
            prewarmed.driver.stop()
            try? removeIfPresent(prewarmed.url)
        }
        guard let activeRecording else { return }
        self.activeRecording = nil
        activeRecording.driver.onFinished = nil
        activeRecording.driver.stop()
        try removeIfPresent(activeRecording.url)
    }

    func delete(_ recording: RecordedAudioFile) throws {
        try removeIfPresent(recording.url)
    }

    private func handleAutomaticFinish(identifier: UUID, succeeded: Bool) {
        guard let activeRecording,
              activeRecording.identifier == identifier else {
            return
        }

        self.activeRecording = nil
        activeRecording.driver.onFinished = nil

        guard succeeded else {
            do {
                try removeIfPresent(activeRecording.url)
                onMaximumDurationReached?(.failure(.encodingFailed))
            } catch {
                onMaximumDurationReached?(.failure(.temporaryFileCleanupFailed))
            }
            return
        }

        let duration = activeRecording.driver.elapsedTime
        guard duration >= Self.maximumDuration - 0.5 else {
            do {
                try removeIfPresent(activeRecording.url)
                onMaximumDurationReached?(.failure(.encodingFailed))
            } catch {
                onMaximumDurationReached?(.failure(.temporaryFileCleanupFailed))
            }
            return
        }

        do {
            let result = try artifact(
                at: activeRecording.url,
                duration: duration
            )
            onMaximumDurationReached?(.success(result))
        } catch let error as AudioRecordingError {
            do {
                try removeIfPresent(activeRecording.url)
                onMaximumDurationReached?(.failure(error))
            } catch {
                onMaximumDurationReached?(.failure(.temporaryFileCleanupFailed))
            }
        } catch {
            onMaximumDurationReached?(.failure(.invalidRecording))
        }
    }

    private func artifact(at url: URL, duration: TimeInterval) throws -> RecordedAudioFile {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw AudioRecordingError.invalidRecording
        }

        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              duration > 0 else {
            throw AudioRecordingError.invalidRecording
        }

        return RecordedAudioFile(
            url: url,
            duration: duration,
            sampleRate: Self.sampleRate,
            channelCount: Self.channelCount,
            bitRate: Self.bitRate
        )
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw AudioRecordingError.temporaryFileCleanupFailed
        }
    }

    private static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channelCount,
        AVEncoderBitRateKey: bitRate,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]
}

@MainActor
// AVAudioRecorderDelegate retains legacy nonisolated requirements; this adapter and recorder
// are created and serviced on the main run loop, so the preconcurrency bridge is intentional.
private final class AVAudioRecorderDriver: NSObject, AudioRecorderDriving, @preconcurrency AVAudioRecorderDelegate {
    var onFinished: ((Bool) -> Void)?

    private let recorder: AVAudioRecorder

    init(url: URL, settings: [String: Any]) throws {
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            throw AudioRecordingError.recorderCreationFailed
        }
        super.init()
        recorder.delegate = self
    }

    var elapsedTime: TimeInterval {
        recorder.currentTime
    }

    func prepareToRecord() -> Bool {
        recorder.prepareToRecord()
    }

    func record(forDuration duration: TimeInterval) -> Bool {
        recorder.record(forDuration: duration)
    }

    func stop() {
        recorder.stop()
    }

    func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        onFinished?(flag)
    }

    func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: (any Error)?
    ) {
        onFinished?(false)
    }
}
