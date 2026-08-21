package fr.pocketprinter5890.demo

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import fr.pocketprinter5890.ble.PocketPrinterBleTransport
import fr.pocketprinter5890.kit.PocketPrinter
import fr.pocketprinter5890.kit.PrintDocument
import fr.pocketprinter5890.kit.PrintElement
import fr.pocketprinter5890.kit.PrintOptions
import fr.pocketprinter5890.kit.Receipt
import fr.pocketprinter5890.kit.ReceiptDocument
import fr.pocketprinter5890.kit.ReceiptItem
import fr.pocketprinter5890.kit.ReceiptPrintMode
import fr.pocketprinter5890.kit.TextLayout
import fr.pocketprinter5890.render.DitherMode
import fr.pocketprinter5890.render.ReceiptRenderer
import java.util.Date

@Composable
fun ReceiptScreen(
    transport: PocketPrinterBleTransport,
    options: PrintOptions,
    modifier: Modifier = Modifier
) {
    val isConnected by transport.isConnected.collectAsStateWithLifecycle()
    var merchant by remember { mutableStateOf("BOULANGERIE") }
    var footer by remember { mutableStateOf("Merci de votre visite") }
    var mode by remember { mutableStateOf(ReceiptPrintMode.NATIVE_TEXT) }
    var dither by remember { mutableStateOf(DitherMode.THRESHOLD) }
    var threshold by remember { mutableIntStateOf(160) }

    val receipt = remember(merchant, footer) {
        Receipt(
            merchantName = merchant,
            address = "",
            date = Date(),
            items = listOf(
                ReceiptItem("Baguette", 2, 120),
                ReceiptItem("Croissant", 3, 110),
                ReceiptItem("Cafe", 1, 249)
            ),
            footer = footer
        )
    }

    val columns = options.textColumns
    val printer = PocketPrinter(transport, options)

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        OutlinedTextField(
            value = merchant,
            onValueChange = { merchant = it },
            label = { Text("Enseigne") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = footer,
            onValueChange = { footer = it },
            label = { Text("Pied de ticket") },
            modifier = Modifier.fillMaxWidth()
        )

        Text("Mode d'impression", style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (value in ReceiptPrintMode.entries) {
                FilterChip(
                    selected = mode == value,
                    onClick = { mode = value },
                    label = { Text(value.title) }
                )
            }
        }
        // Aucun des deux modes n'est meilleur en toutes circonstances: le
        // detail dit le compromis plutot que de laisser deviner.
        Text(mode.detail, style = MaterialTheme.typography.bodySmall)

        if (mode == ReceiptPrintMode.RASTER_IMAGE) {
            Text("Rendu de l'image", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (value in DitherMode.entries) {
                    FilterChip(
                        selected = dither == value,
                        onClick = { dither = value },
                        label = { Text(value.title) }
                    )
                }
            }
            // Un ticket est fait de traits, pas de degrades: le tramage
            // disperse les pixels et sort tres clair sur du texte. Il ne vaut
            // que pour une photo.
            Text(
                if (dither == DitherMode.THRESHOLD) {
                    "Seuil dur: le bon choix pour du texte, verifie sur papier."
                } else {
                    "Tramage: reserve aux photos. Sur du texte, chaque trait " +
                        "devient un semis de points et le rendu s'eclaircit."
                },
                style = MaterialTheme.typography.bodySmall
            )

            if (dither == DitherMode.THRESHOLD) {
                Text("Epaisseur du trait: $threshold")
                // Plus le seuil est haut, plus de pixels passent en noir.
                Slider(
                    value = threshold.toFloat(),
                    onValueChange = { threshold = it.toInt() },
                    valueRange = 80f..220f,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        Text("Apercu", style = MaterialTheme.typography.titleMedium)
        Card(Modifier.fillMaxWidth()) {
            when (mode) {
                ReceiptPrintMode.NATIVE_TEXT -> {
                    // L'apercu partage la mise en page de l'impression: ce qui
                    // s'affiche est ce qui sort du papier.
                    Text(
                        ReceiptDocument.preview(receipt, columns),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        modifier = Modifier.padding(12.dp)
                    )
                }

                ReceiptPrintMode.RASTER_IMAGE -> {
                    val preview = remember(receipt, options.width, dither, threshold) {
                        ReceiptRenderer(
                            width = options.width.pixels,
                            threshold = threshold,
                            ditherMode = dither
                        ).previewImage(receipt)
                    }
                    Image(
                        bitmap = preview.asImageBitmap(),
                        contentDescription = "Apercu du ticket",
                        contentScale = ContentScale.FillWidth,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp)
                    )
                }
            }
        }

        Button(
            onClick = {
                when (mode) {
                    ReceiptPrintMode.NATIVE_TEXT ->
                        printer.print(ReceiptDocument.build(receipt, columns))

                    ReceiptPrintMode.RASTER_IMAGE -> {
                        runCatching {
                            ReceiptRenderer(
                                width = options.width.pixels,
                                threshold = threshold,
                                ditherMode = dither
                            ).render(receipt)
                        }.onSuccess {
                            printer.print(PrintDocument(listOf(PrintElement.Image(it))))
                        }
                    }
                }
            },
            enabled = isConnected,
            modifier = Modifier.fillMaxWidth()
        ) { Text("Imprimer le ticket") }
    }
}
