import Foundation

struct PingResponse: Decodable {
    let ok: Bool?
    let pong: Bool?

    var isAlive: Bool { ok == true || pong == true }
}

struct PairingInfo: Decodable, Equatable {
    let ip: String
    let pin: String
    let port: Int?
    let qrData: String?
    let pairUrl: String?
    let hostname: String?

    // camelCase — CompanionAPI uses convertFromSnakeCase
    enum CodingKeys: String, CodingKey {
        case ip, host, pin, port, hostname
        case qrData, qr, qrPayload, pairUrl
    }

    init(ip: String, pin: String, port: Int? = 4747, qrData: String? = nil, pairUrl: String? = nil, hostname: String? = nil) {
        self.ip = ip
        self.pin = pin
        self.port = port
        self.qrData = qrData
        self.pairUrl = pairUrl
        self.hostname = hostname
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(String.self, forKey: .ip) {
            ip = v
        } else if let v = try c.decodeIfPresent(String.self, forKey: .host) {
            ip = v
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "ip/host fehlt"))
        }
        pin = try c.decode(String.self, forKey: .pin)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
        qrData = try c.decodeIfPresent(String.self, forKey: .qrData)
            ?? c.decodeIfPresent(String.self, forKey: .qr)
            ?? c.decodeIfPresent(String.self, forKey: .qrPayload)
        pairUrl = try c.decodeIfPresent(String.self, forKey: .pairUrl)
    }

    var resolvedPort: Int { port ?? 4747 }

    var baseURL: URL {
        URL(string: "http://\(ip):\(resolvedPort)/api/v1")!
    }
}

struct PairRequest: Encodable {
    let pin: String
    let deviceName: String
}

struct PairResponse: Decodable {
    let token: String
    let deviceId: String?
}

struct ServerStatus: Decodable, Equatable {
    let online: Bool
    let model: String?
    let gpuPercent: Double?
    let cpuPercent: Double?
    let ramUsedGB: Double?
    let ramTotalGB: Double?
    let responseTimeMs: Double?
    let temperatureC: Double?
    let uptimeSeconds: Double?
    let lastActivity: String?
    let requestCount: Int?
    let tokenCount: Int?
    /// Stable Diffusion / Bilder-Engine ready on the PC (same engine for Bildidee + Radierer).
    let stableDiffusion: Bool?

    // camelCase keys — CompanionAPI uses convertFromSnakeCase
    enum CodingKeys: String, CodingKey {
        case online, model, temperature
        case gpuPercent, cpuPercent, ramUsedGB, ramTotalGB
        case responseTimeMs, temperatureC, uptimeSeconds
        case lastActivity, requestCount, tokenCount
        case gpu, ram, cpu, activeModel, system
        case stableDiffusion, imageEngine, bilderEngine
    }

    init(
        online: Bool = false,
        model: String? = nil,
        gpuPercent: Double? = nil,
        cpuPercent: Double? = nil,
        ramUsedGB: Double? = nil,
        ramTotalGB: Double? = nil,
        responseTimeMs: Double? = nil,
        temperatureC: Double? = nil,
        uptimeSeconds: Double? = nil,
        lastActivity: String? = nil,
        requestCount: Int? = nil,
        tokenCount: Int? = nil,
        stableDiffusion: Bool? = nil
    ) {
        self.online = online
        self.model = model
        self.gpuPercent = gpuPercent
        self.cpuPercent = cpuPercent
        self.ramUsedGB = ramUsedGB
        self.ramTotalGB = ramTotalGB
        self.responseTimeMs = responseTimeMs
        self.temperatureC = temperatureC
        self.uptimeSeconds = uptimeSeconds
        self.lastActivity = lastActivity
        self.requestCount = requestCount
        self.tokenCount = tokenCount
        self.stableDiffusion = stableDiffusion
    }

    /// Prefer server latency; otherwise fill with measured round-trip.
    func withMeasuredLatency(_ ms: Double) -> ServerStatus {
        ServerStatus(
            online: online,
            model: model,
            gpuPercent: gpuPercent,
            cpuPercent: cpuPercent,
            ramUsedGB: ramUsedGB,
            ramTotalGB: ramTotalGB,
            responseTimeMs: responseTimeMs ?? ms,
            temperatureC: temperatureC,
            uptimeSeconds: uptimeSeconds,
            lastActivity: lastActivity,
            requestCount: requestCount,
            tokenCount: tokenCount,
            stableDiffusion: stableDiffusion
        )
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? true

        if let flat = try? c.decode(String.self, forKey: .model) {
            model = flat
        } else if let active = try? c.decode(String.self, forKey: .activeModel) {
            model = active
        } else if let activeObj = try? c.decode(ActiveModelInfo.self, forKey: .activeModel) {
            model = activeObj.name ?? activeObj.model
        } else {
            model = nil
        }

        temperatureC = try c.decodeIfPresent(Double.self, forKey: .temperatureC)
            ?? c.decodeIfPresent(Double.self, forKey: .temperature)
        uptimeSeconds = try c.decodeIfPresent(Double.self, forKey: .uptimeSeconds)
        lastActivity = try c.decodeIfPresent(String.self, forKey: .lastActivity)
        requestCount = try c.decodeIfPresent(Int.self, forKey: .requestCount)
        tokenCount = try c.decodeIfPresent(Int.self, forKey: .tokenCount)

        if let v = try c.decodeIfPresent(Bool.self, forKey: .stableDiffusion) {
            stableDiffusion = v
        } else if let v = try c.decodeIfPresent(Bool.self, forKey: .imageEngine) {
            stableDiffusion = v
        } else {
            stableDiffusion = try c.decodeIfPresent(Bool.self, forKey: .bilderEngine)
        }

        var decodedGPU: Double?
        if let gpu = try? c.decode(Double.self, forKey: .gpuPercent) {
            decodedGPU = gpu
        } else if let gpuObj = try? c.decode(GPUMetric.self, forKey: .gpu) {
            decodedGPU = gpuObj.percent ?? gpuObj.usage
        }

        var decodedCPU: Double?
        if let cpu = try? c.decode(Double.self, forKey: .cpuPercent) {
            decodedCPU = cpu
        } else if let cpuObj = try? c.decode(CPUMetric.self, forKey: .cpu) {
            decodedCPU = cpuObj.percent ?? cpuObj.usage
        }

        var decodedRAMUsed: Double?
        var decodedRAMTotal: Double?
        if let used = try? c.decode(Double.self, forKey: .ramUsedGB) {
            decodedRAMUsed = used
            decodedRAMTotal = try c.decodeIfPresent(Double.self, forKey: .ramTotalGB)
        } else if let ramObj = try? c.decode(RAMMetric.self, forKey: .ram) {
            decodedRAMUsed = ramObj.usedGB ?? ramObj.used
            decodedRAMTotal = ramObj.totalGB ?? ramObj.total
        }

        // Always merge nested `system` — companion often puts GPU/RAM only there
        // while CPU stays flat. Previously system was skipped whenever ramUsedGB existed.
        if let sys = try? c.decode(SystemMetric.self, forKey: .system) {
            decodedCPU = decodedCPU ?? sys.cpuPercent
            decodedGPU = decodedGPU ?? sys.gpuPercent
            decodedRAMUsed = decodedRAMUsed ?? sys.ramUsedGB
            decodedRAMTotal = decodedRAMTotal ?? sys.ramTotalGB
        }

        var decodedLatency = try c.decodeIfPresent(Double.self, forKey: .responseTimeMs)
        if decodedLatency == nil, let sys = try? c.decode(SystemMetric.self, forKey: .system) {
            decodedLatency = sys.latencyMs ?? sys.responseTimeMs
        }

        gpuPercent = decodedGPU
        cpuPercent = decodedCPU
        ramUsedGB = decodedRAMUsed
        ramTotalGB = decodedRAMTotal
        responseTimeMs = decodedLatency
    }

    private struct ActiveModelInfo: Decodable {
        let name: String?
        let model: String?
    }

    private struct SystemMetric: Decodable {
        let cpuPercent: Double?
        let gpuPercent: Double?
        let ramUsedGB: Double?
        let ramTotalGB: Double?
        let latencyMs: Double?
        let responseTimeMs: Double?
    }

    private struct GPUMetric: Decodable {
        let percent: Double?
        let usage: Double?
    }

    private struct CPUMetric: Decodable {
        let percent: Double?
        let usage: Double?
    }

    private struct RAMMetric: Decodable {
        let usedGB: Double?
        let totalGB: Double?
        let used: Double?
        let total: Double?
    }
}

struct ChatRequest: Encodable {
    let message: String
    let conversationId: String?
}

struct ChatStreamChunk: Decodable {
    let content: String?
    let done: Bool?
    let error: String?
    let conversationId: String?
    let messageId: String?
    let imageUrl: String?
    let webUsed: Bool?
    let sources: [ChatWebSource]?

    init(
        content: String? = nil,
        done: Bool? = nil,
        error: String? = nil,
        conversationId: String? = nil,
        messageId: String? = nil,
        imageUrl: String? = nil,
        webUsed: Bool? = nil,
        sources: [ChatWebSource]? = nil
    ) {
        self.content = content
        self.done = done
        self.error = error
        self.conversationId = conversationId
        self.messageId = messageId
        self.imageUrl = imageUrl
        self.webUsed = webUsed
        self.sources = sources
    }
}

struct ChatWebSource: Codable, Equatable, Hashable {
    let title: String?
    let url: String?
}

struct PairingDeepLink {
    let host: String
    let port: Int
    let pin: String?

    static func parse(from raw: String) -> PairingDeepLink? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.lowercased() == "nocoai" {
            return from(url: url)
        }
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return from(json: json)
        }
        if let url = URL(string: trimmed), let host = url.host ?? url.queryItem("host") {
            return PairingDeepLink(
                host: host,
                port: Int(url.queryItem("port") ?? "4747") ?? 4747,
                pin: url.queryItem("pin")
            )
        }
        return nil
    }

    static func from(url: URL) -> PairingDeepLink? {
        guard url.scheme?.lowercased() == "nocoai" else { return nil }
        let host = url.queryItem("host") ?? url.queryItem("ip") ?? url.host
        guard let host, !host.isEmpty else { return nil }
        return PairingDeepLink(
            host: host,
            port: Int(url.queryItem("port") ?? "4747") ?? 4747,
            pin: url.queryItem("pin")
        )
    }

    private static func from(json: [String: Any]) -> PairingDeepLink? {
        guard let host = json["host"] as? String ?? json["ip"] as? String else { return nil }
        let port = json["port"] as? Int ?? Int(json["port"] as? String ?? "4747") ?? 4747
        let pin = json["pin"] as? String
        return PairingDeepLink(host: host, port: port, pin: pin)
    }
}

private extension URL {
    func queryItem(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
