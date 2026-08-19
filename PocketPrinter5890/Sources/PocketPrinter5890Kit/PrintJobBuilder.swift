import Foundation

public struct PrintSegment: Equatable {
    public var name: String
    public var bytes: [UInt8]

    public init(name: String, bytes: [UInt8]) {
        self.name = name
        self.bytes = bytes
    }
}

/// Mode de sortie papier.
public enum PaperMode: String, CaseIterable, Identifiable, Sendable {
    /// Rouleau continu type ticket de caisse. Ne declare pas de longueur:
    /// l'imprimante s'arrete a la fin du contenu.
    case continuous
    /// Etiquettes predecoupees de longueur fixe, avec calage entre chaque.
    case label

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .continuous: return "Papier continu"
        case .label: return "Etiquettes"
        }
    }
}

public struct PrintOptions: Equatable {
    /// Largeur d'impression. 384 px pour la machine de l'utilisateur.
    public var width: PrinterWidth
    public var density: PrintDensity
    /// Nombre de lignes par bande raster. Le firmware perd des donnees si on
    /// envoie le raster complet en une seule commande.
    public var bandHeight: Int
    /// Avance de fin de travail, en points (1/203 de pouce).
    ///
    /// Elle degage le contenu imprime de la tete d'impression, qui se trouve
    /// en retrait dans le boitier. Sans elle, la fin du ticket reste coincee
    /// sous le capot et n'est pas lisible.
    ///
    /// Le SDK appelle cela `endLineDot` et le regle par modele: de 50 points
    /// (D82S) a 144 points (PPS1H). 80 points valent environ 10 mm a 203 dpi.
    ///
    /// La valeur n'est pas bornee a 255: `ESCPOS.feed(dots:)` enchaine
    /// plusieurs commandes `1B 4A` quand c'est necessaire.
    public var trailingFeedDots: Int
    /// Envoie `ESC @` au debut du travail.
    public var sendInitialize: Bool
    /// Encadre le travail par la sequence d'activation LuckPrinter.
    /// Indispensable sur cette machine: sans elle le firmware acquitte
    /// les commandes mais n'execute rien.
    public var useLuckSequence: Bool
    /// Mode de sortie: papier continu ou etiquettes predecoupees.
    public var paperMode: PaperMode
    /// Longueur d'etiquette passee a `1F 80`, ignoree en papier continu.
    public var labelLength: UInt8
    /// Convertit les caracteres non-ASCII en equivalents ASCII.
    ///
    /// Le firmware n'affiche pas correctement `°` ni les lettres accentuees:
    /// il imprime un carre plein. La transliteration donne « deg », « e »,
    /// ce qui reste lisible.
    public var transliterateText: Bool
    /// Interroge l'etat du papier avant d'imprimer. Purement informatif: le
    /// resultat ne doit jamais bloquer l'impression.
    public var checkPaper: Bool
    /// Commandes proprietaires observees dans une capture de l'application
    /// officielle, non confirmees sur ce materiel. Desactivees par defaut.
    public var includeExperimentalPrePrint: Bool
    public var experimentalPrePrintUsesF130: Bool
    public var includeExperimentalPostPrint: Bool
    /// Emet un form feed en fin de travail. Inutile sur papier continu.
    public var includeFormFeed: Bool
    public var formFeed: FormFeedMode

    public init(
        width: PrinterWidth = .mm58,
        density: PrintDensity = .medium,
        bandHeight: Int = RasterEncoder.defaultBandHeight,
        trailingFeedDots: Int = 80,
        sendInitialize: Bool = true,
        useLuckSequence: Bool = true,
        transliterateText: Bool = true,
        paperMode: PaperMode = .continuous,
        labelLength: UInt8 = 32,
        checkPaper: Bool = false,
        includeExperimentalPrePrint: Bool = false,
        experimentalPrePrintUsesF130: Bool = false,
        includeExperimentalPostPrint: Bool = false,
        includeFormFeed: Bool = false,
        formFeed: FormFeedMode = .standard
    ) {
        self.width = width
        self.density = density
        self.bandHeight = bandHeight
        self.trailingFeedDots = trailingFeedDots
        self.sendInitialize = sendInitialize
        self.useLuckSequence = useLuckSequence
        self.transliterateText = transliterateText
        self.paperMode = paperMode
        self.labelLength = labelLength
        self.checkPaper = checkPaper
        self.includeExperimentalPrePrint = includeExperimentalPrePrint
        self.experimentalPrePrintUsesF130 = experimentalPrePrintUsesF130
        self.includeExperimentalPostPrint = includeExperimentalPostPrint
        self.includeFormFeed = includeFormFeed
        self.formFeed = formFeed
    }

    /// Nombre approximatif de colonnes de texte en police A (12 px de large).
    public var textColumns: Int {
        max(1, width.pixels / 12)
    }
}

public enum PrintJobBuilder {
    // MARK: - Documents

    public static func segments(document: PrintDocument, options: PrintOptions) -> [PrintSegment] {
        var result = prologue(options: options)

        for (index, element) in document.elements.enumerated() {
            let bytes = element.bytes(
                columns: options.textColumns,
                bandHeight: options.bandHeight,
                transliterate: options.transliterateText
            )
            guard !bytes.isEmpty else { continue }
            result.append(PrintSegment(name: label(for: element, index: index), bytes: bytes))
        }

        result += epilogue(options: options)
        return result
    }

    public static func bytes(document: PrintDocument, options: PrintOptions) -> [UInt8] {
        segments(document: document, options: options).flatMap(\.bytes)
    }

    // MARK: - Bitmap seul

    public static func segments(bitmap: MonochromeBitmap, options: PrintOptions) -> [PrintSegment] {
        segments(document: PrintDocument(elements: [.image(bitmap)]), options: options)
    }

    public static func bytes(bitmap: MonochromeBitmap, options: PrintOptions) -> [UInt8] {
        segments(bitmap: bitmap, options: options).flatMap(\.bytes)
    }

    // MARK: - Assemblage

    private static func prologue(options: PrintOptions) -> [PrintSegment] {
        var result: [PrintSegment] = []
        if options.checkPaper {
            result.append(PrintSegment(name: "Verifier papier", bytes: PrinterCommand.paperStatus))
        }
        if options.useLuckSequence {
            result.append(PrintSegment(
                name: "Activation moteur",
                bytes: PrinterCommand.Luck.enablePrinter()
            ))
            result.append(PrintSegment(name: "Reveil", bytes: PrinterCommand.Luck.wakeup))
            // `1F 80` declare une etiquette de longueur fixe: l'imprimante
            // deroule alors jusqu'a la fin de l'etiquette declaree. En papier
            // continu, l'application officielle ne l'envoie pas du tout
            // (cf. `printOnce` vs `printTagOnce` dans le SDK).
            if options.paperMode == .label {
                result.append(PrintSegment(
                    name: "Longueur d'etiquette",
                    bytes: PrinterCommand.Luck.setPaperType(length: options.labelLength)
                ))
            }
        }
        if options.sendInitialize {
            result.append(PrintSegment(name: "Init ESC @", bytes: ESCPOS.initialize))
            // `ESC t` n'est pas envoye: ce firmware l'ignore et laisse un
            // octet parasite s'imprimer. Le texte est translitere en ASCII.
            if !options.transliterateText {
                result.append(PrintSegment(
                    name: "Page de code Latin-1",
                    bytes: ESCPOS.codePageLatin1
                ))
            }
        }
        result.append(PrintSegment(
            name: "Densite \(options.density.title)",
            bytes: PrinterCommand.setDensity(options.density)
        ))
        if options.includeExperimentalPrePrint {
            let bytes = options.experimentalPrePrintUsesF130
                ? PrinterCommand.experimentalPrePrintF130
                : PrinterCommand.experimentalPrePrintF103
            result.append(PrintSegment(name: "Pre-impression experimentale", bytes: bytes))
        }
        return result
    }

    private static func epilogue(options: PrintOptions) -> [PrintSegment] {
        var result: [PrintSegment] = []
        if options.includeFormFeed {
            result.append(PrintSegment(
                name: "Form feed \(options.formFeed.title)",
                bytes: options.formFeed.bytes
            ))
        }
        if options.trailingFeedDots > 0 {
            result.append(PrintSegment(
                name: "Degagement \(options.trailingFeedDots) points",
                bytes: ESCPOS.feed(dots: options.trailingFeedDots)
            ))
        }
        if options.useLuckSequence {
            // `1D 0C` cale l'etiquette suivante; sur papier continu il ne fait
            // que gaspiller du papier.
            if options.paperMode == .label {
                result.append(PrintSegment(name: "Calage etiquette", bytes: PrinterCommand.Luck.position))
            }
            result.append(PrintSegment(
                name: "Fin du travail",
                bytes: PrinterCommand.Luck.stopPrintJob
            ))
        }
        if options.includeExperimentalPostPrint {
            result.append(PrintSegment(
                name: "Fin experimentale",
                bytes: PrinterCommand.experimentalPostPrint
            ))
        }
        return result
    }

    private static func label(for element: PrintElement, index: Int) -> String {
        switch element {
        case .text: return "Texte \(index + 1)"
        case let .image(bitmap): return "Image \(bitmap.width)x\(bitmap.height)"
        case .barcode: return "Code-barres"
        case .qrCode: return "QR code"
        case .separator: return "Separateur"
        case .feed: return "Avance"
        case .raw: return "Octets bruts"
        }
    }
}
