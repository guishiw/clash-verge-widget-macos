import Foundation

public struct RateSample: Equatable, Sendable {
    public let upload: Int64
    public let download: Int64
    public let uploadTotal: Int64
    public let downloadTotal: Int64
    public let connections: Int

    public init(
        upload: Int64,
        download: Int64,
        uploadTotal: Int64,
        downloadTotal: Int64,
        connections: Int
    ) {
        self.upload = upload
        self.download = download
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.connections = connections
    }
}

public struct RateSampler: Sendable {
    private var previousUpload: Int64?
    private var previousDownload: Int64?
    private var previousTime: TimeInterval?

    public init() {}

    public mutating func sample(
        uploadTotal: Int64,
        downloadTotal: Int64,
        connections: Int,
        at time: TimeInterval = Date().timeIntervalSince1970
    ) -> RateSample {
        let elapsed = max(0.001, time - (previousTime ?? time))
        let uploadDelta = max(0, uploadTotal - (previousUpload ?? uploadTotal))
        let downloadDelta = max(0, downloadTotal - (previousDownload ?? downloadTotal))
        let upload = previousTime == nil ? 0 : Int64(Double(uploadDelta) / elapsed)
        let download = previousTime == nil ? 0 : Int64(Double(downloadDelta) / elapsed)
        previousUpload = uploadTotal
        previousDownload = downloadTotal
        previousTime = time
        return RateSample(
            upload: upload,
            download: download,
            uploadTotal: uploadTotal,
            downloadTotal: downloadTotal,
            connections: connections
        )
    }
}
