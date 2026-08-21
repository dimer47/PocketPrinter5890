package fr.pocketprinter5890.demo

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import fr.pocketprinter5890.ble.PocketPrinterBleTransport
import fr.pocketprinter5890.kit.PrintOptions

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Le scan BLE exige des permissions accordees a l'execution: sans
        // elles, le scan ne remonte simplement aucun appareil, sans erreur.
        val launcher = registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { }
        launcher.launch(requiredPermissions())

        setContent {
            MaterialTheme {
                RootScreen()
            }
        }
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            // Avant Android 12, le scan BLE passait par la localisation.
            // FINE et COARSE doivent etre demandees ensemble.
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        }
}

private enum class Tab(val title: String, val icon: ImageVector) {
    CONNECTION("Connexion", Icons.Filled.Bluetooth),
    RECEIPT("Ticket", Icons.Filled.Description),
    TOOLS("Outils", Icons.Filled.Print),
    SETTINGS("Reglages", Icons.Filled.Settings),
    CONSOLE("Console", Icons.Filled.Terminal)
}

/**
 * Navigation par onglets, comme la demo iOS: les volets de la version macOS
 * ne tiennent pas cote a cote sur telephone.
 */
@Composable
private fun RootScreen() {
    val context = LocalContext.current
    // Le transport survit aux recompositions: le recreer couperait la
    // connexion a chaque changement d'onglet.
    val transport = remember { PocketPrinterBleTransport(context) }
    var options by remember { mutableStateOf(PrintOptions()) }
    var selected by remember { mutableStateOf(Tab.CONNECTION) }

    Scaffold(
        bottomBar = {
            NavigationBar {
                for (tab in Tab.entries) {
                    NavigationBarItem(
                        selected = selected == tab,
                        onClick = { selected = tab },
                        icon = { Icon(tab.icon, contentDescription = tab.title) },
                        label = { Text(tab.title) }
                    )
                }
            }
        }
    ) { padding ->
        val modifier = Modifier.padding(padding)
        when (selected) {
            Tab.CONNECTION -> ConnectionScreen(transport, modifier)
            Tab.RECEIPT -> ReceiptScreen(transport, options, modifier)
            Tab.TOOLS -> PrintToolsScreen(transport, options, modifier)
            Tab.SETTINGS -> SettingsScreen(transport, options, { options = it }, modifier)
            Tab.CONSOLE -> ConsoleScreen(transport, modifier)
        }
    }
}
