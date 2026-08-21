package fr.pocketprinter5890.kit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Le piege principal du protocole: une trame `01 nn` est un credit de flux,
 * jamais une reponse. La confondre faisait lire `01 01` comme
 * « batterie 1 % » alors que la vraie reponse `00 62` (98 %) suivait.
 */
class ResponseDecoderTest {

    private fun bytes(vararg values: Int): ByteArray =
        ByteArray(values.size) { values[it].toByte() }

    @Test
    fun `une trame de credit n'est jamais une reponse sollicitee`() {
        assertFalse(ResponseDecoder.looksLikeSolicitedResponse(bytes(0x01, 0x01), "Lire batterie"))
        assertFalse(ResponseDecoder.looksLikeSolicitedResponse(bytes(0x01, 0x14), "Lire batterie"))
    }

    @Test
    fun `la vraie reponse batterie reste reconnue`() {
        // Forme observee en reponse a `10 FF 50 F1`: 0x62 = 98 %.
        assertTrue(ResponseDecoder.looksLikeSolicitedResponse(bytes(0x00, 0x62), "Lire batterie"))
        // Forme emise spontanement a la connexion: 0x64 = 100 %.
        assertTrue(ResponseDecoder.looksLikeSolicitedResponse(bytes(0x02, 0x64, 0x00), "Lire batterie"))
    }

    @Test
    fun `le pourcentage est toujours le deuxieme octet`() {
        assertEquals("Batterie: 98%", ResponseDecoder.decode(bytes(0x00, 0x62), "Lire batterie"))
        assertEquals("Batterie probable: 100%", ResponseDecoder.decode(bytes(0x02, 0x64, 0x00), null))
    }

    @Test
    fun `un credit reste lisible dans le journal`() {
        assertEquals(
            "Credit de flux: +20 paquet(s)",
            ResponseDecoder.decode(bytes(0x01, 0x14), null)
        )
    }

    @Test
    fun `l'extraction de credit ne repond que sur les trames de credit`() {
        assertEquals(20, ResponseDecoder.creditFrame(bytes(0x01, 0x14)))
        assertNull(ResponseDecoder.creditFrame(bytes(0x00, 0x62)))
        assertNull(ResponseDecoder.creditFrame(bytes(0x01, 0x01, 0x01)))
    }

    @Test
    fun `l'etat papier 0x04 reste informatif`() {
        // L'application officielle imprime malgre ce code avec le meme papier:
        // il ne doit jamais bloquer une impression.
        //
        // Attention: sur deux octets, `01 04` est un credit de flux, pas un
        // statut. C'est bien la regle de longueur qui tranche, et l'octet de
        // statut n'est interprete qu'a partir de trois octets.
        val message = ResponseDecoder.decode(bytes(0x01, 0x04, 0x00), null)
        assertTrue(message.contains("informatif"), "Message inattendu: $message")

        // La meme trame sur deux octets reste lue comme un credit.
        assertEquals(4, ResponseDecoder.creditFrame(bytes(0x01, 0x04)))
    }

    @Test
    fun `un etat papier lu via le contexte reste informatif`() {
        val message = ResponseDecoder.decode(bytes(0x04), "Lire papier")
        assertTrue(message.contains("informatif"), "Message inattendu: $message")
    }

    @Test
    fun `la trame de service n'est jamais une reponse`() {
        // Regression: `AA 0D 0A` est emis spontanement en fin d'echange.
        // Le compter comme une reponse consommait le contexte en attente et
        // decalait toutes les suivantes: le modele arrivait etiquete
        // « firmware », et son `0D` etait lu comme « batterie 13 % ».
        val service = bytes(0xaa, 0x0d, 0x0a)
        assertTrue(ResponseDecoder.isServiceFrame(service))
        assertFalse(ResponseDecoder.looksLikeSolicitedResponse(service, "Lire batterie"))
        assertFalse(ResponseDecoder.looksLikeSolicitedResponse(service, "Lire modele"))
        assertEquals(
            "Trame de service (fin d'echange)",
            ResponseDecoder.decode(service, "Lire batterie")
        )
    }

    @Test
    fun `la reponse batterie observee sur l'appareil est reconnue`() {
        // `00 5E` = 94 %, relevé sur la machine de test.
        assertTrue(ResponseDecoder.looksLikeSolicitedResponse(bytes(0x00, 0x5e), "Lire batterie"))
        assertEquals("Batterie: 94%", ResponseDecoder.decode(bytes(0x00, 0x5e), "Lire batterie"))
    }

    @Test
    fun `le modele et le firmware sont decodes en ASCII`() {
        assertEquals("Modele: A2Y", ResponseDecoder.decode("A2Y".toByteArray(), "Lire modele"))
        assertEquals(
            "Firmware: V1.06LY",
            ResponseDecoder.decode("V1.06LY".toByteArray(), "Lire firmware")
        )
    }
}

class TransliterationTest {

    @Test
    fun `le degre et les accents deviennent ASCII`() {
        // Le firmware imprime un carre plein pour tout caractere non-ASCII,
        // quelle que soit la page de code declaree.
        assertEquals("18degC", Escpos.transliterate("18°C"))
        assertEquals("cafe", Escpos.transliterate("café"))
        assertEquals("eleve a Noel", Escpos.transliterate("élevé à Noël"))
    }

    @Test
    fun `les symboles courants sont remplaces`() {
        assertEquals("12 EUR", Escpos.transliterate("12 €"))
        assertEquals("1/2 litre", Escpos.transliterate("½ litre"))
        assertEquals("oeuf", Escpos.transliterate("œuf"))
    }

    @Test
    fun `l'ASCII n'est pas touche`() {
        assertEquals("Hello, World! 123", Escpos.transliterate("Hello, World! 123"))
    }

    @Test
    fun `le resultat est toujours de l'ASCII pur`() {
        val source = "Crème brûlée — 3,50 € « spécial » …"
        val result = Escpos.transliterate(source)
        assertTrue(result.all { it.code < 128 }, "Reste du non-ASCII: $result")
    }
}

class TextLayoutTest {

    @Test
    fun `une ligne longue est coupee sur les espaces`() {
        // Le firmware coupe au caractere pres: « l'apres-midi. » devenait
        // « l'apres-m » puis « idi. ».
        val lines = TextLayout.wrap("Beau temps cet apres-midi sur la region", 16)
        assertTrue(lines.all { it.length <= 16 })
        assertFalse(lines.any { it.startsWith(" ") })
    }

    @Test
    fun `une ligne courte est laissee intacte`() {
        assertEquals(listOf("Bonjour"), TextLayout.wrap("Bonjour", 32))
    }

    @Test
    fun `un mot trop long est coupe net`() {
        val lines = TextLayout.wrap("anticonstitutionnellement", 10)
        assertTrue(lines.all { it.length <= 10 })
        assertEquals("anticonstitutionnellement", lines.joinToString(""))
    }

    @Test
    fun `les sauts de ligne explicites sont preserves`() {
        assertEquals(listOf("un", "deux"), TextLayout.wrap("un\ndeux", 32))
    }

    @Test
    fun `le nombre de colonnes diminue avec la taille de police`() {
        assertEquals(32, TextLayout.columns(384, 1))
        assertEquals(16, TextLayout.columns(384, 2))
    }

    @Test
    fun `les colonnes ne se chevauchent jamais`() {
        val line = TextLayout.columns("Baguette tradition", "1,20", 32)
        assertEquals(32, line.length)
        assertTrue(line.endsWith("1,20"))
    }
}
