package fr.pocketprinter5890.render

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import fr.pocketprinter5890.kit.MonochromeBitmap
import fr.pocketprinter5890.kit.MonochromeConverter
import fr.pocketprinter5890.kit.Receipt
import fr.pocketprinter5890.kit.RasterException
import fr.pocketprinter5890.kit.formatCents
import java.text.SimpleDateFormat
import java.util.Locale

/** Orientation du rendu. */
enum class ReceiptOrientation(val title: String) {
    NORMAL("Normal"),
    ROTATED_90("Rotation 90 deg")
}

/** Methode de conversion des niveaux de gris en noir et blanc. */
enum class DitherMode(val title: String) {
    /** Seuil dur. Le seul valable pour un code a scanner. */
    THRESHOLD("Seuil"),
    ORDERED("Tramage ordonne"),
    FLOYD_STEINBERG("Floyd-Steinberg")
}

/**
 * Rendu d'un ticket en bitmap monochrome.
 *
 * Equivalent Android de `ReceiptRenderer` cote Swift: meme mise en page,
 * memes proportions, dessine ici avec `android.graphics` au lieu de
 * CoreGraphics.
 *
 * C'est le chemin qu'emprunte l'application officielle pour **tout** son
 * texte, ce qui lui permet le gras et les accents que le firmware ne sait pas
 * rendre lui-meme. En contrepartie le resultat est plus doux que la police
 * interne, et un ticket pese des milliers d'octets au lieu de quelques
 * dizaines.
 */
class ReceiptRenderer(
    val width: Int = MonochromeBitmap.nativeWidth,
    /**
     * Seuil de noircissement, 0 a 255.
     *
     * Un pixel plus sombre que cette valeur est imprime en noir. Monter le
     * seuil epaissit le rendu: utile quand le texte antialiase sort trop
     * maigre.
     */
    val threshold: Int = 160,
    /**
     * Defaut: seuil dur.
     *
     * Un ticket est fait de traits, pas de degrades. Floyd-Steinberg disperse
     * les pixels pour simuler du gris: applique a du texte, il transforme
     * chaque trait plein en semis de points et le rendu sort tres clair et
     * tres fin. Le tramage n'a d'interet que pour une photo.
     */
    val ditherMode: DitherMode = DitherMode.THRESHOLD,
    val orientation: ReceiptOrientation = ReceiptOrientation.NORMAL
) {

    // MARK: - Rendu de ticket

    /** Rend le ticket en bitmap pret a etre envoye en raster. */
    @Throws(RasterException::class)
    fun render(receipt: Receipt): MonochromeBitmap {
        val image = renderToBitmap(receipt)
        return try {
            convert(image)
        } finally {
            image.recycle()
        }
    }

    /**
     * Image de previsualisation, affichable directement par l'interface.
     *
     * Elle passe par la meme binarisation que l'impression: un apercu en
     * niveaux de gris montrerait un rendu plus dense que le papier, et le
     * reglage du seuil n'y serait pas visible.
     *
     * L'appelant est responsable de son cycle de vie.
     */
    fun previewImage(receipt: Receipt): Bitmap {
        val drawn = renderToBitmap(receipt)
        return try {
            toDisplayBitmap(convert(drawn))
        } finally {
            drawn.recycle()
        }
    }

    /** Reconstruit une image affichable a partir du bitmap monochrome. */
    private fun toDisplayBitmap(source: MonochromeBitmap): Bitmap {
        val pixels = IntArray(source.width * source.height)
        for (y in 0 until source.height) {
            for (x in 0 until source.width) {
                val byte = source.bytes[y * source.widthBytes + x / 8].toInt() and 0xff
                val on = (byte shr (7 - x % 8)) and 1 == 1
                pixels[y * source.width + x] = if (on) Color.BLACK else Color.WHITE
            }
        }
        return Bitmap.createBitmap(
            pixels, source.width, source.height, Bitmap.Config.ARGB_8888
        )
    }

    private fun renderToBitmap(receipt: Receipt): Bitmap {
        val height = contentHeight(receipt)
        val image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(image)
        canvas.drawColor(Color.WHITE)
        drawReceipt(receipt, canvas, height)
        return image
    }

    private fun contentHeight(receipt: Receipt): Int =
        90 + receipt.items.size * 22 + 80

    // MARK: - Conversion d'image quelconque

    /**
     * Convertit une image a la largeur d'impression, proportions conservees.
     *
     * Le filtrage est actif ici: pour une photo il ameliore le rendu. A
     * proscrire en revanche pour un code a scanner, dont les bords doivent
     * rester francs.
     */
    @Throws(RasterException::class)
    fun bitmap(source: Bitmap): MonochromeBitmap {
        if (source.width <= 0 || source.height <= 0) {
            throw RasterException.InvalidDimensions
        }
        val scale = width.toDouble() / source.width
        val height = maxOf(1, Math.round(source.height * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(source, width, height, true)
        return try {
            convert(scaled)
        } finally {
            if (scaled !== source) scaled.recycle()
        }
    }

    // MARK: - Mire

    /** Mire de controle: cadre, graduation, damier de densite, aplat plein. */
    @Throws(RasterException::class)
    fun testPattern(height: Int = 240): MonochromeBitmap {
        val image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(image)
        canvas.drawColor(Color.WHITE)
        drawTestPattern(canvas, height)
        return try {
            convert(image)
        } finally {
            image.recycle()
        }
    }

    // MARK: - Dessin

    private fun drawReceipt(receipt: Receipt, canvas: Canvas, height: Int) {
        val margin = 8f
        val right = width - margin
        var y = 10f

        drawText(
            receipt.merchantName.uppercase(Locale.FRANCE), canvas,
            Anchor.Center, y, 22f, bold = true
        )
        y += 30f
        if (receipt.address.isNotEmpty()) {
            drawText(receipt.address, canvas, Anchor.Center, y, 12f)
        }
        y += 18f
        drawText(dateFormatter.format(receipt.date), canvas, Anchor.Center, y, 12f)
        y += 22f

        strokeLine(canvas, margin, right, y)
        y += 10f

        for (item in receipt.items) {
            drawText("${item.quantity}x ${item.name}", canvas, Anchor.Left(margin), y, 13f)
            drawText(formatCents(item.totalCents), canvas, Anchor.Right(right), y, 13f)
            y += 20f
        }

        y += 4f
        strokeLine(canvas, margin, right, y)
        y += 10f

        // Le gras est ici reellement dessine: c'est tout l'interet du chemin
        // image, le firmware ne sachant pas appliquer `ESC E`.
        drawText("TOTAL", canvas, Anchor.Left(margin), y, 17f, bold = true)
        drawText(
            formatCents(receipt.totalCents), canvas,
            Anchor.Right(right), y, 17f, bold = true
        )
        y += 32f

        if (receipt.footer.isNotEmpty()) {
            drawText(receipt.footer, canvas, Anchor.Center, y, 13f)
        }
    }

    private fun drawTestPattern(canvas: Canvas, height: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            strokeWidth = 1f
        }

        // Cadre: verifie que toute la largeur est imprimee.
        paint.style = Paint.Style.STROKE
        canvas.drawRect(0.5f, 0.5f, width - 0.5f, height - 0.5f, paint)

        // Graduation, reperes longs tous les 64 px.
        var x = 0
        while (x < width) {
            val long = x % 64 == 0
            canvas.drawLine(x.toFloat(), 0f, x.toFloat(), if (long) 20f else 10f, paint)
            x += 8
        }

        // Damier de controle de densite.
        paint.style = Paint.Style.FILL
        for (row in 0 until 6) {
            for (column in 0 until 12) {
                if ((row + column) % 2 != 0) continue
                val left = (10 + column * 6).toFloat()
                val top = (34 + row * 6).toFloat()
                canvas.drawRect(left, top, left + 6f, top + 6f, paint)
            }
        }

        // Aplat plein: revele une largeur mal cadree.
        canvas.drawRect(0f, (height - 30).toFloat(), width.toFloat(), (height - 18).toFloat(), paint)

        drawText("$width px", canvas, Anchor.Left(250f), 44f, 15f, bold = true)
        drawText("GAUCHE", canvas, Anchor.Left(4f), height - 52f, 11f)
        drawText("DROITE", canvas, Anchor.Right(width - 4f), height - 52f, 11f)
    }

    // MARK: - Primitives de dessin

    private sealed class Anchor {
        data class Left(val x: Float) : Anchor()
        data class Right(val x: Float) : Anchor()
        object Center : Anchor()
    }

    private fun strokeLine(canvas: Canvas, from: Float, to: Float, y: Float) {
        val paint = Paint().apply {
            color = Color.BLACK
            strokeWidth = 1f
        }
        canvas.drawLine(from, y, to, y, paint)
    }

    private fun drawText(
        text: String,
        canvas: Canvas,
        anchor: Anchor,
        y: Float,
        size: Float,
        bold: Boolean = false
    ) {
        // Police a chasse fixe: les colonnes d'un ticket doivent s'aligner.
        //
        // L'antialiasing est conserve car il rend les formes des lettres, mais
        // il produit des bords gris que le seuil supprime, ce qui amaigrit le
        // trait. `isFakeBoldText` compense en epaississant le glyphe lui-meme:
        // le noir reellement pose sur le papier augmente, la ou `Typeface.BOLD`
        // seul reste trop fin une fois binarise.
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = size
            typeface = Typeface.create(
                Typeface.MONOSPACE,
                if (bold) Typeface.BOLD else Typeface.NORMAL
            )
            isFakeBoldText = bold
        }
        val measured = paint.measureText(text)
        val x = when (anchor) {
            is Anchor.Left -> anchor.x
            is Anchor.Right -> anchor.x - measured
            Anchor.Center -> (width - measured) / 2f
        }
        // `y` designe le haut du texte, comme cote Swift: on decale de
        // l'ascendante pour que les deux rendus se superposent.
        canvas.drawText(text, x, y - paint.fontMetrics.ascent, paint)
    }

    // MARK: - Conversion

    @Throws(RasterException::class)
    private fun convert(image: Bitmap): MonochromeBitmap {
        val source = if (orientation == ReceiptOrientation.ROTATED_90) {
            rotate90(image)
        } else {
            image
        }
        try {
            val imageWidth = source.width
            val imageHeight = source.height
            val pixels = IntArray(imageWidth * imageHeight)
            source.getPixels(pixels, 0, imageWidth, 0, 0, imageWidth, imageHeight)

            // Luminance perceptuelle: un gris moyen naif noircit les rouges.
            val gray = IntArray(pixels.size) { index ->
                val pixel = pixels[index]
                val red = (pixel shr 16) and 0xff
                val green = (pixel shr 8) and 0xff
                val blue = pixel and 0xff
                (red * 299 + green * 587 + blue * 114) / 1000
            }

            return when (ditherMode) {
                DitherMode.THRESHOLD ->
                    MonochromeConverter.threshold(gray, imageWidth, imageHeight, threshold)
                DitherMode.ORDERED ->
                    MonochromeConverter.orderedDither(gray, imageWidth, imageHeight)
                DitherMode.FLOYD_STEINBERG ->
                    MonochromeConverter.floydSteinberg(gray, imageWidth, imageHeight)
            }
        } finally {
            if (source !== image) source.recycle()
        }
    }

    /**
     * Rotation d'un quart de tour.
     *
     * La largeur devient l'ancienne hauteur, qui n'a aucune raison d'etre un
     * multiple de 8. Comme un bitmap monochrome exige des lignes entieres en
     * octets, on complete a droite en blanc jusqu'au multiple suivant plutot
     * que de laisser echouer la conversion.
     */
    private fun rotate90(image: Bitmap): Bitmap {
        val matrix = android.graphics.Matrix().apply { postRotate(90f) }
        val rotated = Bitmap.createBitmap(image, 0, 0, image.width, image.height, matrix, true)
        if (rotated.width % 8 == 0) return rotated

        val padded = ((rotated.width + 7) / 8) * 8
        val output = Bitmap.createBitmap(padded, rotated.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(rotated, 0f, 0f, null)
        rotated.recycle()
        return output
    }

    private companion object {
        val dateFormatter = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.FRANCE)
    }
}
