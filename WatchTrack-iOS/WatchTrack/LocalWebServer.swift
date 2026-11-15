import Combine
import Foundation
import Network

/// Serves the bundled website on an IPv4 loopback socket only.
/// A fixed origin keeps WebKit localStorage stable between app launches.
final class LocalWebServer: ObservableObject {
    @Published private(set) var baseURL: URL?
    @Published private(set) var errorMessage: String?

    private let queue = DispatchQueue(label: "com.watchtrack.ios.local-web-server")
    private let port = NWEndpoint.Port(rawValue: 8765)!
    private var listener: NWListener?

    private var webRoot: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("www", isDirectory: true)
    }

    func start() {
        guard listener == nil else { return }
        errorMessage = nil

        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: port
            )

            let newListener = try NWListener(using: parameters)
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self?.baseURL = URL(string: "http://127.0.0.1:8765/index.html")
                    }
                case .failed(let error):
                    DispatchQueue.main.async {
                        self?.errorMessage = "The local app server couldn’t start: \(error.localizedDescription)"
                        self?.listener?.cancel()
                        self?.listener = nil
                    }
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                self.handle(connection)
            }

            listener = newListener
            newListener.start(queue: queue)
        } catch {
            errorMessage = "The local app server couldn’t start: \(error.localizedDescription)"
        }
    }

    deinit {
        listener?.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeader(from: connection, accumulated: Data())
    }

    private func receiveHeader(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            var request = accumulated
            if let data {
                request.append(data)
            }

            let headerComplete = request.range(of: Data([13, 10, 13, 10])) != nil
            if headerComplete || isComplete || error != nil || request.count >= 64 * 1024 {
                self?.respond(to: connection, request: request)
            } else {
                self?.receiveHeader(from: connection, accumulated: request)
            }
        }
    }

    private func respond(to connection: NWConnection, request: Data) {
        let requestText = String(decoding: request, as: UTF8.self)
        let requestLine = requestText.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")

        guard parts.count >= 2 else {
            send(connection, status: 400, reason: "Bad Request", contentType: "text/plain", body: Data("Bad request".utf8), method: "GET")
            return
        }

        let method = String(parts[0]).uppercased()
        guard method == "GET" || method == "HEAD" else {
            send(connection, status: 405, reason: "Method Not Allowed", contentType: "text/plain", body: Data("Method not allowed".utf8), method: method)
            return
        }

        let rawTarget = String(parts[1])
        let pathOnly = rawTarget.components(separatedBy: "?").first ?? "/"
        guard let decodedPath = pathOnly.removingPercentEncoding, decodedPath.hasPrefix("/") else {
            send(connection, status: 400, reason: "Bad Request", contentType: "text/plain", body: Data("Invalid path".utf8), method: method)
            return
        }

        let relativePath = decodedPath == "/" ? "index.html" : String(decodedPath.dropFirst())
        let pathParts = relativePath.split(separator: "/")
        guard !relativePath.isEmpty, !pathParts.contains(".."), let root = webRoot else {
            send(connection, status: 403, reason: "Forbidden", contentType: "text/plain", body: Data("Forbidden".utf8), method: method)
            return
        }

        let rootPath = root.standardizedFileURL.path
        let fileURL = root.appendingPathComponent(relativePath).standardizedFileURL
        guard fileURL.path.hasPrefix(rootPath + "/") else {
            send(connection, status: 403, reason: "Forbidden", contentType: "text/plain", body: Data("Forbidden".utf8), method: method)
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            send(connection, status: 404, reason: "Not Found", contentType: "text/plain", body: Data("Not found".utf8), method: method)
            return
        }

        do {
            let body = try Data(contentsOf: fileURL)
            send(
                connection,
                status: 200,
                reason: "OK",
                contentType: contentType(for: fileURL.pathExtension),
                body: body,
                method: method
            )
        } catch {
            send(connection, status: 500, reason: "Internal Server Error", contentType: "text/plain", body: Data("Could not read app resource".utf8), method: method)
        }
    }

    private func contentType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }

    private func send(
        _ connection: NWConnection,
        status: Int,
        reason: String,
        contentType: String,
        body: Data,
        method: String
    ) {
        let headers = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        X-Content-Type-Options: nosniff\r
        Connection: close\r
        \r

        """
        var response = Data(headers.utf8)
        if method != "HEAD" {
            response.append(body)
        }

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
