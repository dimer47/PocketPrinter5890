import Foundation

/// Documents de demonstration en texte natif.
///
/// Ces documents n'utilisent aucune rasterisation: tout passe par les
/// commandes ESC/POS de mise en forme, donc par la police interne de
/// l'imprimante. C'est le meilleur moyen de verifier ce que le firmware
/// sait reellement faire, et c'est bien plus rapide qu'un raster.
public enum DemoDocuments {

    /// Bulletin meteo et horoscope fictifs.
    ///
    /// Sert de vitrine: tailles multiples, gras, souligne, inversion video,
    /// alignements, separateurs, code-barres et QR code.
    public static func weatherAndHoroscope(date: Date = Date()) -> PrintDocument {
        var document = PrintDocument()

        // En-tete en inverse video, pleine largeur.
        document.append(.text(
            " BULLETIN DU JOUR ",
            size: 1,
            bold: true,
            underline: false,
            inverted: true,
            alignment: .center
        ))
        document.append(.feed(lines: 1))

        document.append(.text(
            Self.dateFormatter.string(from: date),
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .center
        ))
        document.append(.separator(character: "="))

        // --- Meteo
        document.append(.text(
            "METEO",
            size: 2,
            bold: true,
            underline: false,
            inverted: false,
            alignment: .left
        ))
        document.append(.feed(lines: 1))

        document.append(.text(
            "Lille",
            size: 1,
            bold: true,
            underline: true,
            inverted: false,
            alignment: .left
        ))
        document.append(.text(
            "Ciel voile, eclaircies l'apres-midi.",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .left
        ))
        document.append(.feed(lines: 1))

        // Temperature en tres gros, centree.
        document.append(.text(
            "18°C",
            size: 3,
            bold: true,
            underline: false,
            inverted: false,
            alignment: .center
        ))
        document.append(.text(
            "ressenti 16°C",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .center
        ))
        document.append(.feed(lines: 1))

        // Colonnes alignees a gauche et a droite.
        for (label, value) in [
            ("Min / Max", "12° / 21°"),
            ("Vent", "23 km/h SO"),
            ("Humidite", "68 %"),
            ("Pluie", "20 %"),
            ("UV", "4 modere")
        ] {
            document.append(.text(
                Self.columns(label, value),
                size: 1,
                bold: false,
                underline: false,
                inverted: false,
                alignment: .left
            ))
        }

        document.append(.separator(character: "-"))

        // --- Horoscope
        document.append(.text(
            "HOROSCOPE",
            size: 2,
            bold: true,
            underline: false,
            inverted: false,
            alignment: .right
        ))
        document.append(.feed(lines: 1))

        document.append(.text(
            "BELIER",
            size: 2,
            bold: true,
            underline: false,
            inverted: true,
            alignment: .center
        ))
        document.append(.text(
            "21 mars - 19 avril",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .center
        ))
        document.append(.feed(lines: 1))

        document.append(.text(
            "Une journee favorable aux projets",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .left
        ))
        document.append(.text(
            "techniques. Votre perseverance",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .left
        ))
        document.append(.text(
            "finit par payer.",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .left
        ))
        document.append(.feed(lines: 1))

        document.append(.text(
            Self.columns("Amour", "***"),
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .left
        ))
        document.append(.text(
            Self.columns("Travail", "*****"),
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .left
        ))
        document.append(.text(
            Self.columns("Forme", "****"),
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .left
        ))

        document.append(.separator(character: "="))

        // --- Codes
        // Version rasterisee: l'application officielle procede ainsi (ZXing
        // puis raster) et n'emet aucune commande ESC/POS native de code.
        if let qr = try? PrintElement.qr("https://exemple.fr/meteo") {
            document.append(qr)
        }
        document.append(.text(
            "Scannez pour le detail",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .center
        ))
        document.append(.feed(lines: 1))
        if let barcode = try? PrintElement.code("METEO2026", height: 70) {
            document.append(barcode)
        }

        return document
    }

    /// Nuancier typographique: chaque capacite du firmware, une par ligne.
    ///
    /// Utile pour verifier precisement ce que la machine supporte, sans
    /// interpretation.
    public static func typographySampler() -> PrintDocument {
        var document = PrintDocument()

        document.append(.text(
            " STYLES DISPONIBLES ",
            size: 1,
            bold: true,
            underline: false,
            inverted: true,
            alignment: .center
        ))
        document.append(.separator(character: "="))

        document.append(.text("Texte normal"))
        document.append(.text(
            "Texte gras",
            size: 1,
            bold: true,
            underline: false,
            inverted: false,
            alignment: .left
        ))
        document.append(.text(
            "Texte souligne",
            size: 1,
            bold: false,
            underline: true,
            inverted: false,
            alignment: .left
        ))
        document.append(.text(
            "Texte inverse",
            size: 1,
            bold: false,
            underline: false,
            inverted: true,
            alignment: .left
        ))
        document.append(.separator(character: "-"))

        document.append(.text("Aligne a gauche"))
        document.append(.centered("Centre"))
        document.append(.text(
            "Aligne a droite",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .right
        ))
        document.append(.separator(character: "-"))

        // Tailles 1 a 4: au-dela, une ligne ne tient plus sur 384 px.
        for size in 1...4 {
            document.append(.text(
                "Taille \(size)",
                size: size,
                bold: false,
                underline: false,
                inverted: false,
                alignment: .left
            ))
        }
        document.append(.separator(character: "-"))

        document.append(.text("Accents: eeaaiouc ÀÉÈÊÇÔÙ"))
        document.append(.text("Chiffres: 0123456789"))
        document.append(.text("Symboles: !?@#%&*()[]{}/\\"))
        document.append(.text("Monnaie: 12,50 EUR"))

        return document
    }

    /// Mire de diagnostic des pages de code.
    ///
    /// Imprime la meme serie de caracteres accentues apres chaque commande
    /// `ESC t n`. La ligne dont les caracteres sortent correctement designe
    /// la table reellement utilisee par le firmware; si toutes echouent,
    /// c'est que `ESC t` est ignore et il faut transliterer.
    public static func codePageProbe() -> PrintDocument {
        var document = PrintDocument()

        document.append(.text(
            "TEST PAGES DE CODE",
            size: 1,
            bold: true,
            underline: false,
            inverted: false,
            alignment: .center
        ))
        document.append(.separator(character: "="))
        document.append(.text("Reference ASCII:"))
        document.append(.text("degre C, aout, ete"))
        document.append(.separator(character: "-"))

        // Octets bruts des caracteres vises, identiques d'une table a l'autre
        // seulement si le firmware suit la page demandee.
        for page in ESCPOS.CodePageCandidate.allCases {
            document.append(.raw(ESCPOS.codePage(page.rawValue)))
            document.append(.text("\(page.rawValue): \(page.title)"))
            // `°` `é` `è` `à` `û` `ç` dans leurs valeurs CP1252.
            document.append(.raw(
                [0xb0, 0x20, 0xe9, 0x20, 0xe8, 0x20, 0xe0, 0x20, 0xfb, 0x20, 0xe7] + ESCPOS.lineFeed
            ))
        }

        // On restaure une page connue avant de rendre la main.
        document.append(.raw(ESCPOS.codePageLatin1))
        document.append(.separator(character: "="))
        document.append(.text(
            "Ligne correcte = bonne table",
            size: 1,
            bold: false,
            underline: false,
            inverted: false,
            alignment: .center
        ))

        return document
    }

    // MARK: - Aides

    /// Met une etiquette a gauche et une valeur a droite.
    ///
    /// Pratique pour composer des lignes de ticket en texte natif, ou
    /// l'imprimante ne gere qu'un seul alignement par ligne.
    public static func columns(_ left: String, _ right: String, width: Int = 32) -> String {
        TextLayout.columns(left, right, width: width)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy - HH:mm"
        return formatter
    }()
}
