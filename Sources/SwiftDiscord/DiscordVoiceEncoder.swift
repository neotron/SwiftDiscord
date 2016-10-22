import Foundation

public class DiscordVoiceEncoder {
	public let ffmpeg: Process
	public let readPipe: Pipe
	public let writePipe: Pipe

	private let readIO: DispatchIO
	private let readQueue = DispatchQueue(label: "discordVoiceEngine.readQueue")
	private let writeQueue = DispatchQueue(label: "discordEngine.writeQueue")

	private var encoderClosed = false

	public init(ffmpeg: Process, readPipe: Pipe, writePipe: Pipe) {
		self.ffmpeg = ffmpeg
		self.readPipe = readPipe
		self.writePipe = writePipe
		self.readIO = DispatchIO(type: .stream, fileDescriptor: writePipe.fileHandleForReading.fileDescriptor,
			queue: readQueue,
			cleanupHandler: {_ in })

		readIO.setLimit(lowWater: 1)

		self.ffmpeg.launch()
	}

	deinit {
		guard !encoderClosed else { return }

		closeEncoder()
	}

	// Abrubtly halts encoding and kills ffmpeg
	public func closeEncoder() {
		kill(ffmpeg.processIdentifier, SIGKILL)

		closeReader()
		ffmpeg.waitUntilExit()

		encoderClosed = true
	}

	public func closeReader() {
		readIO.close(flags: .stop)
		readQueue.sync {}
	}

	/// Call only when you know you've finished writing data, but ffmpeg is still encoding, or has data we haven't read
	/// This should cause ffmpeg to get an EOF on input, which will cause it to close once its output buffer is empty
	public func finishEncodingAndClose() {
		close(readPipe.fileHandleForWriting.fileDescriptor)
	}

	public func read(callback: @escaping (Bool, DispatchData?, Int32) -> Void) {
		assert(!encoderClosed, "Tried reading from a closed encoder")

		readIO.read(offset: 0, length: 320, queue: readQueue, ioHandler: callback)
	}

	public func write(_ data: Data, doneHandler: (() -> Void)? = nil) {
		assert(!encoderClosed, "Tried writing to a closed encoder")

		writeQueue.async {[weak self] in
			data.enumerateBytes {bytes, range, stop in
				let buf = UnsafeRawPointer(bytes.baseAddress!)
				var bytesRemaining = data.count

				while bytesRemaining > 0 {
					var bytesWritten: Int

					repeat {
						guard let fd = self?.readPipe.fileHandleForWriting.fileDescriptor else { return }

						bytesWritten = Darwin.write(fd, buf.advanced(by: data.count - bytesRemaining), bytesRemaining)
					} while bytesWritten < 0 && errno == EINTR

					if bytesWritten <= 0 {
						// Something went wrong
						break
					} else {
						bytesRemaining -= bytesWritten
					}
				}

				doneHandler?()
			}
		}
	}
}
