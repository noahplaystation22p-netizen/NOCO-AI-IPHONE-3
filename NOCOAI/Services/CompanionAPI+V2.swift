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

    func postMode(_ mode: AIMode) async throws {
        struct Body: Encodable {
            let mode: String
            let source: String
        }
        let wire = mode.wireModeValue ?? "auto"
        let _: EmptyResponse = try await post(
            "mode",
            body: Body(mode: wire, source: "mobile"),
            as: EmptyResponse.self
        )
    }

    func fetchProfile() async throws -> NocoUserProfile {
        try await get("profile", as: NocoUserProfile.self)
    }

    func saveProfile(_ profile: NocoUserProfile) async throws -> NocoUserProfile {
        try await post("profile", body: profile, as: NocoUserProfile.self)
    }

    func streamChatV2(
        message: String,
        conversationId: String?,
        mode: AIMode,
        speak: Bool = false,
        agentPower: Bool = false
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let modeValue: String?
        if speak {
            modeValue = "flash"
        } else if agentPower {
            modeValue = "think"
        } else {
            modeValue = mode.wireModeValue
        }
        return streamSSEChunks(
            path: "chat",
            body: ChatRequestV2(
                message: message,
                conversationId: conversationId,
                stream: true,
                mode: modeValue,
                speak: speak ? true : nil,
                agent: agentPower ? true : nil
            )
        )
    }

    func uploadVisionImage(
        imageData: Data,
        filename: String,
        message: String?,
        conversationId: String?,
        qualityProfile: String? = nil,
        ocrLength: Int? = nil,
        source: String? = nil
    ) async throws -> VisionUploadResult {
        var fields: [String: String] = [:]
        let caption = (message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? message!
            : """
            [NOCO VISION] Ein Bild ist angehängt. Beschreibe ausführlich auf Deutsch, was sichtbar ist. \
            Du kannst Bilder sehen. Antworte nie, dass du keine Bilder anzeigen oder beschreiben kannst.
            """
        fields["message"] = caption
        if let conversationId { fields["conversation_id"] = conversationId }
        if let qualityProfile, !qualityProfile.isEmpty { fields["quality_profile"] = qualityProfile }
        if let ocrLength { fields["ocr_length"] = String(ocrLength) }
        if let source, !source.isEmpty { fields["source"] = source }

        // Do NOT fall back to /chat — that duplicates the user-image on the PC.
        return try await uploadMultipart(
            "vision",
            fileData: imageData,
            filename: filename,
            mime: "image/jpeg",
            fields: fields,
            as: VisionUploadResult.self,
            timeout: 180
        )
    }

    func interruptChat(conversationId: String?) async throws {
        struct Body: Encodable {
            let conversationId: String?
        }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await post("chat/interrupt", body: Body(conversationId: conversationId), as: Resp.self)
    }

    // MARK: - NOCO Agent

    func listAgentTasks() async throws -> [AgentTask] {
        let resp: AgentTaskListResponse = try await get("agent/tasks", as: AgentTaskListResponse.self)
        return resp.tasks ?? []
    }

    func getAgentTask(id: String) async throws -> AgentTask {
        let resp: AgentTaskResponse = try await get("agent/tasks/\(id)", as: AgentTaskResponse.self)
        guard let task = resp.task else { throw CompanionAPIError.server(resp.error ?? "Aufgabe fehlt") }
        return task
    }

    func createAgentTask(
        goal: String,
        mode: AgentMode,
        kind: AgentKind = .general,
        autoRun: Bool = true,
        qualityProfile: AgentQualityProfile = .auto,
        source: String = "mobile"
    ) async throws -> AgentTask {
        struct Body: Encodable {
            let goal: String
            let mode: String
            let kind: String
            let source: String
            let auto_run: Bool
            let quality_profile: String
        }
        var request = try authorizedRequest(path: "agent/tasks", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        request.httpBody = try encoder.encode(
            Body(
                goal: goal,
                mode: mode.rawValue,
                kind: kind.rawValue,
                source: source,
                auto_run: autoRun,
                quality_profile: qualityProfile.rawValue
            )
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        let resp = try decoder.decode(AgentTaskResponse.self, from: data)
        guard let task = resp.task else {
            throw CompanionAPIError.server(resp.error ?? "Agent-Antwort leer")
        }
        return task
    }

    func runAgentTask(id: String) async throws -> AgentTask {
        var request = try authorizedRequest(path: "agent/tasks/\(id)/run", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        let resp = try decoder.decode(AgentTaskResponse.self, from: data)
        guard let task = resp.task else {
            throw CompanionAPIError.server(resp.error ?? "Agent-Antwort leer")
        }
        return task
    }

    func confirmAgentStep(taskId: String, stepId: String, allow: Bool) async throws -> AgentTask {
        struct Body: Encodable {
            let step_id: String
            let allow: Bool
        }
        var request = try authorizedRequest(path: "agent/tasks/\(taskId)/confirm", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        request.httpBody = try encoder.encode(Body(step_id: stepId, allow: allow))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        let resp = try decoder.decode(AgentTaskResponse.self, from: data)
        guard let task = resp.task else {
            throw CompanionAPIError.server(resp.error ?? "Agent-Antwort leer")
        }
        return task
    }

    func cancelAgentTask(id: String) async throws -> AgentTask {
        let resp: AgentTaskResponse = try await post(
            "agent/tasks/\(id)/cancel",
            body: EmptyBody(),
            as: AgentTaskResponse.self
        )
        guard let task = resp.task else {
            throw CompanionAPIError.server(resp.error ?? "Agent-Antwort leer")
        }
        return task
    }

    func listAgentProjects() async throws -> [AgentProject] {
        let resp: AgentProjectsResponse = try await get("agent/projects", as: AgentProjectsResponse.self)
        return resp.projects ?? []
    }

    func fetchAgentMemory() async throws -> AgentMemorySnapshot? {
        struct Resp: Decodable { let memory: AgentMemorySnapshot? }
        let resp: Resp = try await get("agent/memory", as: Resp.self)
        return resp.memory
    }

    // MARK: - Computer Control

    func fetchComputerControlStatus() async throws -> ComputerControlStatus {
        try await get("computer/status", as: ComputerControlStatus.self)
    }

    func setComputerControlPermission(
        enabled: Bool,
        allowMouse: Bool,
        allowKeyboard: Bool,
        allowOpenApps: Bool,
        allowWindowFocus: Bool,
        confirmEveryInput: Bool
    ) async throws -> ComputerControlStatus {
        struct Body: Encodable {
            let enabled: Bool
            let allowMouse: Bool
            let allowKeyboard: Bool
            let allowOpenApps: Bool
            let allowWindowFocus: Bool
            let confirmEveryInput: Bool
        }
        return try await post(
            "computer/permission",
            body: Body(
                enabled: enabled,
                allowMouse: allowMouse,
                allowKeyboard: allowKeyboard,
                allowOpenApps: allowOpenApps,
                allowWindowFocus: allowWindowFocus,
                confirmEveryInput: confirmEveryInput
            ),
            as: ComputerControlStatus.self
        )
    }

    func pauseComputerControl() async throws -> ComputerControlStatus {
        try await post("computer/pause", body: EmptyBody(), as: ComputerControlStatus.self)
    }

    func resumeComputerControl() async throws -> ComputerControlStatus {
        try await post("computer/resume", body: EmptyBody(), as: ComputerControlStatus.self)
    }

    func executeComputerAction(action: String, extras: [String: String] = [:]) async throws -> ComputerControlStatus {
        struct Body: Encodable {
            let action: String
            let question: String?
            let confirm: Bool?
        }
        return try await post(
            "computer/execute",
            body: Body(action: action, question: extras["question"], confirm: extras["confirm"] == "true"),
            as: ComputerControlStatus.self
        )
    }

    func generateImage(
        prompt: String,
        conversationId: String?,
        width: Int = 384,
        height: Int = 384,
        steps: Int = 6
    ) async throws -> ImageGenerateResponse {
        var request = try authorizedRequest(path: "images/txt2img", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // SD on CPU can take several minutes — must outlive default 20s request timeout
        request.timeoutInterval = 360
        request.httpBody = try encoder.encode(
            ImageGenerateRequest(
                prompt: prompt,
                conversationId: conversationId,
                width: width,
                height: height,
                steps: steps
            )
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(ImageGenerateResponse.self, from: data)
    }

    /// Edit an existing photo with Stable Diffusion img2img (remove object, recolor hair, etc.).
    func editImage(
        prompt: String,
        imageJPEG: Data,
        conversationId: String?,
        denoisingStrength: Double
    ) async throws -> ImageGenerateResponse {
        var request = try authorizedRequest(path: "images/img2img", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 360
        request.httpBody = try encoder.encode(
            ImageEditRequest(
                prompt: prompt,
                imageBase64: imageJPEG.base64EncodedString(),
                conversationId: conversationId,
                denoisingStrength: denoisingStrength
            )
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(ImageGenerateResponse.self, from: data)
    }

    /// Magical eraser — paint mask (white = edit) + instruction → SD inpaint (masked region only).
    func inpaintImage(
        prompt: String,
        imageJPEG: Data,
        maskPNG: Data,
        conversationId: String?,
        denoisingStrength: Double = 0.82,
        steps: Int = 14
    ) async throws -> ImageGenerateResponse {
        struct Body: Encodable {
            let prompt: String
            let imageBase64: String
            let maskBase64: String
            let conversationId: String?
            let width: Int
            let height: Int
            let steps: Int
            let denoisingStrength: Double
        }
        let body = Body(
            prompt: prompt,
            imageBase64: imageJPEG.base64EncodedString(),
            maskBase64: maskPNG.base64EncodedString(),
            conversationId: conversationId,
            width: 512,
            height: 512,
            steps: steps,
            denoisingStrength: denoisingStrength
        )
        guard !body.imageBase64.isEmpty, !body.maskBase64.isEmpty, !prompt.isEmpty else {
            throw CompanionAPIError.server("Bild/Maske leer — erneut bemalen und tippen")
        }
        // Encoder uses snake_case globally — companion accepts both.
        var lastError: Error?
        for path in ["images/inpaint", "images/erase", "images/magic-erase", "inpaint"] {
            do {
                var request = try authorizedRequest(path: path, method: "POST")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 420
                request.httpBody = try encoder.encode(body)
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data, isPairRequest: false)
                return try decoder.decode(ImageGenerateResponse.self, from: data)
            } catch {
                lastError = error
                let msg = (error as? LocalizedError)?.errorDescription?.lowercased() ?? ""
                if msg.contains("unbekannte") || msg.contains("route") || msg.contains("404") {
                    continue
                }
                // Retry next alias only for missing-route; payload errors stop immediately
                if msg.contains("fehlen") || msg.contains("base64") {
                    throw CompanionAPIError.server(
                        "Radierer: Companion erwartet Bild+Maske — NOCO AI X neu starten (snake_case Fix)"
                    )
                }
                throw error
            }
        }
        throw lastError ?? CompanionAPIError.server("Inpaint fehlgeschlagen — Companion neu starten")
    }

    /// Warm up Stable Diffusion / Bilder-Engine on the PC (same engine as Bildidee).
    func prepareImageEngine() async throws -> ImageEnginePrepareResponse {
        struct Empty: Encodable {}
        var lastError: Error?
        for path in ["images/prepare", "images/engine", "images/start-engine"] {
            do {
                var request = try authorizedRequest(path: path, method: "POST")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 200
                request.httpBody = try encoder.encode(Empty())
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data, isPairRequest: false)
                return try decoder.decode(ImageEnginePrepareResponse.self, from: data)
            } catch {
                lastError = error
                let msg = (error as? LocalizedError)?.errorDescription?.lowercased() ?? ""
                if msg.contains("unbekannte") || msg.contains("route") || msg.contains("404") {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? CompanionAPIError.server("Bilder-Engine-Start fehlt — Companion neu starten")
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
        as type: T.Type,
        timeout: TimeInterval = 60
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try authorizedRequest(path: path, method: "POST")
        request.timeoutInterval = timeout
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

                    // UTF-8 line decode — never treat raw bytes as Characters (breaks ä/ö/ü)
                    for try await line in bytes.lines {
                        if let chunk = try parseSSEChunk(line) {
                            continuation.yield(chunk)
                            if chunk.done == true { break }
                        }
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

                    for try await line in bytes.lines {
                        try processSSELine(line, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapNetworkError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}