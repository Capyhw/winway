import Foundation

public struct FileServiceError: Error, LocalizedError, Sendable, Equatable {
    public enum Code: String, Sendable { case invalidName, notFound, permissionDenied, readOnly, conflict, invalidDestination, sourceChanged, duplicateJob, cancelled, io }
    public let code: Code
    public let message: String
    public let path: String?
    public var errorDescription: String? { message }
    public init(_ code: Code, _ message: String, path: String? = nil) {
        self.code = code; self.message = message; self.path = path
    }
}

public struct FileSearchResult: Sendable {
    public let entries: [FileEntry]
    public let skippedCount: Int
    public var isTruncated: Bool = false
    public var isIndexing: Bool = false
    public var limitedAccess: Bool = false
}

public enum FileTransferKind: String, Sendable { case copy, move }
public enum FileConflictChoice: String, Sendable { case skip, keepBoth, cancel }
public struct FileConflict: Sendable {
    public let source: URL
    public let destination: URL
}
public struct FileTransferRequest: Sendable {
    public let id: UUID
    public let sources: [URL]
    public let destination: URL
    public let kind: FileTransferKind
    public init(id: UUID = UUID(), sources: [URL], destination: URL, kind: FileTransferKind) {
        self.id = id; self.sources = sources; self.destination = destination; self.kind = kind
    }
}
public enum FileOperationState: String, Sendable { case queued, running, awaitingConflict, completed, partial, failed, cancelled }
public enum FileItemOutcome: String, Sendable { case succeeded, skipped, failed, cancelled }
public struct FileItemResult: Sendable {
    public let source: URL
    public let destination: URL?
    public let outcome: FileItemOutcome
    public let error: FileServiceError?
    public let residualURLs: [URL]
}
public struct FileOperationProgress: Sendable {
    public let jobID: UUID
    public let total: Int
    public let processed: Int
    public let succeeded: Int
    public let failed: Int
    public let currentSource: URL?
    public let state: FileOperationState
}
public struct FileOperationReport: Sendable {
    public let jobID: UUID
    public let kind: FileTransferKind
    public let results: [FileItemResult]
    public let state: FileOperationState
    public var succeeded: Int { results.filter { $0.outcome == .succeeded }.count }
    public var failed: Int { results.filter { $0.outcome == .failed }.count }
}

/// Cancellation is observed between items and before committing a completed copy.
public final class FileOperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public var isCancelled: Bool { lock.withLock { value } }
    public func cancel() { lock.withLock { value = true } }
}

public protocol FileServing: Sendable {
    func listDirectory(_ directory: URL, includeHidden: Bool) async throws -> [FileEntry]
    func searchDirectory(_ directory: URL, query: String, includeHidden: Bool,
                         cancellation: FileOperationCancellation) async throws -> FileSearchResult
    func createDirectory(in directory: URL, name: String) async throws -> URL
    func rename(_ source: URL, to name: String) async throws -> URL
    func transfer(_ request: FileTransferRequest, cancellation: FileOperationCancellation,
                  onProgress: @escaping @Sendable (FileOperationProgress) -> Void,
                  resolveConflict: @escaping @Sendable (FileConflict) async -> FileConflictChoice) async -> FileOperationReport
}
