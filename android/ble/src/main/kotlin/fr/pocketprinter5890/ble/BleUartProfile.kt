package fr.pocketprinter5890.ble

import java.util.UUID

/**
 * Profil GATT: un service, une caracteristique d'ecriture, une ou deux de
 * notification.
 */
data class BleUartProfile(
    val id: String,
    val service: UUID,
    /** Caracteristique de notification principale (reponses sollicitees). */
    val notify: UUID,
    /** Caracteristique d'ecriture. */
    val write: UUID,
    /** Notification secondaire: statut et controle de flux. */
    val extraNotify: UUID? = null
)

/** Raccourci pour les UUID 16 bits du Bluetooth SIG. */
private fun shortUuid(value: String): UUID =
    UUID.fromString("0000$value-0000-1000-8000-00805F9B34FB")

/**
 * Profils BLE observes sur cette famille d'imprimantes.
 *
 * L'imprimante annonce quatre services; **seul FF00 repond**. Les autres
 * acceptent les ecritures et ne notifient jamais: une implementation qui
 * choisit le mauvais service semble fonctionner et n'imprime rien.
 */
object PrinterBleProfiles {

    const val AUTOMATIC_ID: String = "Automatique"

    /**
     * Le seul profil qui repond sur cette machine.
     *
     * FF01 porte les reponses sollicitees, FF03 le statut et les credits de
     * flux: il faut s'abonner aux deux.
     */
    val ff00: BleUartProfile = BleUartProfile(
        id = "FF00 UART",
        service = shortUuid("FF00"),
        notify = shortUuid("FF01"),
        write = shortUuid("FF02"),
        extraNotify = shortUuid("FF03")
    )

    /** Microchip Transparent UART. Accepte les ecritures, ne notifie jamais. */
    val transparentUart: BleUartProfile = BleUartProfile(
        id = "Microchip Transparent UART",
        service = UUID.fromString("49535343-fe7d-4ae5-8fa9-9fafd205e455"),
        notify = UUID.fromString("49535343-1e4d-4bd9-ba61-23c647249616"),
        write = UUID.fromString("49535343-8841-43f4-a8d4-ecbe34729bb3"),
        extraNotify = UUID.fromString("49535343-aca3-481c-91ec-d85e28a60318")
    )

    val service18F0: BleUartProfile = BleUartProfile(
        id = "18F0 UART",
        service = shortUuid("18F0"),
        notify = shortUuid("2AF0"),
        write = shortUuid("2AF1")
    )

    val combinedE781: BleUartProfile = BleUartProfile(
        id = "E781 Combined UART",
        service = UUID.fromString("e7810a71-73ae-499d-8c15-faa9aef0c3f2"),
        notify = UUID.fromString("bef8d6c9-9c21-4c9e-b632-bd58c1009f9f"),
        write = UUID.fromString("bef8d6c9-9c21-4c9e-b632-bd58c1009f9f")
    )

    val preferred: List<BleUartProfile> =
        listOf(transparentUart, ff00, service18F0, combinedE781)

    /** Ordre reel d'essai: FF00 d'abord, seul profil observe repondant. */
    val observedResponsive: List<BleUartProfile> =
        listOf(ff00, transparentUart, service18F0, combinedE781)

    val allServiceUuids: List<UUID> = preferred.map { it.service }

    fun profile(service: UUID): BleUartProfile? =
        preferred.firstOrNull { it.service == service }

    /** Place le profil choisi en tete, sans retirer les autres. */
    fun orderedProfiles(preferredProfileId: String): List<BleUartProfile> {
        val selected = preferred.firstOrNull { it.id == preferredProfileId }
        if (preferredProfileId == AUTOMATIC_ID || selected == null) {
            return observedResponsive
        }
        return listOf(selected) + preferred.filter { it.id != selected.id }
    }

    /** Descripteur standard d'activation des notifications. */
    val clientCharacteristicConfig: UUID = shortUuid("2902")
}

/** Decoupe un tableau d'octets en paquets BLE. */
object BlePacketizer {
    fun chunks(bytes: ByteArray, maxWriteLength: Int): List<ByteArray> {
        require(maxWriteLength > 0) { "maxWriteLength doit etre positif" }
        val result = mutableListOf<ByteArray>()
        var index = 0
        while (index < bytes.size) {
            val end = minOf(index + maxWriteLength, bytes.size)
            result.add(bytes.copyOfRange(index, end))
            index = end
        }
        return result
    }
}
