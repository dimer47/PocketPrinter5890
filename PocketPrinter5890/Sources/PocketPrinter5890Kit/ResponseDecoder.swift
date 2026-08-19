import Foundation

public enum ResponseDecoder {
    public static func decode(_ bytes: [UInt8], context: String?) -> String {
        let context = context?.lowercased() ?? ""

        // Acquittement ASCII observe sur FF01 apres une commande proprietaire
        // acceptee, par exemple le reglage de densite.
        if bytes == [0x4f, 0x4b] {
            return "OK: commande acceptee"
        }

        if bytes.count >= 3, bytes[0] == 0x02 {
            let suffix = bytes[2] != 0x00 ? " (flags 0x\(hex(bytes[2])))" : ""
            return "Batterie probable: \(bytes[1])%\(suffix)"
        }

        // Trame de credit de flux: `01 nn` signifie que l'imprimante peut
        // accepter nn paquets supplementaires. Ce n'est ni un acquittement
        // ni un statut papier, contrairement a ce que supposait la version
        // precedente de ce decodeur.
        if bytes.count == 2, bytes[0] == 0x01 {
            return "Credit de flux: +\(bytes[1]) paquet(s)"
        }

        if bytes.count >= 2, bytes[0] == 0x01 {
            return decodeStatusByte(bytes[1])
        }

        if context.contains("modele") || context.contains("model") {
            return ascii(bytes).map { "Modele: \($0)" } ?? "Modele: reponse non ASCII"
        }

        if context.contains("firmware") {
            return ascii(bytes).map { "Firmware: \($0)" } ?? "Firmware: reponse non ASCII"
        }

        if context.contains("serial") || context.contains("serie") {
            return ascii(bytes).map { "Numero de serie: \($0)" } ?? "Numero de serie: reponse non ASCII"
        }

        if context.contains("batterie") || context.contains("battery") {
            guard bytes.count >= 2 else { return "Batterie: reponse vide" }
            return "Batterie: \(bytes[1])%"
        }

        // Reponse a `10 FF 13`: delai d'extinction sur deux octets.
        if context.contains("extinction") || context.contains("shutdown") {
            guard bytes.count >= 2 else { return "Extinction auto: reponse vide" }
            let minutes = Int(bytes[bytes.count - 2]) << 8 | Int(bytes[bytes.count - 1])
            return minutes == 0
                ? "Extinction auto: desactivee"
                : "Extinction auto: \(minutes) min"
        }

        if context.contains("papier") || context.contains("paper") {
            switch bytes.last {
            case 0x00:
                return "Papier: present"
            case 0x04:
                return "Papier: capteur signale 0x04 (informatif, n'empeche pas d'imprimer)"
            case let value?:
                return "Papier: etat 0x\(String(format: "%02X", value))"
            case nil:
                return "Papier: reponse vide"
            }
        }

        if bytes == [0x00] {
            return "Statut: 0x00, papier present"
        }

        if let text = ascii(bytes), !text.isEmpty {
            return "ASCII: \(text)"
        }
        return ""
    }

    public static func looksLikeSolicitedResponse(_ bytes: [UInt8], context: String?) -> Bool {
        guard let context = context?.lowercased() else { return false }

        // Une trame `01 nn` est un credit de flux emis en continu pendant les
        // echanges: elle ne repond a aucune commande. La confondre avec une
        // reponse consommait le contexte et faisait lire `01 01` comme
        // « batterie 1 % » alors que la vraie reponse `00 62` suivait.
        if bytes.count == 2, bytes[0] == 0x01 { return false }

        if bytes == [0x4f, 0x4b] { return true }

        if context.contains("modele") || context.contains("model")
            || context.contains("firmware")
            || context.contains("serial")
            || context.contains("serie") {
            return ascii(bytes) != nil
        }

        if context.contains("batterie") || context.contains("battery") {
            // Deux formes observees: `02 64 00` emis spontanement, et
            // `00 62` en reponse a la requete. Dans les deux cas le
            // pourcentage est le deuxieme octet.
            guard bytes.count >= 2 else { return false }
            return bytes[0] == 0x02 || (bytes[1] > 0 && bytes[1] <= 100)
        }

        if context.contains("papier") || context.contains("paper") {
            return bytes.count == 1 || (bytes.count >= 2 && bytes[0] == 0x01)
        }

        return false
    }

    private static func ascii(_ bytes: [UInt8]) -> String? {
        let printable = bytes.filter { $0 >= 0x20 && $0 <= 0x7e }
        guard !printable.isEmpty else { return nil }
        return String(bytes: printable, encoding: .ascii)
    }

    private static func decodeStatusByte(_ status: UInt8) -> String {
        // Observation: pendant l'envoi d'un raster, l'imprimante emet un flot
        // continu de `01 01`. Il s'agit d'un acquittement de reception, pas
        // d'une erreur. Le statut `01 04` apparait a la connexion alors que
        // l'application officielle imprime sans probleme avec le meme papier:
        // il est donc informatif et ne doit jamais bloquer une impression.
        switch status {
        case 0x00:
            return "Etat 0x00: pret, papier present"
        case 0x01:
            return "Etat 0x01: reception ou impression en cours (normal)"
        case 0x04:
            return "Etat 0x04: capteur papier (informatif, n'empeche pas d'imprimer)"
        case 0x84:
            return "Etat 0x84: capteur papier + flag 0x80 (informatif)"
        default:
            var parts: [String] = []
            if status & 0x01 != 0 { parts.append("occupe") }
            if status & 0x04 != 0 { parts.append("capteur papier") }
            if status & 0x80 != 0 { parts.append("flag 0x80") }
            let known: UInt8 = 0x85
            let unknown = status & ~known
            if unknown != 0 { parts.append("flags inconnus 0x\(hex(unknown))") }
            if parts.isEmpty { parts.append("etat non documente") }
            return "Etat 0x\(hex(status)): \(parts.joined(separator: ", "))"
        }
    }

    private static func hex(_ byte: UInt8) -> String {
        String(format: "%02X", byte)
    }
}
