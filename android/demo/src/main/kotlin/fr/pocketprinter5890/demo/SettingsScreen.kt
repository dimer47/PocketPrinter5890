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
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import fr.pocketprinter5890.ble.PocketPrinterBleTransport
import fr.pocketprinter5890.kit.PaperMode
import fr.pocketprinter5890.kit.PocketPrinter
import fr.pocketprinter5890.kit.PrintDensity
import fr.pocketprinter5890.kit.PrintOptions
import fr.pocketprinter5890.kit.PrinterWidth

@Composable
fun SettingsScreen(
    transport: PocketPrinterBleTransport,
    options: PrintOptions,
    onOptionsChange: (PrintOptions) -> Unit,
    modifier: Modifier = Modifier
) {
    val isConnected by transport.isConnected.collectAsStateWithLifecycle()
    val printer = PocketPrinter(transport, options)

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Densite", style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (value in PrintDensity.entries) {
                FilterChip(
                    selected = options.density == value,
                    onClick = {
                        onOptionsChange(options.copy(density = value))
                        if (isConnected) printer.setDensity(value)
                    },
                    label = { Text(value.title) }
                )
            }
        }

        HorizontalDivider()
        Text("Largeur", style = MaterialTheme.typography.titleMedium)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (value in PrinterWidth.entries) {
                FilterChip(
                    selected = options.width == value,
                    onClick = { onOptionsChange(options.copy(width = value)) },
                    label = { Text(value.title) }
                )
            }
        }

        HorizontalDivider()
        Text("Mode papier", style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (value in PaperMode.entries) {
                FilterChip(
                    selected = options.paperMode == value,
                    onClick = { onOptionsChange(options.copy(paperMode = value)) },
                    label = { Text(value.title) }
                )
            }
        }

        HorizontalDivider()
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text("Transliterer en ASCII")
                // Sans cela, le firmware imprime un carre plein a la place de
                // chaque accent, quelle que soit la page de code declaree.
                Text(
                    "Le firmware imprime un carre a la place des accents",
                    style = MaterialTheme.typography.bodySmall
                )
            }
            Switch(
                checked = options.transliterateText,
                onCheckedChange = { onOptionsChange(options.copy(transliterateText = it)) }
            )
        }

        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text("Controle de flux par credits")
                Text(
                    "Desactiver divise le debit par environ vingt",
                    style = MaterialTheme.typography.bodySmall
                )
            }
            Switch(
                checked = transport.useCreditFlowControl,
                onCheckedChange = { transport.useCreditFlowControl = it }
            )
        }

        HorizontalDivider()
        Text("Commandes non verifiees", style = MaterialTheme.typography.titleMedium)
        // Ces commandes viennent du SDK, qui couvre plus de 150 modeles: rien
        // ne garantit que l'A2Y les implemente.
        Text(
            "Transcrites du SDK constructeur, jamais confirmees sur ce materiel.",
            style = MaterialTheme.typography.bodySmall
        )
        Button(
            onClick = { printer.setAutoShutdown(30) },
            enabled = isConnected,
            modifier = Modifier.fillMaxWidth()
        ) { Text("Extinction auto: 30 min") }

        Button(
            onClick = { printer.readSettings() },
            enabled = isConnected,
            modifier = Modifier.fillMaxWidth()
        ) { Text("Relire les reglages") }
    }
}
