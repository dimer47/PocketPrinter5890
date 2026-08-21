package fr.pocketprinter5890.kit

import java.util.Date

/**
 * Transport capable d'envoyer des octets a l'imprimante.
 *
 * L'interface isole la librairie du moyen de communication: BLE aujourd'hui,
 * USB ou Bluetooth Classic plus tard, sans rien changer au reste du code.
 */
interface PrinterTransport {
    fun send(bytes: ByteArray, label: String)
}

/**
 * Facade equivalente a l'objet `Printer` du LuckPrinter SDK.
 *
 * Elle rassemble le cycle d'impression et les reglages en une API unique,
 * pour eviter d'avoir a assembler les commandes a la main.
 *
 * ```kotlin
 * val printer = PocketPrinter(bleTransport)
 * printer.readDeviceInformation()
 * printer.setDensity(PrintDensity.STRONG)
 *
 * val document = PrintDocument()
 * document.append(PrintElement.title("BOULANGERIE"))
 * document.append(PrintElement.Image(CodeBitmaps.qrCode("https://exemple.fr")))
 * printer.print(document)
 * ```
 */
class PocketPrinter(
    var transport: PrinterTransport?,
    /** Options appliquees par defaut a chaque impression. */
    var options: PrintOptions = PrintOptions()
) {

    // MARK: - Impression

    /** Imprime un document compose. */
    fun print(document: PrintDocument, options: PrintOptions? = null) {
        send(PrintJobBuilder.segments(document, options ?: this.options))
    }

    /** Imprime un bitmap deja converti. */
    fun print(bitmap: MonochromeBitmap, options: PrintOptions? = null) {
        send(PrintJobBuilder.segments(bitmap, options ?: this.options))
    }

    /** Imprime une ou plusieurs lignes de texte. */
    fun print(
        text: String,
        size: Int = 1,
        bold: Boolean = false,
        alignment: Escpos.Alignment = Escpos.Alignment.LEFT,
        options: PrintOptions? = null
    ) {
        val elements = text.split("\n").map {
            PrintElement.Text(it, size = size, bold = bold, alignment = alignment)
        }
        print(PrintDocument(elements), options)
    }

    /**
     * Avance le papier de n points sans rien imprimer.
     *
     * La commande est encadree par la sequence d'activation: un `1B 4A nn`
     * envoye nu est acquitte par le firmware et **ignore**, exactement comme
     * une impression sans activation (cf. specification, section 3.1).
     */
    fun feed(dots: Int, options: PrintOptions? = null) {
        val effective = options ?: this.options
        print(
            PrintDocument(listOf(PrintElement.Raw(LuckPrinter.feedDots(dots)))),
            // L'avance demandee est la seule attendue: pas de degagement
            // supplementaire, pas d'initialisation ESC/POS.
            effective.copy(trailingFeedDots = 0, sendInitialize = false)
        )
    }

    // MARK: - Reglages

    fun setDensity(density: PrintDensity) {
        options = options.copy(density = density)
        command(LuckPrinter.setDensity(density.value), "Densite ${density.title}")
    }

    /** Vitesse d'impression. Non verifiee sur ce firmware. */
    fun setSpeed(level: Int) {
        command(LuckPrinter.setSpeed(level), "Vitesse $level")
    }

    /** Niveau de chauffe de la tete. Non verifiee sur ce firmware. */
    fun setHeatingLevel(level: Int) {
        command(LuckPrinter.setHeatingLevel(level), "Chauffe $level")
    }

    /** Delai d'extinction automatique, en minutes. */
    fun setAutoShutdown(minutes: Int) {
        command(LuckPrinter.setAutoShutdown(minutes), "Extinction auto $minutes min")
    }

    /** Regle l'horloge interne. Non verifiee sur ce firmware. */
    fun setClock(date: Date = Date()) {
        command(LuckPrinter.setTimeFormat(date), "Horloge")
    }

    /** Retour aux reglages d'usine. Non verifiee sur ce firmware. */
    fun factoryReset() {
        command(LuckPrinter.factoryReset, "Reglages d'usine")
    }

    // MARK: - Informations

    fun readDeviceInformation() {
        command(LuckPrinter.model, "Lire modele")
        command(LuckPrinter.firmware, "Lire firmware")
        command(LuckPrinter.battery, "Lire batterie")
        command(LuckPrinter.status, "Lire papier")
    }

    fun readSerialNumber() {
        command(LuckPrinter.serialNumber, "Lire numero de serie")
    }

    fun readBootloader() {
        command(LuckPrinter.bootloader, "Lire bootloader")
    }

    fun readSettings() {
        command(LuckPrinter.getDensity, "Lire densite")
        command(LuckPrinter.getSpeed, "Lire vitesse")
        command(LuckPrinter.getAutoShutdown, "Lire extinction auto")
    }

    // MARK: - Commande brute

    /**
     * Echappatoire pour une commande non couverte par la librairie.
     *
     * @param wrapInActivation encadre la commande par la sequence
     *   d'activation. Necessaire pour toute commande devant reellement
     *   s'executer: sans elle le firmware acquitte et n'agit pas.
     */
    fun sendRaw(
        bytes: ByteArray,
        label: String = "Commande brute",
        wrapInActivation: Boolean = false
    ) {
        if (!wrapInActivation) {
            transport?.send(bytes, label)
            return
        }
        transport?.send(LuckPrinter.enablePrinter(), "Activation moteur")
        transport?.send(LuckPrinter.wakeup, "Reveil")
        transport?.send(bytes, label)
        transport?.send(LuckPrinter.stopPrintJob, "Fin du travail")
    }

    /**
     * Envoie une commande unique encadree par la sequence d'activation.
     *
     * La specification est explicite (section 3.1): l'activation n'est pas une
     * affaire d'impression. Un `10 FF 20 F0` nu est acquitte et ignore tout
     * autant qu'une avance papier nue, ce qui donne une application capable
     * d'imprimer mais dont les boutons « lire les infos » ne repondent jamais.
     */
    private fun command(bytes: ByteArray, label: String) {
        transport?.send(LuckPrinter.enablePrinter(), "Activation moteur")
        transport?.send(LuckPrinter.wakeup, "Reveil")
        transport?.send(bytes, label)
        transport?.send(LuckPrinter.stopPrintJob, "Fin du travail")
    }

    private fun send(segments: List<PrintSegment>) {
        for (segment in segments) {
            transport?.send(segment.bytes, segment.name)
        }
    }
}
