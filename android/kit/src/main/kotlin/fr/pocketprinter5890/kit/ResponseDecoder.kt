package fr.pocketprinter5890.kit

/** Formatage hexadecimal, pour les journaux. */
object Hex {
    fun encode(bytes: ByteArray): String =
        bytes.joinToString(" ") { "%02X".format(it.toInt() and 0xff) }
}

/**
 * Interprete les trames recues de l'imprimante.
 *
 * Le piege principal: une trame `01 nn` est un **credit de flux**, jamais une
 * reponse a une commande. La confondre avec une reponse fait lire `01 01`
 * comme « batterie 1 % » alors que la vraie reponse (`00 62`, 98 %) arrive
 * juste apres.
 */
object ResponseDecoder {

    fun decode(bytes: ByteArray, context: String?): String {
        val ctx = context?.lowercase() ?: ""
        val unsigned = bytes.map { it.toInt() and 0xff }

        // Trame de service emise spontanement en fin d'echange (`AA` suivi
        // d'un CRLF). Elle ne repond a aucune commande: la compter comme une
        // reponse decalait toutes les suivantes d'un cran, et son `0D` etait
        // lu comme « batterie 13 % ».
        if (isServiceFrame(bytes)) {
            return "Trame de service (fin d'echange)"
        }

        // Acquittement ASCII observe sur FF01 apres une commande proprietaire
        // acceptee, par exemple le reglage de densite.
        if (unsigned == listOf(0x4f, 0x4b)) {
            return "OK: commande acceptee"
        }

        if (unsigned.size >= 3 && unsigned[0] == 0x02) {
            val suffix = if (unsigned[2] != 0x00) " (flags 0x${hex(unsigned[2])})" else ""
            return "Batterie probable: ${unsigned[1]}%$suffix"
        }

        // Trame de credit de flux: `01 nn` signifie que l'imprimante peut
        // accepter nn paquets supplementaires. Ce n'est ni un acquittement ni
        // un statut papier.
        if (unsigned.size == 2 && unsigned[0] == 0x01) {
            return "Credit de flux: +${unsigned[1]} paquet(s)"
        }

        if (unsigned.size >= 2 && unsigned[0] == 0x01) {
            return decodeStatusByte(unsigned[1])
        }

        if (ctx.contains("modele") || ctx.contains("model")) {
            return ascii(bytes)?.let { "Modele: $it" } ?: "Modele: reponse non ASCII"
        }

        if (ctx.contains("firmware")) {
            return ascii(bytes)?.let { "Firmware: $it" } ?: "Firmware: reponse non ASCII"
        }

        if (ctx.contains("serial") || ctx.contains("serie")) {
            return ascii(bytes)?.let { "Numero de serie: $it" }
                ?: "Numero de serie: reponse non ASCII"
        }

        if (ctx.contains("batterie") || ctx.contains("battery")) {
            if (unsigned.size < 2) return "Batterie: reponse vide"
            return "Batterie: ${unsigned[1]}%"
        }

        // Reponse a `10 FF 13`: delai d'extinction sur deux octets.
        if (ctx.contains("extinction") || ctx.contains("shutdown")) {
            if (unsigned.size < 2) return "Extinction auto: reponse vide"
            val minutes = (unsigned[unsigned.size - 2] shl 8) or unsigned[unsigned.size - 1]
            return if (minutes == 0) {
                "Extinction auto: desactivee"
            } else {
                "Extinction auto: $minutes min"
            }
        }

        if (ctx.contains("papier") || ctx.contains("paper")) {
            return when (val last = unsigned.lastOrNull()) {
                null -> "Papier: reponse vide"
                0x00 -> "Papier: present"
                0x04 ->
                    "Papier: capteur signale 0x04 (informatif, n'empeche pas d'imprimer)"
                else -> "Papier: etat 0x${hex(last)}"
            }
        }

        if (unsigned == listOf(0x00)) {
            return "Statut: 0x00, papier present"
        }

        val text = ascii(bytes)
        if (!text.isNullOrEmpty()) {
            return "ASCII: $text"
        }
        return ""
    }

    /**
     * Determine si une trame repond a la commande en attente.
     *
     * Une trame `01 nn` est un credit emis en continu pendant les echanges:
     * elle ne repond a aucune commande. La compter comme une reponse
     * consommait le contexte et faisait lire `01 01` comme « batterie 1 % ».
     */
    fun looksLikeSolicitedResponse(bytes: ByteArray, context: String?): Boolean {
        val ctx = context?.lowercase() ?: return false
        val unsigned = bytes.map { it.toInt() and 0xff }

        if (unsigned.size == 2 && unsigned[0] == 0x01) return false
        if (isServiceFrame(bytes)) return false

        if (unsigned == listOf(0x4f, 0x4b)) return true

        if (ctx.contains("modele") || ctx.contains("model") ||
            ctx.contains("firmware") || ctx.contains("serial") || ctx.contains("serie")
        ) {
            return ascii(bytes) != null
        }

        if (ctx.contains("batterie") || ctx.contains("battery")) {
            // Deux formes observees: `02 64 00` emis spontanement, et `00 nn`
            // en reponse a la requete (`00 5E` = 94 % sur l'appareil de test).
            // Dans les deux cas le pourcentage est le deuxieme octet.
            if (unsigned.size < 2) return false
            if (unsigned[0] == 0x02) return true
            return unsigned[0] == 0x00 && unsigned[1] in 1..100
        }

        if (ctx.contains("papier") || ctx.contains("paper")) {
            // Un octet seul, ou `01 nn`. Une trame `00 nn` est une reponse
            // batterie et ne doit pas etre prise pour un etat papier.
            return unsigned.size == 1 || (unsigned.size >= 2 && unsigned[0] == 0x01)
        }

        return false
    }

    /**
     * Trame de service `AA 0D 0A`, emise spontanement en fin d'echange.
     *
     * Observee sur l'A2Y apres chaque commande. Ce n'est pas une reponse: la
     * traiter comme telle consomme le contexte en attente, et toutes les
     * reponses suivantes se retrouvent etiquetees avec la mauvaise commande.
     */
    fun isServiceFrame(bytes: ByteArray): Boolean {
        if (bytes.size != 3) return false
        return (bytes[0].toInt() and 0xff) == 0xaa &&
            (bytes[1].toInt() and 0xff) == 0x0d &&
            (bytes[2].toInt() and 0xff) == 0x0a
    }

    /**
     * Extrait un credit de flux d'une trame `01 nn`.
     *
     * @return le nombre de paquets supplementaires autorises, ou null si la
     *   trame n'est pas un credit.
     */
    fun creditFrame(bytes: ByteArray): Int? {
        if (bytes.size != 2) return null
        if ((bytes[0].toInt() and 0xff) != 0x01) return null
        return bytes[1].toInt() and 0xff
    }

    private fun ascii(bytes: ByteArray): String? {
        val printable = bytes.filter { (it.toInt() and 0xff) in 0x20..0x7e }
        if (printable.isEmpty()) return null
        return String(printable.toByteArray(), Charsets.US_ASCII)
    }

    private fun decodeStatusByte(status: Int): String {
        // Observation: pendant l'envoi d'un raster, l'imprimante emet un flot
        // continu de `01 01`. Il s'agit d'un acquittement de reception, pas
        // d'une erreur. Le statut `01 04` apparait a la connexion alors que
        // l'application officielle imprime sans probleme avec le meme papier:
        // il est donc informatif et ne doit jamais bloquer une impression.
        return when (status) {
            0x00 -> "Etat 0x00: pret, papier present"
            0x01 -> "Etat 0x01: reception ou impression en cours (normal)"
            0x04 -> "Etat 0x04: capteur papier (informatif, n'empeche pas d'imprimer)"
            0x84 -> "Etat 0x84: capteur papier + flag 0x80 (informatif)"
            else -> {
                val parts = mutableListOf<String>()
                if (status and 0x01 != 0) parts.add("occupe")
                if (status and 0x04 != 0) parts.add("capteur papier")
                if (status and 0x80 != 0) parts.add("flag 0x80")
                val known = 0x85
                val unknown = status and known.inv() and 0xff
                if (unknown != 0) parts.add("flags inconnus 0x${hex(unknown)}")
                if (parts.isEmpty()) parts.add("etat non documente")
                "Etat 0x${hex(status)}: ${parts.joinToString(", ")}"
            }
        }
    }

    private fun hex(byte: Int): String = "%02X".format(byte and 0xff)
}
