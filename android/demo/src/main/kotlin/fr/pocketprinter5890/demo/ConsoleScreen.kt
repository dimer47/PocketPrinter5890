package fr.pocketprinter5890.demo

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import fr.pocketprinter5890.ble.LogDirection
import fr.pocketprinter5890.ble.PocketPrinterBleTransport

/**
 * Journal hexadecimal des echanges.
 *
 * Indispensable au diagnostic: c'est la qu'on voit les trames `01 nn`
 * arriver et qu'on distingue un credit de flux d'une vraie reponse.
 */
@Composable
fun ConsoleScreen(
    transport: PocketPrinterBleTransport,
    modifier: Modifier = Modifier
) {
    val log by transport.log.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()

    // Suit le bas du journal a mesure que les trames arrivent.
    LaunchedEffect(log.size) {
        if (log.isNotEmpty()) listState.animateScrollToItem(log.size - 1)
    }

    Column(modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("${log.size} entrees", style = MaterialTheme.typography.titleSmall)
            OutlinedButton(onClick = { transport.clearLog() }) { Text("Effacer") }
        }

        LazyColumn(state = listState, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            itemsIndexed(log) { _, entry ->
                val color = when (entry.direction) {
                    LogDirection.TX -> Color(0xFF1565C0)
                    LogDirection.RX -> Color(0xFF2E7D32)
                    LogDirection.INFO -> Color.Gray
                }
                Column(Modifier.fillMaxWidth()) {
                    Text(
                        "${entry.direction} ${entry.label}",
                        color = color,
                        fontSize = 12.sp
                    )
                    if (entry.hex.isNotEmpty()) {
                        Text(entry.hex, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
                    }
                    if (entry.decoded.isNotEmpty()) {
                        Text(
                            entry.decoded,
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}
