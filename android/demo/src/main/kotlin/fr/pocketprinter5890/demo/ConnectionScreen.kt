package fr.pocketprinter5890.demo

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import fr.pocketprinter5890.ble.PocketPrinterBleTransport

@Composable
fun ConnectionScreen(
    transport: PocketPrinterBleTransport,
    modifier: Modifier = Modifier
) {
    val devices by transport.devices.collectAsStateWithLifecycle()
    val isScanning by transport.isScanning.collectAsStateWithLifecycle()
    val isConnected by transport.isConnected.collectAsStateWithLifecycle()
    val stateText by transport.stateText.collectAsStateWithLifecycle()
    val battery by transport.batteryPercent.collectAsStateWithLifecycle()
    val model by transport.deviceModel.collectAsStateWithLifecycle()
    val firmware by transport.deviceFirmware.collectAsStateWithLifecycle()
    val status by transport.printerStatus.collectAsStateWithLifecycle()
    val progress by transport.sendProgress.collectAsStateWithLifecycle()
    var onlyPrinters by remember { mutableStateOf(transport.showOnlyLikelyPrinters) }
    val isBusy by transport.isBusy.collectAsStateWithLifecycle()
    val connectingAddress by transport.connectingAddress.collectAsStateWithLifecycle()

    Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stateText, style = MaterialTheme.typography.titleMedium)

        if (progress < 1.0) {
            LinearProgressIndicator(
                progress = { progress.toFloat() },
                modifier = Modifier.fillMaxWidth()
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!isConnected) {
                Button(
                    onClick = {
                        if (isScanning) transport.stopScan() else transport.startScan()
                    },
                    // Pas de nouveau scan pendant qu'une connexion s'etablit.
                    enabled = !isBusy
                ) {
                    Text(if (isScanning) "Arreter" else "Rechercher")
                }
            }
            if (isConnected) {
                OutlinedButton(
                    onClick = { transport.disconnect() },
                    enabled = !isBusy
                ) {
                    Text(if (isBusy) "Deconnexion…" else "Deconnecter")
                }
                OutlinedButton(
                    onClick = { transport.requestDeviceInformation() },
                    enabled = !isBusy
                ) { Text("Lire infos") }
            }
        }

        if (isConnected) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    InfoRow("Modele", model ?: "-")
                    InfoRow("Firmware", firmware ?: "-")
                    InfoRow("Batterie", battery?.let { "$it %" } ?: "-")
                    InfoRow("Etat", status?.description ?: "-")
                }
            }
        }

        // Liste d'appareils masquee tant qu'une imprimante est connectee:
        // proposer « Connecter » sur la machine deja connectee n'a pas de sens.
        if (!isConnected) {
            HorizontalDivider()
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Appareils detectes", style = MaterialTheme.typography.titleSmall)
                    // Le filtre masque tout appareil dont le nom ne ressemble
                    // pas a une imprimante: le desactiver permet de retrouver
                    // un modele nomme autrement.
                    Text(
                        "Filtrer sur les noms d'imprimante",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Switch(
                    checked = onlyPrinters,
                    onCheckedChange = {
                        onlyPrinters = it
                        transport.showOnlyLikelyPrinters = it
                    }
                )
            }

            LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                items(devices, key = { it.address }) { device ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(device.name ?: "Sans nom")
                            Text(
                                "${device.address} — ${device.rssi} dBm",
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                        val isTarget = connectingAddress == device.address
                        Button(
                            onClick = { transport.connect(device.address) },
                            // Desactive des le premier appui: sans cela, deux
                            // appuis rapproches ouvraient deux clients GATT.
                            enabled = !isBusy
                        ) {
                            if (isTarget) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp
                                )
                            } else {
                                Text("Connecter")
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
