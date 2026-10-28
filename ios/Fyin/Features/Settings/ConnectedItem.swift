import Foundation

// Espelha GET /v1/items (internal/items). O dono vem do rótulo dono:itemId do servidor.
struct ConnectedItem: Decodable, Identifiable, Equatable {
    struct Sync: Decodable, Equatable {
        let state: String          // idle | running | succeeded | failed
        let phase: String?         // refreshing | importing
        let error: String?
    }

    let id: String
    let owner: String
    let connector: String
    let status: String             // status do item na Pluggy
    let consentExpiresAt: Date?
    let syncedAt: Date
    let accounts: Int
    let sync: Sync

    var isRunning: Bool { sync.state == "running" }
}

enum ItemTone { case ok, running, attention, error }

extension ConnectedItem {
    /// A linha de status de um banco, na ordem do que o usuário precisa saber primeiro.
    func line(now: Date) -> (text: String, tone: ItemTone) {
        if isRunning {
            return (sync.phase == "importing" ? "importando transações" : "pedindo dado novo ao banco", .running)
        }
        switch status {
        case "LOGIN_ERROR": return ("precisa reconectar", .error)
        case "WAITING_USER_INPUT": return ("confirme no app do banco", .attention)
        case "OUTDATED": return ("leitura desatualizada", .attention)
        default: break
        }
        if sync.state == "failed" { return ("não conseguiu atualizar", .attention) }
        if let days = consentDays(now: now), days <= 30 {
            return (days <= 0 ? "consentimento venceu" : "consentimento vence em \(days) dias", days <= 0 ? .error : .attention)
        }
        return ("atualizado \(SyncFormat.when(syncedAt, now: now))", .ok)
    }

    private func consentDays(now: Date) -> Int? {
        consentExpiresAt.map { Calendar.current.dateComponents([.day], from: now, to: $0).day ?? 0 }
    }
}

enum SyncFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = format
        return f
    }

    /// "9:41" hoje; "24 out" em outro dia.
    static func when(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? formatter("H:mm").string(from: date) : formatter("d MMM").string(from: date)
    }

    /// "Hoje, 9:41"; "24 out, 9:41".
    static func long(_ date: Date, now: Date) -> String {
        let time = formatter("H:mm").string(from: date)
        return Calendar.current.isDate(date, inSameDayAs: now) ? "Hoje, \(time)" : "\(formatter("d MMM").string(from: date)), \(time)"
    }
}
