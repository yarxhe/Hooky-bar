import Foundation
import Network

/// One bounded, loopback-only request. Network.framework supplies TCP and the
/// WebSocket handshake/framing; no URLSession/CFNetwork connection pool is used.
final class CDPLocalRequest: @unchecked Sendable {
    enum Kind { case discovery, evaluate(Int) }
    let reply = CDPReplyBox<Data>()
    private static let queue = DispatchQueue(label: "hooky.cdp.transport", qos: .userInitiated,
                                             autoreleaseFrequency: .workItem)
    private let connection: NWConnection
    private let kind: Kind
    private let message: Data
    private let lock = NSLock()
    private var stopped = false
    private var received = 0
    private var http = CDPHTTPResponse()

    init(connection: NWConnection, kind: Kind, message: Data) {
        self.connection = connection
        self.kind = kind
        self.message = message
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.isStopped else { return }
            switch state {
            case .ready: self.send()
            case .failed, .waiting, .cancelled: self.reply.resolve(nil)
            default: break
            }
        }
        connection.start(queue: Self.queue)
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func send() {
        let context: NWConnection.ContentContext
        switch kind {
        case .discovery: context = .defaultMessage
        case .evaluate:
            context = NWConnection.ContentContext(identifier: "hooky.cdp.evaluate",
                metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        }
        connection.send(content: message, contentContext: context, isComplete: true,
            completion: .contentProcessed { [weak self] error in
                guard let self, !self.isStopped else { return }
                if error != nil { self.reply.resolve(nil) } else { self.receive() }
            })
    }

    private func receive() {
        guard !isStopped else { return }
        switch kind {
        case .discovery:
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
                guard let self, !self.isStopped else { return }
                do {
                    if let body = try self.http.append(data ?? Data(), complete: complete) { self.reply.resolve(body) }
                    else if error != nil || complete { self.reply.resolve(nil) }
                    else { self.receive() }
                } catch { self.reply.resolve(nil) }
            }
        case .evaluate(let id):
            connection.receiveMessage { [weak self] data, context, _, error in
                guard let self, !self.isStopped else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                guard error == nil, metadata?.opcode != .close, let data else { self.reply.resolve(nil); return }
                if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (response["id"] as? NSNumber)?.intValue == id {
                    self.reply.resolve(data)
                } else {
                    self.received += 1
                    if self.received < 32 { self.receive() } else { self.reply.resolve(nil) }
                }
            }
        }
    }

    deinit { stop() }
}

/// Chromium DevTools /json/list uses a Content-Length response. Also accept
/// close-delimited HTTP/1.x. Redirects, compression and transfer encodings are
/// deliberately rejected: this is one fixed local endpoint, not a web browser.
struct CDPHTTPResponse {
    enum Invalid: Error { case response }
    static let bodyLimit = 1024 * 1024
    private var buffer = Data()
    private var bodyOffset: Int?
    private var contentLength: Int?

    mutating func append(_ bytes: Data, complete: Bool) throws -> Data? {
        guard buffer.count + bytes.count <= Self.bodyLimit + 16 * 1024 else { throw Invalid.response }
        buffer.append(bytes)
        if bodyOffset == nil {
            if let separator = buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard separator.upperBound <= 16 * 1024,
                      let header = String(data: buffer[..<separator.lowerBound], encoding: .utf8) else { throw Invalid.response }
                let lines = header.components(separatedBy: "\r\n")
                let status = lines[0].split(separator: " ")
                guard status.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(String(status[0])), status[1] == "200" else { throw Invalid.response }
                for line in lines.dropFirst() {
                    let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    guard pair.count == 2 else { throw Invalid.response }
                    let key = pair[0].lowercased()
                    let value = pair[1].trimmingCharacters(in: .whitespaces)
                    if key == "content-length" {
                        guard contentLength == nil, let length = Int(value), (0...Self.bodyLimit).contains(length) else { throw Invalid.response }
                        contentLength = length
                    }
                    if key == "transfer-encoding" || (key == "content-encoding" && value.lowercased() != "identity") { throw Invalid.response }
                }
                bodyOffset = separator.upperBound
            } else {
                guard buffer.count <= 16 * 1024, !complete else { throw Invalid.response }
                return nil
            }
        }
        guard let bodyOffset else { return nil }
        let size = buffer.count - bodyOffset
        guard size <= Self.bodyLimit else { throw Invalid.response }
        if let contentLength {
            guard size <= contentLength, !complete || size == contentLength else { throw Invalid.response }
            return size == contentLength ? Data(buffer[bodyOffset...]) : nil
        }
        return complete ? Data(buffer[bodyOffset...]) : nil
    }
}
