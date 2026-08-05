import Foundation

extension CompanionAPI {
    func fetchFeatures() async throws -> FeaturesResponse {
        try await get("features", as: FeaturesResponse.self)
    }

    func fetchConversations() async throws -> [ConversationSummary] {
        let (data, response) = try await session.data(for: authorizedRequest(path: "conversations", method: "GET"))
        try validate(response: response, data: data, isPairRequest: false)
        if let list = try? decoder.decode(ConversationListResponse.self, from: data) {
            return list.all
        }
        if let direct = try? decoder.decode([ConversationSummary].self, from: data) {
            return direct
        }
        struct Wrapper: Decodable { let data: [ConversationSummary]?; let items: [ConversationSummary]? }
        if let wrapped = try? decoder.decode(Wrapper.self, from: data) {
            return wrapped.data ?? wrapped.items ?? []
        }
        return []
    }

    func createConversation(title: String? = nil) async throws -> CreateConversationResponse {
        try await post("conversations", body: CreateConversationRequest(title: title), as: CreateConversationResponse.self)
    }

    func fetchConversation(id: String) async throws -> ConversationDetail {
        try await get("conversations/\(id)", as: ConversationDetail.self)
    }

    func deleteConversation(id: String) async throws {
        try await delete("conversations/\(id)")
    }

    func renameConversation(id: String, title: String) async throws {
        struct Body: Encodable { let title: String }
        let _: EmptyResponse = try await patch("conversations/\(id)", body: Body(title: title), as: EmptyResponse.self)
    }

    func fetchSyncEvents(since: String?) async throws -> SyncEventsResponse {
        var path = "sync/events"
        if let since, !since.isEmpty {
            path += "?since=\(since.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? since)"
        }
        return try await get(path, as: SyncEventsResponse.self)
    }

    func postTyping(conversationId: String, typing: Bool, draftPreview: String?, deviceId: String?) async throws {
        struct Body: Encodable {
            let conversation_id: String
            let typing: Bool
            let draft_preview: String?
            let device_id: String?
            let source: String
        }
        let _: EmptyResponse = try await post(
            "typing",
            body: Body(
                conversation_id: conversationId,
                typing: typing,
                draft_preview: draftPreview,
                device_id: deviceId,
                source: "mobile"
            ),
            as: EmptyResponse.self
        )
    }

    func streamChatV2(message: String, conversationId: String?, mode: AIMode) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        streamSSEChunks(
            path: "chat",
            body: ChatRequestV2(message: message, conversationId: conversationId, stream: true, mode: mode == .auto ? nil : mode.rawValue)
        )
    }

    func uploadVisionImage(imageData: Data, filename: String, message: String?, conversationId: String?) async throws -> VisionUploadResult {
        var fields: [String: String] = [:]
        if let message, !message.isEmpty { fields["message"] = message }
        if let conversationId { fields["conversation_id"] = conversationId }

        do {
            return try await uploadMultipart("vision", fileData: imageData, filename: filename, mime: "image/jpeg", fields: fields, as: VisionUploadResult.self)
        } catch {
            return try await uploadMultipart("chat", fileData: imageData, filename: filename, mime: "image/jpeg", fields: fields, as: VisionUploadResult.self)
        }
    }

    func generateImage(prompt: String, conversationId: String?) async throws -> ImageGenerateResponse {
        var request = try authorizedRequest(path: "images/txt2img", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // SD on CPU can take several minutes — must outlive default 20s request timeout
        request.timeoutInterval = 360
        request.httpBody = try encoder.encode(
            ImageGenerateRequest(prompt: prompt, conversationId: conversationId)
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(ImageGenerateResponse.self, from: data)
    }

    func imageProgress(jobId: String? = nil) async throws -> ImageProgressResponse {
        var path = "images/progress"
        if let jobId { path += "?job_id=\(jobId)" }
        var request = try authorizedRequest(path: path, method: "GET")
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(ImageProgressResponse.self, from: data)
    }

    func interruptImage() async throws {
        let _: ImageInterruptResponse = try await post("images/interrupt", body: EmptyBody(), as: ImageInterruptResponse.self)
    }

    func fetchCodeSessions() async throws -> [CodeSession] {
        let res: CodeSessionListResponse = try await get("code/sessions", as: CodeSessionListResponse.self)
        return res.all
    }

    func createCodeSession(title: String?, language: String?) async throws -> CodeSession {
        try await post("code/sessions", body: CreateCodeSessionRequest(title: title, language: language), as: CodeSession.self)
    }

    func initCodeWorkspace(sessionId: String) async throws {
        let _: EmptyResponse = try await post("code/sessions/\(sessionId)/init-workspace", body: EmptyBody(), as: EmptyResponse.self)
    }

    func streamCodeChat(sessionId: String, message: String) -> AsyncThrowingStream<String, Error> {
        streamSSE(path: "code/sessions/\(sessionId)/chat", body: CodeChatRequest(message: message, stream: true))
    }

    // MARK: - HTTP helpers

    private struct EmptyBody: Encodable {}
    private struct EmptyResponse: Decodable {}

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: authorizedRequest(path: path, method: "GET"))
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        var request = try authorizedRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        if data.isEmpty, T.self == EmptyResponse.self { return EmptyResponse() as! T }
        return try decoder.decode(T.self, from: data)
    }

    private func patch<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        var request = try authorizedRequest(path: path, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        let (data, response) = try await session.data(for: authorizedRequest(path: path, method: "DELETE"))
        try validate(response: response, data: data, isPairRequest: false)
    }

    private func uploadMultipart<T: Decodable>(
        _ path: String,
        fileData: Data,
        filename: String,
        mime: String,
        fields: [String: String],
        as type: T.Type
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try authorizedRequest(path: path, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(T.self, from: data)
    }

    private func authorizedRequest(path: String, method: String) throws -> URLRequest {
        // CRITICAL: URL(string:relativeTo:) replaces the last path segment when baseURL
        // has no trailing slash ("…/api/v1" + "chat" → "…/api/chat"). Always append.
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathOnly = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = baseURL
        for segment in pathOnly.split(separator: "/") {
            url = url.appendingPathComponent(String(segment))
        }
        if parts.count > 1, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.percentEncodedQuery = String(parts[1])
            if let withQuery = comps.url { url = withQuery }
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    func streamSSEChunks<B: Encodable>(path: String, body: B) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try authorizedRequest(path: path, method: "POST")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try encoder.encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw CompanionAPIError.server("Keine Server-Antwort")
                    }
                    guard (200...299).contains(http.statusCode) else {
                        // Collect a short body for better errors (e.g. Unbekannte Route)
                        var errData = Data()
                        for try await b in bytes.prefix(4096) { errData.append(b) }
                        let msg = String(data: errData, encoding: .utf8) ?? ""
                        if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
                        if msg.lowercased().contains("unbekannte route") || http.statusCode == 404 {
                            throw CompanionAPIError.server("API-Route fehlt (\(path)) — Companion Server neu starten?")
                        }
                        throw CompanionAPIError.server(msg.isEmpty ? "Stream-Fehler HTTP \(http.statusCode)" : msg)
                    }

                    var lineBuffer = ""
                    for try await byte in bytes {
                        let char = Character(UnicodeScalar(byte))
                        if char == "\n" {
                            if let chunk = try parseSSEChunk(lineBuffer) {
                                continuation.yield(chunk)
                                if chunk.done == true { break }
                            }
                            lineBuffer = ""
                        } else if char != "\r" {
                            lineBuffer.append(char)
                        }
                    }
                    if !lineBuffer.isEmpty, let chunk = try parseSSEChunk(lineBuffer) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapNetworkError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func parseSSEChunk(_ line: String) throws -> ChatStreamChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return ChatStreamChunk(content: nil, done: true, error: nil, conversationId: nil, messageId: nil, imageUrl: nil) }
        guard let data = payload.data(using: .utf8),
              let chunk = try? decoder.decode(ChatStreamChunk.self, from: data) else { return nil }
        if let error = chunk.error, !error.isEmpty { throw CompanionAPIError.server(error) }
        return chunk
    }

    func streamSSE<B: Encodable>(path: String, body: B) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try authorizedRequest(path: path, method: "POST")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try encoder.encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw CompanionAPIError.server("Keine Server-Antwort")
                    }
                    guard (200...299).contains(http.statusCode) else {
                        // Collect a short body for better errors (e.g. Unbekannte Route)
                        var errData = Data()
                        for try await b in bytes.prefix(4096) { errData.append(b) }
                        let msg = String(data: errData, encoding: .utf8) ?? ""
                        if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
                        if msg.lowercased().contains("unbekannte route") || http.statusCode == 404 {
                            throw CompanionAPIError.server("API-Route fehlt (\(path)) — Companion Server neu starten?")
                        }
                        throw CompanionAPIError.server(msg.isEmpty ? "Stream-Fehler HTTP \(http.statusCode)" : msg)
                    }

                    var lineBuffer = ""
                    for try await byte in bytes {
                        let char = Character(UnicodeScalar(byte))
                        if char == "\n" {
                            try processSSELine(lineBuffer, continuation: continuation)
                            lineBuffer = ""
                        } else if char != "\r" {
                            lineBuffer.append(char)
                        }
                    }
                    if !lineBuffer.isEmpty { try processSSELine(lineBuffer, continuation: continuation) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapNetworkError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}