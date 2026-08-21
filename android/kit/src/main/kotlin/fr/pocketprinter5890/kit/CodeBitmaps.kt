package fr.pocketprinter5890.kit

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/** Erreurs de generation d'un code en bitmap. */
sealed class CodeException(message: String) : Exception(message) {
    object EmptyContent : CodeException("Contenu vide") {
        private fun readResolve(): Any = EmptyContent
    }

    object GenerationFailed : CodeException("Generation du code impossible") {
        private fun readResolve(): Any = GenerationFailed
    }
}

/**
 * Conversion des codes en bitmaps imprimables.
 *
 * Les codes-barres lineaires sont generes en Kotlin pur ([Barcode1D]), donc
 * portables partout. Les QR codes s'appuient sur ZXing: ecrire un encodeur QR
 * conforme (masques, evaluation de penalite, format BCH) est une source
 * d'erreurs silencieuses, et un QR faux ne se voit qu'au scanner. C'est aussi
 * la bibliotheque qu'utilise l'application officielle. Le moteur est isole ici
 * pour pouvoir etre remplace sans toucher au reste de la librairie.
 *
 * Dans tous les cas les modules sont ecrits directement dans le bitmap, sans
 * interpolation: un code redimensionne en douceur devient illisible.
 */
object CodeBitmaps {

    enum class QRCorrectionLevel(val title: String) {
        LOW("Faible (7 %)"),
        MEDIUM("Moyen (15 %)"),
        QUARTILE("Bon (25 %)"),
        HIGH("Maximal (30 %)");

        internal val zxing: ErrorCorrectionLevel
            get() = when (this) {
                LOW -> ErrorCorrectionLevel.L
                MEDIUM -> ErrorCorrectionLevel.M
                QUARTILE -> ErrorCorrectionLevel.Q
                HIGH -> ErrorCorrectionLevel.H
            }
    }

    /** Matrice de modules d'un QR code, sans zone de silence. */
    class QRMatrix(val size: Int, val modules: BooleanArray) {
        operator fun get(x: Int, y: Int): Boolean = modules[y * size + x]
    }

    /**
     * Genere la matrice brute d'un QR code, sans mise a l'echelle.
     *
     * ZXing ajoute une zone de silence par defaut; on la desactive ici pour
     * maitriser nous-memes la marge dans [qrCode].
     */
    @Throws(CodeException::class)
    fun qrMatrix(
        content: String,
        correction: QRCorrectionLevel = QRCorrectionLevel.MEDIUM
    ): QRMatrix {
        if (content.isEmpty()) throw CodeException.EmptyContent
        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to correction.zxing,
            EncodeHintType.CHARACTER_SET to "UTF-8",
            // La zone de silence est ajoutee par qrCode(), pas par ZXing.
            EncodeHintType.MARGIN to 0
        )
        val matrix = runCatching {
            QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, 0, 0, hints)
        }.getOrElse { throw CodeException.GenerationFailed }

        val size = matrix.width
        if (size <= 0 || matrix.height != size) throw CodeException.GenerationFailed

        val modules = BooleanArray(size * size)
        for (y in 0 until size) {
            for (x in 0 until size) {
                modules[y * size + x] = matrix.get(x, y)
            }
        }
        return QRMatrix(size, modules)
    }

    /**
     * QR code centre sur la largeur d'impression.
     *
     * @param moduleSize taille d'un module en pixels. Calculee automatiquement
     *   pour occuper environ deux tiers de la largeur si elle vaut null.
     * @param quietZone marge blanche autour du code, en modules. La norme en
     *   exige 4; en dessous, beaucoup de lecteurs echouent.
     */
    @Throws(CodeException::class, RasterException::class)
    fun qrCode(
        content: String,
        correction: QRCorrectionLevel = QRCorrectionLevel.MEDIUM,
        moduleSize: Int? = null,
        quietZone: Int = 4,
        printWidth: Int = MonochromeBitmap.nativeWidth
    ): MonochromeBitmap {
        if (content.isEmpty()) throw CodeException.EmptyContent
        val matrix = qrMatrix(content, correction)
        val totalModules = matrix.size + quietZone * 2

        // Taille de module par defaut: le code occupe environ deux tiers de la
        // largeur, sans jamais la depasser.
        val scale = moduleSize ?: maxOf(1, (printWidth * 2 / 3) / totalModules)
        val codeSize = minOf(totalModules * scale, printWidth)

        val widthBytes = (printWidth + 7) / 8
        val bytes = ByteArray(widthBytes * codeSize)

        val originX = (printWidth - codeSize) / 2
        for (y in 0 until codeSize) {
            val moduleY = y / scale - quietZone
            if (moduleY < 0 || moduleY >= matrix.size) continue
            for (x in 0 until codeSize) {
                val moduleX = x / scale - quietZone
                if (moduleX < 0 || moduleX >= matrix.size) continue
                if (!matrix[moduleX, moduleY]) continue
                val pixelX = originX + x
                val index = y * widthBytes + pixelX / 8
                bytes[index] = (bytes[index].toInt() or (0x80 shr (pixelX % 8))).toByte()
            }
        }
        return MonochromeBitmap(printWidth, codeSize, bytes)
    }

    /**
     * Code-barres lineaire centre sur la largeur d'impression.
     *
     * @param moduleWidth largeur d'une barre elementaire. Calculee pour remplir
     *   la largeur disponible si elle vaut null.
     * @param quietZone marge blanche laterale en pixels.
     */
    @Throws(BarcodeException::class, RasterException::class)
    fun barcode(
        content: String,
        symbology: Barcode1D.Symbology = Barcode1D.Symbology.CODE128,
        height: Int = 80,
        moduleWidth: Int? = null,
        quietZone: Int = 20,
        printWidth: Int = MonochromeBitmap.nativeWidth
    ): MonochromeBitmap {
        val pattern = Barcode1D.pattern(content, symbology)
        val available = maxOf(1, printWidth - quietZone * 2)
        val scale = moduleWidth ?: maxOf(1, available / pattern.size)
        val codeWidth = minOf(pattern.size * scale, printWidth)

        val codeHeight = maxOf(8, height)
        val widthBytes = (printWidth + 7) / 8
        val bytes = ByteArray(widthBytes * codeHeight)

        val originX = (printWidth - codeWidth) / 2
        for (x in 0 until codeWidth) {
            val index = x / scale
            if (index >= pattern.size || !pattern[index]) continue
            val pixelX = originX + x
            for (y in 0 until codeHeight) {
                val offset = y * widthBytes + pixelX / 8
                bytes[offset] = (bytes[offset].toInt() or (0x80 shr (pixelX % 8))).toByte()
            }
        }
        return MonochromeBitmap(printWidth, codeHeight, bytes)
    }
}

/**
 * QR code genere en bitmap, portable et sans commande native.
 *
 * A preferer a [PrintElement.QrCode], qui repose sur la commande native
 * `GS ( k` que ce firmware n'implemente pas.
 */
@Throws(CodeException::class, RasterException::class)
fun PrintElement.Companion.qr(
    content: String,
    correction: CodeBitmaps.QRCorrectionLevel = CodeBitmaps.QRCorrectionLevel.MEDIUM,
    moduleSize: Int? = null,
    printWidth: Int = MonochromeBitmap.nativeWidth
): PrintElement = PrintElement.Image(
    CodeBitmaps.qrCode(content, correction, moduleSize, printWidth = printWidth)
)

/** Code-barres genere en bitmap, seule voie fiable sur ce firmware. */
@Throws(BarcodeException::class, RasterException::class)
fun PrintElement.Companion.code(
    content: String,
    symbology: Barcode1D.Symbology = Barcode1D.Symbology.CODE128,
    height: Int = 80,
    printWidth: Int = MonochromeBitmap.nativeWidth
): PrintElement = PrintElement.Image(
    CodeBitmaps.barcode(content, symbology, height, printWidth = printWidth)
)
