package fr.pocketprinter5890.demo

import fr.pocketprinter5890.kit.Escpos
import fr.pocketprinter5890.kit.PrintDocument
import fr.pocketprinter5890.kit.PrintElement
import fr.pocketprinter5890.kit.TextLayout
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Documents de demonstration.
 *
 * Ils n'utilisent que ce que ce firmware sait reellement faire: texte natif
 * translitere en ASCII, et codes rasterises. Aucune commande native de
 * code-barres ou de QR, qui s'imprimeraient en clair.
 */
object DemoDocuments {

    private const val COLUMNS = 32

    /** Bulletin meteo et horoscope, en texte natif. */
    fun weatherAndHoroscope(date: Date = Date()): PrintDocument {
        val formatter = SimpleDateFormat("EEEE d MMMM yyyy", Locale.FRANCE)
        val document = PrintDocument()

        document.append(PrintElement.title("BULLETIN"))
        document.append(PrintElement.centered(formatter.format(date)))
        document.append(PrintElement.Separator('='))

        document.append(
            PrintElement.Text("METEO", bold = true, alignment = Escpos.Alignment.CENTER)
        )
        // Le degre est translitere en « deg »: le firmware imprime un carre
        // plein pour tout caractere non-ASCII.
        document.append(PrintElement.Text(TextLayout.columns("Matin", "12°C", COLUMNS)))
        document.append(PrintElement.Text(TextLayout.columns("Apres-midi", "18°C", COLUMNS)))
        document.append(PrintElement.Text(TextLayout.columns("Soir", "14°C", COLUMNS)))
        document.append(
            PrintElement.Text("Ciel voile le matin, belles eclaircies l'apres-midi.")
        )

        document.append(PrintElement.Separator())
        document.append(
            PrintElement.Text("HOROSCOPE", bold = true, alignment = Escpos.Alignment.CENTER)
        )
        document.append(PrintElement.Text("Balance: journee propice aux decisions."))
        document.append(PrintElement.Text("Chiffre porte-bonheur: 7"))

        document.append(PrintElement.Separator('='))
        document.append(PrintElement.centered("Bonne journee"))
        document.append(PrintElement.Feed(2))
        return document
    }

    /**
     * Mire typographique: montre ce que le firmware sait rendre.
     *
     * Les limitations connues (accents, inversion video) sont volontairement
     * incluses pour rester verifiables sur papier.
     */
    fun typographySampler(): PrintDocument {
        val document = PrintDocument()

        document.append(PrintElement.title("TYPOGRAPHIE"))
        document.append(PrintElement.Separator('='))

        document.append(PrintElement.Text("Taille 1 - texte normal"))
        document.append(PrintElement.Text("Taille 2", size = 2))
        document.append(PrintElement.Text("Taille 3", size = 3))

        document.append(PrintElement.Separator())
        // Le gras et l'inversion video sont acceptes par le firmware sans
        // etre appliques. Les lignes restent dans la mire pour que ce soit
        // constatable sur le papier, mais leur libelle le dit.
        document.append(PrintElement.Text("Gras (sans effet ici)", bold = true))
        document.append(PrintElement.Text("Souligne", underline = true))
        document.append(PrintElement.Text("Inverse (sans effet ici)", inverted = true))

        document.append(PrintElement.Separator())
        document.append(PrintElement.Text("Gauche", alignment = Escpos.Alignment.LEFT))
        document.append(PrintElement.Text("Centre", alignment = Escpos.Alignment.CENTER))
        document.append(PrintElement.Text("Droite", alignment = Escpos.Alignment.RIGHT))

        document.append(PrintElement.Separator())
        document.append(PrintElement.Text("Accents: eleve a Noel, 18°C, 12 €"))
        document.append(PrintElement.Text("Ligne de 32 caracteres exactement:"))
        document.append(PrintElement.Text("12345678901234567890123456789012"))

        document.append(PrintElement.Feed(2))
        return document
    }
}
