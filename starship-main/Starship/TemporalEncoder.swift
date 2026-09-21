import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia
import CoreVideo

final class TemporalEncoder {
    enum EncoderError: Error { case noVideoTrack, reader, writer, session(OSStatus), append, finalize }

    func encode(source: URL, output: URL, loopCount: Int, bitrateMbps: Int, progress: @escaping (Int) -> Void) throws {
        let asset = AVAsset(url: source)
        guard let track = asset.tracks(withMediaType: .video).first else { throw EncoderError.noVideoTrack }
        let duration = asset.duration.seconds
        let fps = max(1.0, track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : 30.0)
        let width = Int(track.naturalSize.width); let height = Int(track.naturalSize.height)
        guard width > 0 && height > 0 else { throw EncoderError.noVideoTrack }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange]
        let outputReader = AVAssetReaderTrackOutput(track: track, outputSettings: settings); outputReader.alwaysCopiesSampleData = false
        reader.add(outputReader)
        guard reader.startReading() else { throw EncoderError.reader }
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let compression: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                kVTCompressionPropertyKey_AverageBitRate as String: bitrateMbps * 1_000_000,
                kVTCompressionPropertyKey_MaxKeyFrameInterval as String: Int(fps * 2),
                kVTCompressionPropertyKey_AllowOpenGOP as String: true,
                kVTCompressionPropertyKey_RealTime as String: false,
                kVTCompressionPropertyKey_BaseLayerFrameRate as String: fps / 2,
                kVTCompressionPropertyKey_BaseLayerBitRateFraction as String: 0.5
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: compression); input.expectsMediaDataInRealTime = false
        input.transform = track.preferredTransform
        writer.add(input)
        guard writer.startWriting() else { throw EncoderError.writer }
        writer.startSession(atSourceTime: .zero)
        var totalFrames = max(1.0, duration * fps * Double(loopCount)); var frameIndex = 0.0
        while input.isReadyForMoreMediaData {
            guard let sample = outputReader.copyNextSampleBuffer() else { break }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let dur = CMSampleBufferGetDuration(sample)
            for pass in 0..<loopCount {
                var timing = CMSampleTimingInfo(duration: dur, presentationTimeStamp: CMTimeAdd(pts, CMTimeMultiply(CMTime(seconds: duration * Double(pass), preferredTimescale: 600), multiplier: 1)), decodeTimeStamp: .invalid)
                var copy: CMSampleBuffer?
                CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
                if let copy { while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }; guard input.append(copy) else { throw EncoderError.append } }
                frameIndex += 1; progress(Int(min(99, frameIndex / totalFrames * 100)))
                if pass + 1 < loopCount { continue }
                break
            }
        }
        input.markAsFinished(); let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        guard writer.status == .completed else { throw EncoderError.finalize }
        progress(100)
    }
}
