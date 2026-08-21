# PocketPrinter5890 — Android

Librairie Kotlin pour les imprimantes thermiques de poche vendues par Lidl
sous les marques Tronic, SILVERCREST et Parkside, de la famille générique 5890.

Même protocole, même forme d'API et mêmes noms de méthodes que la librairie
Swift de [`../swift`](../swift). Ce que vous faites sur iOS s'écrit ici de la
même façon.

[English version](README.md) · [Spécification du protocole](../docs/PROTOCOLE.md)

## Modules

| Module | Contenu |
|---|---|
| `kit` | Protocole, encodage raster, ESC/POS, documents, codes-barres, QR. JVM pur — sans SDK Android, donc les tests tournent sur votre machine sans émulateur. |
| `ble` | Transport BLE prêt à l'emploi, contrôle de flux par crédits inclus. |
| `demo` | Application Compose : connexion, ticket, outils, réglages, console. |

## Prérequis

- Android 7.0 (API 24) ou plus récent
- JDK 17 ou plus récent pour compiler

## Démarrage rapide

```kotlin
val transport = PocketPrinterBleTransport(context)
transport.startScan()
// …une fois l'appareil choisi :
transport.connect(device.address)

val printer = PocketPrinter(transport)
printer.setDensity(PrintDensity.STRONG)

val document = PrintDocument()
document.append(PrintElement.title("BOULANGERIE"))
document.append(PrintElement.Separator())
document.append(PrintElement.Text("Baguette          1,20 EUR"))
document.append(PrintElement.Image(CodeBitmaps.qrCode("https://exemple.fr")))
document.append(PrintElement.Feed(2))
printer.print(document)
```

`PocketPrinter` dialogue avec un `PrinterTransport`. `PocketPrinterBleTransport`
l'implémente, mais rien n'empêche d'en écrire un autre — USB, fichier, ou
double de test.

## Permissions

Le module `ble` déclare ce dont il a besoin, mais Android 12 et plus exigent
que l'utilisateur les accorde à l'exécution. Demandez `BLUETOOTH_SCAN` et
`BLUETOOTH_CONNECT` avant de scanner ; sur Android 11 et antérieur, demandez
`ACCESS_FINE_LOCATION` et `ACCESS_COARSE_LOCATION` ensemble. Sans elles, le
scan ne remonte aucun appareil et ne signale aucune erreur — voir
`MainActivity` dans la démo.

## Les trois pièges qui bloquent une implémentation naïve

Les trois sont documentés dans la spécification, et les trois sont déjà traités
ici.

1. **Contrôle de flux par crédits.** Les trames `01 nn` sur `FF03` ne sont pas
   des acquittements : elles annoncent que l'imprimante peut accepter `nn`
   paquets de plus. Temporiser à intervalle fixe à la place divise le débit par
   environ vingt.
2. **La séquence d'activation.** Sans `10 FF F1 03` suivi de douze octets nuls
   en écriture **distincte**, l'imprimante acquitte tout et n'exécute rien.
3. **Le raster en bandes.** Un raster envoyé en une seule commande est perdu.
   Il faut le découper en bandes d'environ 24 lignes.

## Ce que le firmware ne sait pas faire

Constaté sur papier, pas déduit du code : les commandes natives de QR et de
codes-barres s'impriment en clair, les caractères accentués sortent en carrés
pleins, et la sélection de page de code `ESC t` est ignorée. La librairie
contourne les trois — les codes sont rasterisés, le texte est translittéré en
ASCII.

## Compilation

```bash
./gradlew build          # tout, lint compris
./gradlew :kit:test      # tests du protocole, sans matériel
./gradlew :demo:assembleDebug
```

## État

La couche protocole est couverte par les tests portés depuis la suite Swift, et
ils passent.

**Vérifié sur matériel** : connexion, lecture des informations, texte natif,
codes rasterisés et tickets s'impriment depuis un Pixel 7a (Android 17) sur
l'imprimante de référence. [`TEST_MATERIEL.md`](TEST_MATERIEL.md) donne les
résultats complets et la procédure pas à pas — les retours depuis d'autres
téléphones ou d'autres modèles d'imprimante sont bienvenus.

Un comportement de plateforme à connaître : la déconnexion prend environ
quatre secondes. Android ne coupe pas la liaison radio à l'appel de
`disconnect()` ; sa pile attend l'expiration d'un temporisateur L2CAP, et la
LED de l'imprimante reste allumée un moment. iOS ferme plus rapidement.

Les commandes transcrites du SDK constructeur mais jamais exécutées sont
signalées comme telles dans le code, exactement comme dans la librairie Swift.
