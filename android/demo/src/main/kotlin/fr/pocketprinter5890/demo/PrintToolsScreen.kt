package fr.pocketprinter5890.demo

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import fr.pocketprinter5890.ble.PocketPrinterBleTransport
import fr.pocketprinter5890.kit.Barcode1D
import fr.pocketprinter5890.kit.CodeBitmaps
import fr.pocketprinter5890.kit.Escpos
import fr.pocketprinter5890.kit.PocketPrinter
import fr.pocketprinter5890.kit.PrintDocument
import fr.pocketprinter5890.kit.PrintElement
import fr.pocketprinter5890.kit.PrintOptions

@Composable
fun PrintToolsScreen(
    transport: PocketPrinterBleTransport,
    options: PrintOptions,
    modifier: Modifier = Modifier
) {
    val isConnected by transport.isConnected.collectAsStateWithLifecycle()
    var freeText by remember { mutableStateOf("Bonjour depuis Android") }
    var textSize by remember { mutableIntStateOf(1) }
    var alignment by remember { mutableStateOf(Escpos.Alignment.LEFT) }
    var codeContent by remember { mutableStateOf("https://exemple.fr") }

    val printer = PocketPrinter(transport, options)

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Texte natif", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(
            value = freeText,
            onValueChange = { freeText = it },
            label = { Text("Texte a imprimer") },
            modifier = Modifier.fillMaxWidth()
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (value in Escpos.Alignment.entries) {
                FilterChip(
                    selected = alignment == value,
                    onClick = { alignment = value },
                    label = { Text(value.title) }
                )
            }
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Taille $textSize")
            OutlinedButton(onClick = { if (textSize > 1) textSize-- }) { Text("-") }
            OutlinedButton(onClick = { if (textSize < 4) textSize++ }) { Text("+") }
        }

        // Pas d'option « gras »: le firmware A2Y accepte `ESC E` sans
        // l'appliquer (constate sur papier ici et sur macOS/iOS). Un
        // interrupteur sans effet ferait croire a une panne.
        Text(
            "Le gras n'est pas supporté par ce firmware en texte natif.",
            style = MaterialTheme.typography.bodySmall
        )

        Button(
            onClick = {
                printer.print(
                    text = freeText,
                    size = textSize,
                    alignment = alignment
                )
            },
            enabled = isConnected && freeText.isNotEmpty(),
            modifier = Modifier.fillMaxWidth()
        ) { Text("Imprimer le texte") }

        HorizontalDivider()
        Text("Codes", style = MaterialTheme.typography.titleMedium)
        // Les commandes natives GS k / GS ( k s'impriment en clair sur ce
        // firmware: les codes sont donc rasterises avant envoi.
        OutlinedTextField(
            value = codeContent,
            onValueChange = { codeContent = it },
            label = { Text("Contenu du code") },
            modifier = Modifier.fillMaxWidth()
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = {
                    runCatching {
                        CodeBitmaps.qrCode(codeContent, printWidth = options.width.pixels)
                    }.onSuccess {
                        printer.print(PrintDocument(listOf(PrintElement.Image(it))))
                    }
                },
                enabled = isConnected && codeContent.isNotEmpty()
            ) { Text("QR code") }

            Button(
                onClick = {
                    // Code 128 accepte tout l'ASCII imprimable, contrairement
                    // aux symbologies numeriques.
                    runCatching {
                        CodeBitmaps.barcode(
                            codeContent,
                            Barcode1D.Symbology.CODE128,
                            printWidth = options.width.pixels
                        )
                    }.onSuccess {
                        printer.print(PrintDocument(listOf(PrintElement.Image(it))))
                    }
                },
                enabled = isConnected && codeContent.isNotEmpty()
            ) { Text("Code-barres") }
        }

        HorizontalDivider()
        Text("Demonstrations", style = MaterialTheme.typography.titleMedium)
        Button(
            onClick = { printer.print(DemoDocuments.typographySampler()) },
            enabled = isConnected,
            modifier = Modifier.fillMaxWidth()
        ) { Text("Mire typographique") }

        Button(
            onClick = { printer.print(DemoDocuments.weatherAndHoroscope()) },
            enabled = isConnected,
            modifier = Modifier.fillMaxWidth()
        ) { Text("Meteo et horoscope") }

        OutlinedButton(
            onClick = { printer.feed(80) },
            enabled = isConnected,
            modifier = Modifier.fillMaxWidth()
        ) { Text("Degager le papier") }
    }
}
