import Foundation

enum AIClientError: LocalizedError, Sendable, Equatable {
    case invalidBaseURL
    case missingAPIKey
    case invalidAPIKey
    case billingRequired
    case network
    case serverError(Int)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "API Base URL이 올바르지 않습니다."
        case .missingAPIKey: return "OpenAI API 키가 설정되어 있지 않습니다. 설정 > AI 탭에서 입력하세요."
        case .invalidAPIKey: return "API 키가 유효하지 않습니다. 설정에서 키를 다시 확인하세요."
        case .billingRequired: return "OpenAI 크레딧이 부족합니다. 결제(Billing) 정보를 확인하고 충전한 뒤 다시 시도하세요."
        case .network: return "네트워크 응답을 확인할 수 없습니다."
        case .serverError(let code): return "AI 서버에 일시적인 문제가 있습니다 (코드 \(code))."
        case .httpError(let code): return "요청이 실패했습니다 (코드 \(code))."
        }
    }
}

/// OpenAI(및 호환 API)의 Chat Completions 스트리밍 엔드포인트를 호출한다.
///
/// 보안 메모(스펙 16절): 이 타입은 요청/응답을 어디에도 로그로 남기지 않는다 — Authorization
/// 헤더가 찍힐 수 있는 디버그 프린트를 절대 추가하지 않는다. API 키는 호출자(LLMUseCase)가
/// Keychain에서 매번 읽어와 파라미터로만 넘기고, 이 클라이언트는 그 값을 보관하지 않는다.
struct OpenAIClient: Sendable {
    /// SSE(text/event-stream)의 한 줄을 파싱한다. 네트워크 없이 순수하게 테스트할 수 있도록
    /// 스트리밍 로직에서 분리했다.
    enum SSEFragment: Equatable, Sendable {
        case content(String)
        case done
    }

    static func parseSSELine(_ line: String) -> SSEFragment? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return nil }
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
              let delta = chunk.choices.first?.delta.content else {
            return nil
        }
        return .content(delta)
    }

    func streamChatCompletion(messages: [AIChatMessage], settings: AISettings, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.makeRequest(messages: messages, settings: settings, apiKey: apiKey, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.utf8.count > 4000 { break }
                        }
                        try Self.validate(response: response, bodyText: errorBody)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let fragment = Self.parseSSELine(line) else { continue }
                        switch fragment {
                        case .done:
                            continuation.finish()
                            return
                        case .content(let text):
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 설정 화면의 "연결 테스트" 버튼용 — 완성 토큰을 소비하지 않고 인증/URL만 확인한다.
    func testConnection(settings: AISettings, apiKey: String) async throws {
        guard let baseURL = settings.baseURL else { throw AIClientError.invalidBaseURL }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = settings.timeoutSeconds
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, bodyText: String(data: data, encoding: .utf8))
    }

    private static func makeRequest(messages: [AIChatMessage], settings: AISettings, apiKey: String, stream: Bool) throws -> URLRequest {
        guard let baseURL = settings.baseURL else { throw AIClientError.invalidBaseURL }
        guard !apiKey.isEmpty else { throw AIClientError.missingAPIKey }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = settings.timeoutSeconds

        let body = ChatCompletionRequest(
            model: settings.modelID,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: settings.temperature,
            max_tokens: settings.maxOutputTokens,
            stream: stream
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func validate(response: URLResponse, bodyText: String? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw AIClientError.network }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw AIClientError.invalidAPIKey
        case 429:
            if isBillingExhausted(bodyText) {
                throw AIClientError.billingRequired
            }
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw AppError.apiRateLimited(retryAfter: retryAfter)
        case 500...599:
            throw AIClientError.serverError(http.statusCode)
        default:
            throw AIClientError.httpError(http.statusCode)
        }
    }

    /// OpenAI는 크레딧 소진(결제 필요)과 단순 초당 요청 과다를 똑같이 HTTP 429로 반환하고,
    /// 응답 본문의 `"type"`/`"code"`로만 구분된다 (`insufficient_quota`). 전자는 "잠시 후
    /// 재시도"로는 해결되지 않으므로 별도 안내가 필요해서 이 둘을 나눈다.
    static func isBillingExhausted(_ bodyText: String?) -> Bool {
        guard let bodyText else { return false }
        return bodyText.contains("insufficient_quota") || bodyText.contains("billing_hard_limit_reached")
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}
