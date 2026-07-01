import Foundation

/// One row of the public web borrow form (`t.l0l0.app/<code>`), as returned by
/// the Supabase `tanamiru_fetch_borrow_requests` RPC. All string dates are
/// stored in the backend as `date` (`yyyy-MM-dd`) / `timestamptz`.
struct WebBorrowRequest: Decodable, Identifiable, Equatable {
    let id: String
    let code: String
    let borrowerName: String
    let borrowFrom: String?
    let borrowUntil: String?
    let destination: String?
    let note: String?
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, code, destination, note, status
        case borrowerName = "borrower_name"
        case borrowFrom = "borrow_from"
        case borrowUntil = "borrow_until"
        case createdAt = "created_at"
    }

    var isPending: Bool { status == "pending" }

    // MARK: - Parsed values

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Loan start: the borrower's chosen "from" date (local midnight), or the
    /// moment the request was created if they left it blank.
    var startDate: Date {
        if let from = borrowFrom, let d = Self.dayFormatter.date(from: from) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: createdAt) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: createdAt) ?? Date()
    }

    /// Loan due date: end of the borrower's chosen "until" day, or `nil`.
    var dueDate: Date? {
        guard let until = borrowUntil, let day = Self.dayFormatter.date(from: until) else { return nil }
        // Treat the return date as the end of that day (23:59:59 local).
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: day) ?? day
    }

    var trimmedBorrower: String {
        borrowerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDestination: String? {
        guard let d = destination?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else { return nil }
        return d
    }

    var trimmedNote: String? {
        guard let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return nil }
        return n
    }
}

/// Thin networking layer over the Supabase REST/RPC endpoints that back the web
/// borrow form. No third-party SDK — plain `URLSession`. The anon key is public
/// by design (see `AppConfig.webBorrowAnonKey`).
struct BorrowBackend {

    enum BackendError: LocalizedError {
        case badResponse(Int)
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                return String(format: NSLocalizedString("サーバーとの通信に失敗しました (%d)", comment: ""), code)
            case .notConfigured:
                return NSLocalizedString("借用リクエストの取得先が設定されていません。", comment: "")
            }
        }
    }

    let baseURL: String
    let anonKey: String
    let session: URLSession

    init(baseURL: String = AppConfig.webBorrowBaseURL,
         anonKey: String = AppConfig.webBorrowAnonKey,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// Fetch every borrow request whose code is one of `codes` (any status).
    func fetch(codes: [String]) async throws -> [WebBorrowRequest] {
        guard !codes.isEmpty else { return [] }
        let body: [String: Any] = ["p_codes": codes]
        let data = try await callRPC("tanamiru_fetch_borrow_requests", body: body)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([WebBorrowRequest].self, from: data)
    }

    /// Mark a request `applied` or `rejected` so it is not re-processed.
    func mark(id: String, code: String, status: String) async throws {
        let body: [String: Any] = ["p_id": id, "p_code": code, "p_status": status]
        _ = try await callRPC("tanamiru_mark_borrow_request", body: body)
    }

    // MARK: - Private

    private func callRPC(_ name: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/\(name)") else {
            throw BackendError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse(-1) }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.badResponse(http.statusCode)
        }
        return data
    }
}
