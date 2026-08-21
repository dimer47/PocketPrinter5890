package fr.pocketprinter5890.kit

/**
 * Largeurs d'impression supportees, exprimees en pixels.
 *
 * La machine de reference (SilverCrest/Tronic Lidl, famille generique 5890,
 * papier ticket ~56 mm, 203 dpi) imprime sur 384 px = 48 octets par ligne.
 * Les autres valeurs sont fournies pour d'autres materiels et ne doivent pas
 * devenir le defaut.
 */
enum class PrinterWidth(val pixels: Int, val title: String) {
    /** 58 mm de papier, 48 mm imprimables. Defaut de la famille 5890. */
    MM58(384, "58 mm - 384 px (defaut)"),

    /** 80 mm de papier, 72 mm imprimables. */
    MM80(576, "80 mm - 576 px"),

    /** Etiquettes 14 mm de la L13 documentee par atctwo. Compatibilite uniquement. */
    LABEL_14MM(96, "Etiquette 14 mm - 96 px");

    val bytesPerLine: Int get() = pixels / 8
}

/** Erreurs de construction d'un bitmap. */
sealed class RasterException(message: String) : Exception(message) {
    object InvalidDimensions : RasterException("Dimensions raster invalides") {
        private fun readResolve(): Any = InvalidDimensions
    }

    class InvalidDataSize(expected: Int, actual: Int) :
        RasterException("Taille raster invalide: $actual octets au lieu de $expected")

    class InvalidPixelCount(expected: Int, actual: Int) :
        RasterException("Nombre de pixels invalide: $actual au lieu de $expected")

    class WidthNotByteAligned(width: Int) :
        RasterException("Largeur $width px non multiple de 8")
}

/**
 * Image monochrome prete a etre encodee en commande raster.
 *
 * Un bit par pixel, MSB en premier: le pixel le plus a gauche d'une ligne est
 * le bit 7 du premier octet. Un bit a 1 imprime un point noir.
 */
class MonochromeBitmap
@Throws(RasterException::class)
constructor(
    val width: Int = nativeWidth,
    val height: Int,
    val bytes: ByteArray
) {
    val widthBytes: Int get() = (width + 7) / 8

    init {
        if (width <= 0 || height <= 0) throw RasterException.InvalidDimensions
        if (width % 8 != 0) throw RasterException.WidthNotByteAligned(width)
        val expected = ((width + 7) / 8) * height
        if (bytes.size != expected) {
            throw RasterException.InvalidDataSize(expected, bytes.size)
        }
    }

    /** Extrait une bande horizontale, utilisee pour l'envoi fragmente. */
    @Throws(RasterException::class)
    fun slice(fromLine: Int, lineCount: Int): MonochromeBitmap {
        if (fromLine < 0 || lineCount <= 0 || fromLine + lineCount > height) {
            throw RasterException.InvalidDimensions
        }
        val stride = widthBytes
        return MonochromeBitmap(
            width = width,
            height = lineCount,
            bytes = bytes.copyOfRange(fromLine * stride, (fromLine + lineCount) * stride)
        )
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is MonochromeBitmap) return false
        return width == other.width && height == other.height && bytes.contentEquals(other.bytes)
    }

    override fun hashCode(): Int =
        (width * 31 + height) * 31 + bytes.contentHashCode()

    companion object {
        /**
         * Largeur native de la machine cible: 384 px.
         *
         * Anciennement 96 px cote Swift, valeur heritee d'un modele different
         * (L13 a etiquettes) qui empechait toute impression.
         */
        const val nativeWidth: Int = 384
    }
}

object RasterEncoder {
    /**
     * Nombre de lignes par bande envoyee a l'imprimante.
     *
     * Le firmware perd des donnees quand on lui envoie un raster de plusieurs
     * milliers d'octets en une seule commande. Toutes les implementations qui
     * fonctionnent sur cette famille decoupent en bandes.
     */
    const val defaultBandHeight: Int = 24

    @Throws(RasterException::class)
    fun encodeBlackPixels(
        pixels: BooleanArray,
        width: Int = MonochromeBitmap.nativeWidth,
        height: Int
    ): MonochromeBitmap {
        if (width <= 0 || height <= 0) throw RasterException.InvalidDimensions
        if (width % 8 != 0) throw RasterException.WidthNotByteAligned(width)
        val expected = width * height
        if (pixels.size != expected) {
            throw RasterException.InvalidPixelCount(expected, pixels.size)
        }

        val widthBytes = (width + 7) / 8
        val output = ByteArray(widthBytes * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                if (!pixels[y * width + x]) continue
                val index = y * widthBytes + x / 8
                output[index] = (output[index].toInt() or (0x80 shr (x % 8))).toByte()
            }
        }
        return MonochromeBitmap(width, height, output)
    }

    /**
     * Commande raster unique `1D 76 30 00 xL xH yL yH <pixels>`.
     *
     * Pour un bitmap de plus de quelques dizaines de lignes, preferer
     * [bandedRasterCommands].
     */
    fun rasterCommand(bitmap: MonochromeBitmap): ByteArray {
        val x = bitmap.widthBytes
        val y = bitmap.height
        return byteArrayOf(
            0x1d, 0x76, 0x30, 0x00,
            (x and 0xff).toByte(), ((x shr 8) and 0xff).toByte(),
            (y and 0xff).toByte(), ((y shr 8) and 0xff).toByte()
        ) + bitmap.bytes
    }

    /** Decoupe le bitmap en bandes, chacune etant une commande raster complete. */
    fun bandedRasterCommands(
        bitmap: MonochromeBitmap,
        bandHeight: Int = defaultBandHeight
    ): List<ByteArray> {
        val step = maxOf(1, bandHeight)
        val commands = mutableListOf<ByteArray>()
        var line = 0
        while (line < bitmap.height) {
            val count = minOf(step, bitmap.height - line)
            runCatching { bitmap.slice(line, count) }
                .getOrNull()
                ?.let { commands.add(rasterCommand(it)) }
            line += count
        }
        return commands
    }
}

/** Conversion niveaux de gris vers monochrome. */
object MonochromeConverter {

    @Throws(RasterException::class)
    fun threshold(
        grayscale: IntArray,
        width: Int,
        height: Int,
        threshold: Int
    ): MonochromeBitmap {
        if (grayscale.size != width * height) {
            throw RasterException.InvalidPixelCount(width * height, grayscale.size)
        }
        return RasterEncoder.encodeBlackPixels(
            BooleanArray(grayscale.size) { grayscale[it] < threshold },
            width,
            height
        )
    }

    @Throws(RasterException::class)
    fun orderedDither(grayscale: IntArray, width: Int, height: Int): MonochromeBitmap {
        if (grayscale.size != width * height) {
            throw RasterException.InvalidPixelCount(width * height, grayscale.size)
        }
        val matrix = arrayOf(
            intArrayOf(0, 8, 2, 10),
            intArrayOf(12, 4, 14, 6),
            intArrayOf(3, 11, 1, 9),
            intArrayOf(15, 7, 13, 5)
        )
        val pixels = BooleanArray(grayscale.size)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val limit = matrix[y % 4][x % 4] * 16 + 8
                pixels[y * width + x] = grayscale[y * width + x] < limit
            }
        }
        return RasterEncoder.encodeBlackPixels(pixels, width, height)
    }

    /**
     * Diffusion d'erreur Floyd-Steinberg: bien meilleur rendu photo que le
     * tramage ordonne.
     */
    @Throws(RasterException::class)
    fun floydSteinberg(grayscale: IntArray, width: Int, height: Int): MonochromeBitmap {
        if (grayscale.size != width * height) {
            throw RasterException.InvalidPixelCount(width * height, grayscale.size)
        }
        val buffer = grayscale.copyOf()
        val pixels = BooleanArray(width * height)

        fun spread(x: Int, y: Int, error: Int, factor: Int) {
            if (x < 0 || x >= width || y < 0 || y >= height) return
            buffer[y * width + x] += error * factor / 16
        }

        for (y in 0 until height) {
            for (x in 0 until width) {
                val index = y * width + x
                val old = buffer[index]
                val new = if (old < 128) 0 else 255
                pixels[index] = new == 0
                val error = old - new

                spread(x + 1, y, error, 7)
                spread(x - 1, y + 1, error, 3)
                spread(x, y + 1, error, 5)
                spread(x + 1, y + 1, error, 1)
            }
        }
        return RasterEncoder.encodeBlackPixels(pixels, width, height)
    }
}
