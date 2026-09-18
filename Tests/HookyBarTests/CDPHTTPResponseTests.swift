import Foundation
import Testing
@testable import HookyBar

struct CDPHTTPResponseTests {
    @Test func splitHeadersAndBodyAreAssembledOnce() throws {
        var parser = CDPHTTPResponse()
        for byte in Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n[".utf8) {
            #expect(try parser.append(Data([byte]), complete: false) == nil)
        }
        #expect(try parser.append(Data("]".utf8), complete: false) == Data("[]".utf8))
    }

    @Test func closeDelimitedResponseNeedsEOF() throws {
        var parser = CDPHTTPResponse()
        #expect(try parser.append(Data("HTTP/1.0 200 OK\r\n\r\n[]".utf8), complete: false) == nil)
        #expect(try parser.append(Data(), complete: true) == Data("[]".utf8))
    }

    @Test func rejectsRedirectsUnsupportedEncodingsAndInvalidLengths() {
        let responses = [
            "HTTP/1.1 302 Found\r\nLocation: http://example.com\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 1048577\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n[]",
            "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n[]",
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n[]"
        ]
        for response in responses {
            var parser = CDPHTTPResponse()
            #expect(throws: CDPHTTPResponse.Invalid.self) { try parser.append(Data(response.utf8), complete: true) }
        }
    }

    @Test func limitsApplyBeforeBufferingOversizedResponses() {
        var header = CDPHTTPResponse()
        #expect(throws: CDPHTTPResponse.Invalid.self) {
            try header.append(Data(repeating: 65, count: 16 * 1024 + 1), complete: false)
        }
        var body = CDPHTTPResponse()
        #expect(throws: CDPHTTPResponse.Invalid.self) {
            try body.append(Data(repeating: 65, count: CDPHTTPResponse.bodyLimit + 16 * 1024 + 1), complete: false)
        }
    }
}
