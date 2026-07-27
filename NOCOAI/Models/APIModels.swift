import Foundation

struct PairingInfo: Codable, Equatable {
    let ip: String
    let pin: String
    let port: Int?
    let qrData: String?
    let hostname: String?

    enum CodingKeys: String, CodingKey {
        case ip, pin, port, hostname
        case qrData = "qr_data"
        case qr = "qr"
    }

    init(ip: String, pin: String, port: Int? = 4747, qrData: String? = nil, hostname: String? = nil) {
        self.ip = ip
        self.pin = pin
        self.port = port
        self.qrData = qrData
        self.hostname = hostname
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ip = try c.decode(String.self, forKey: .ip)
        pin = try c.decode(String.self, forKey: .pin)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
        qrData = try c.decodeIfPresent(String.self, forKey: .qrData)
            ?? c.decodeIfPresent(String.self, forKey: .qr)
    }

    var baseURL: URL {
        URL(string: "http://\(ip):\(port ?? 4747)/api/v1")!
    }
}

struct PairRequest: Codable {
    let pin: String
    let deviceName: String

    enum CodingKeys: String, CodingKey {
        case pin
        case deviceName = "device_name"
    }
}

struct PairResponse: Codable {
    let token: String
    let deviceId: String?

    enum CodingKeys: String, CodingKey {
        case token
        case deviceId = "device_id"
    }
}

struct ServerStatus: Codable, Equatable {
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

    enum CodingKeys: String, CodingKey {
        case online, model, temperature
        case gpuPercent = "gpu_percent"
        case cpuPercent = "cpu_percent"
        case ramUsedGB = "ram_used_gb"
        case ramTotalGB = "ram_total_gb"
        case responseTimeMs = "response_time_ms"
        case temperatureC = "temperature_c"
        case uptimeSeconds = "uptime_seconds"
        case lastActivity = "last_activity"
        case requestCount = "request_count"
        case tokenCount = "token_count"
        case gpu = "gpu"
        case ram = "ram"
        case cpu = "cpu"
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
        tokenCount: Int? = nil
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
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? true
        model = try c.decodeIfPresent(String.self, forKey: .model)
        temperatureC = try c.decodeIfPresent(Double.self, forKey: .temperatureC)
            ?? c.decodeIfPresent(Double.self, forKey: .temperature)
        responseTimeMs = try c.decodeIfPresent(Double.self, forKey: .responseTimeMs)
        uptimeSeconds = try c.decodeIfPresent(Double.self, forKey: .uptimeSeconds)
        lastActivity = try c.decodeIfPresent(String.self, forKey: .lastActivity)
        requestCount = try c.decodeIfPresent(Int.self, forKey: .requestCount)
        tokenCount = try c.decodeIfPresent(Int.self, forKey: .tokenCount)

        if let gpu = try? c.decode(Double.self, forKey: .gpuPercent) {
            gpuPercent = gpu
        } else if let gpuObj = try? c.decode(GPUMetric.self, forKey: .gpu) {
            gpuPercent = gpuObj.percent ?? gpuObj.usage
        } else {
            gpuPercent = nil
        }

        if let cpu = try? c.decode(Double.self, forKey: .cpuPercent) {
            cpuPercent = cpu
        } else if let cpuObj = try? c.decode(CPUMetric.self, forKey: .cpu) {
            cpuPercent = cpuObj.percent ?? cpuObj.usage
        } else {
            cpuPercent = nil
        }

        if let used = try? c.decode(Double.self, forKey: .ramUsedGB) {
            ramUsedGB = used
            ramTotalGB = try c.decodeIfPresent(Double.self, forKey: .ramTotalGB)
        } else if let ramObj = try? c.decode(RAMMetric.self, forKey: .ram) {
            ramUsedGB = ramObj.usedGB ?? ramObj.used
            ramTotalGB = ramObj.totalGB ?? ramObj.total
        } else {
            ramUsedGB = nil
            ramTotalGB = nil
        }
    }

    private struct GPUMetric: Codable {
        let percent: Double?
        let usage: Double?
    }

    private struct CPUMetric: Codable {
        let percent: Double?
        let usage: Double?
    }

    private struct RAMMetric: Codable {
        let usedGB: Double?
        let totalGB: Double?
        let used: Double?
        let total: Double?

        enum CodingKeys: String, CodingKey {
            case usedGB = "used_gb"
            case totalGB = "total_gb"
            case used, total
        }
    }
}

struct ChatRequest: Codable {
    let message: String
    let conversationId: String?

    enum CodingKeys: String, CodingKey {
        case message
        case conversationId = "conversation_id"
    }
}

struct ChatStreamChunk: Codable {
    let content: String?
    let delta: String?
    let done: Bool?
    let error: String?
}
