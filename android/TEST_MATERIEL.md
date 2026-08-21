# Procédure de test sur imprimante réelle — Android

La librairie a été **vérifiée sur matériel** : impression réelle depuis un
Pixel 7a sous Android 17 sur l'imprimante de référence. Le tableau ci-dessous
donne les résultats obtenus ; la procédure qui suit reste valable pour
qui teste un autre téléphone ou un autre modèle d'imprimante.

Règle du dépôt : ce qui n'est pas sorti sur papier n'est pas vérifié. Un test
qui échoue est une information, pas un échec — notez-le.

Comptez 20 à 30 minutes.

---

## Résultats obtenus

| | |
|---|---|
| Téléphone | Pixel 7a |
| Système | Android 17 (API 37) |
| Imprimante | Mini Pocket Printer, modèle `A2Y`, firmware `V1.06LY` |
| Profil BLE | `FF00 UART` |
| MTU négocié | 240 — paquets de 180 octets |

| Test | Résultat |
|---|---|
| 1 — Permissions et scan | Réussi. `Mini Pocket Printer_BLE` détecté |
| 2 — Connexion et profil | Réussi. `FF00 UART`, MTU 240 |
| 3 — Lecture des informations | Réussi. `A2Y`, `V1.06LY`, batterie correcte |
| 4 — Première impression | Réussi |
| 5 — Débit | Réussi. Aucun blocage sur les écritures GATT |
| 6 — Codes rasterisés | Réussi. QR et code-barres scannés |
| 7 — Accents et ticket | Réussi. Translittération conforme |
| 8 — Reconnexion | Réussi |

### Ce que ces tests ont corrigé

Trois défauts, invisibles à la compilation, que seule l'impression a révélés.

- **Commandes envoyées nues.** L'avance papier, les lectures et les réglages
  partaient sans la séquence d'activation. Le firmware les acquittait puis les
  ignorait : les champs Modèle et Firmware restaient vides, et le bouton de
  dégagement papier n'avait aucun effet. La spécification le dit en section
  3.1 — encore fallait-il le constater.
- **Trame `AA 0D 0A`.** Émise spontanément en fin d'échange, elle était prise
  pour une réponse. Elle consommait le contexte en attente, décalait toutes
  les réponses suivantes, et son octet `0D` s'affichait comme « batterie
  13 % ».
- **Tramage par défaut.** Le rendu d'image utilisait Floyd-Steinberg. Sur du
  texte, la diffusion d'erreur transforme chaque trait plein en semis de
  points : le ticket sortait fin et pâle.

### Comportements de plateforme, non corrigeables

- **La déconnexion prend environ 4 secondes.** Android n'interrompt pas la
  liaison radio à l'appel de `disconnect()` : la pile laisse expirer un
  temporisateur L2CAP avant de fermer la connexion ACL
  (`l2c_link_timeout`, mesuré sur Pixel 7a). La LED de l'imprimante reste
  donc allumée un moment après l'appui. iOS ferme plus rapidement. Appeler
  `close()` sans attendre accélère la coupure, sans la rendre immédiate.

---

## Avant de commencer

**Matériel**

- Le téléphone Android, câble USB
- L'imprimante, chargée, avec du papier
- Ce Mac

**Sur le téléphone** — deux réglages à faire une fois :

- Bluetooth activé
- Débogage USB : *Paramètres → À propos → appuyer 7 fois sur « Numéro de
  build »*, puis *Options pour développeurs → Débogage USB*

**Sur le Mac**

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
adb devices
```

Le téléphone doit apparaître avec la mention `device`. S'il affiche
`unauthorized`, acceptez l'invite qui s'affiche sur le téléphone.

---

## Installation

```bash
cd android
./gradlew :demo:installDebug
```

L'app « Pocket Printer 5890 » apparaît dans le lanceur.

**Ouvrez une seconde fenêtre de terminal** et laissez-y tourner :

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
adb logcat -c && adb logcat -s PocketPrinter5890
```

Chaque trame échangée s'y affiche. C'est là que vous verrez ce qui se passe
réellement — l'onglet Console de l'app affiche la même chose.

---

## Test 1 — Permissions et scan

1. Lancez l'app. Une demande de permissions Bluetooth apparaît : **acceptez**.
2. Onglet **Connexion** → *Rechercher*.

| Attendu | L'imprimante apparaît dans la liste (nom type `Mini Pocket Printer_BLE`) |
|---|---|

**Si la liste reste vide :**

- Permissions refusées ? Le scan ne remonte rien **sans signaler d'erreur**.
  *Paramètres → Applications → Pocket Printer 5890 → Autorisations*.
- L'imprimante est peut-être déjà connectée à l'app officielle ou à un autre
  appareil : coupez-la et rallumez-la.
- Le filtre par nom est peut-être trop strict. Test 1b ci-dessous.

**Test 1b — si le nom n'est pas reconnu**

Le filtre cherche `printer`, `pocket`, `mini`, `pt-`, `mpt`, `bt` dans le nom.
Un modèle nommé autrement serait masqué.

Basculez l'interrupteur **« Filtrer sur les noms d'imprimante »**, sous le titre
« Appareils detectes », puis relancez la recherche. Tous les appareils BLE des
environs apparaissent alors. Si l'imprimante s'y trouve, **notez son nom
exact** : c'est une valeur à ajouter au filtre.

---

## Test 2 — Connexion et profil BLE

Appuyez sur *Connecter* en face de l'imprimante.

| Attendu | L'en-tête affiche `Connecte (FF00 UART)` |
|---|---|

Dans logcat, vous devez voir une ligne `INFO MTU ... paquets de N octets`.

**Notez la valeur de N.** Elle vaut 240 sur Pixel 7a, soit des paquets de
180 octets. Si N vaut 20, la négociation du MTU a échoué et l'impression sera
très lente sans être cassée pour autant.

**Si l'app affiche `Aucun profil compatible` :** logcat contient une ligne
`Services vus: ...`. Copiez-la, elle dit exactement ce que la machine expose.

---

## Test 3 — Lecture des informations

Appuyez sur *Lire infos*.

| Champ | Attendu sur la machine de référence |
|---|---|
| Modèle | `A2Y` |
| Firmware | `V1.06LY` |
| Batterie | un pourcentage plausible (pas `1 %`) |
| État | `pret` ou un état non bloquant |

**Le piège à surveiller ici :** si la batterie affiche **1 %**, une trame de
crédit `01 01` a été prise pour la réponse. C'est le bug historique du projet.
Le code s'en protège, mais c'est exactement ce que ce test vérifie.

Dans logcat, vous verrez passer des lignes `RX Credit ... Credit de flux`.
Elles sont normales et attendues.

---

## Test 4 — Première impression (le vrai test)

Onglet **Outils** → *Imprimer le texte*, avec le texte par défaut.

| Attendu | Une ligne imprimée, entièrement sortie du boîtier |
|---|---|

Ce test valide d'un coup les trois pièges du protocole.

**Diagnostic si ça ne sort pas :**

| Symptôme | Cause probable |
|---|---|
| Rien ne sort, aucune erreur | Séquence d'activation non reçue — vérifiez dans logcat que `TX Activation moteur` puis `TX Reveil` apparaissent |
| Le moteur tourne, page blanche | Papier à l'envers : le thermique n'imprime que d'un côté |
| La fin du texte reste sous le capot | Dégagement insuffisant — augmentez `trailingFeedDots` |
| L'impression avance millimètre par millimètre | Crédits de flux ignorés — vérifiez `RX Credit` dans logcat |

---

## Test 5 — Débit (spécifique Android)

Onglet **Outils** → *Mire typographique*. **Chronométrez.**

| Attendu | Quelques secondes, avance continue et régulière |
|---|---|

C'est le test le plus important pour Android, car il éprouve la sérialisation
des écritures GATT, qui n'existe pas sous cette forme sur iOS.

Aucun blocage constaté sur Pixel 7a.

**Si l'impression est saccadée ou s'arrête en cours**, refaites-la avec les
crédits désactivés (onglet Réglages → *Contrôle de flux par crédits*). Si cela
change le comportement, le problème vient de l'articulation entre les crédits
et le rappel d'écriture Android : c'est corrigible, ouvrez une issue avec le
journal.

---

## Test 6 — Codes rasterisés

Onglet **Outils**, contenu par défaut `https://exemple.fr` :

1. *QR code* → **scannez-le avec le téléphone**
2. *Code-barres* → scannez-le

| Attendu | Les deux scannent et renvoient le contenu exact |
|---|---|

Un code qui *paraît* correct mais ne scanne pas est déjà arrivé sur ce projet.
Le scan est le seul juge.

---

## Test 7 — Accents et ticket

Onglet **Ticket** → *Imprimer le ticket*.

| Attendu | Colonnes alignées, total à droite, aucun carré plein |
|---|---|

Les accents doivent apparaître translittérés (`Cafe`, `deg`), jamais en carrés.
Un carré signifie que la translittération a été contournée.

---

## Test 8 — Reconnexion

Le piège classique des crédits hérités d'une session précédente.

1. Éteignez l'imprimante pendant que l'app est connectée
2. L'app doit repasser à `Deconnecte`
3. Rallumez, reconnectez, réimprimez

| Attendu | La deuxième impression est aussi rapide que la première |
|---|---|

Si la seconde impression se bloque, des crédits ont survécu à la déconnexion.

---

## Que rapporter

Les retours depuis d'autres téléphones ou d'autres modèles d'imprimante sont
bienvenus — ouvrez une issue. Peu importe la forme, mais ces points sont
utiles :

1. Modèle du téléphone et version d'Android
2. La valeur du MTU (test 2)
3. Quels tests passent, lesquels échouent
4. Pour un échec : les lignes de logcat autour du problème
5. Si possible, une photo du ticket

Vous pouvez capturer le journal complet dans un fichier :

```bash
adb logcat -d -s PocketPrinter5890 > test-imprimante.txt
```

---

## Ce qui n'est pas testé ici, volontairement

- **Mise à jour du firmware** : non implémentée, et elle ne le sera pas. Une
  implémentation non testée qui échoue en cours d'écriture rend l'imprimante
  inutilisable.
- **Réinitialisation d'usine** : la commande existe (`10 FF 04`) mais n'est
  câblée dans aucun bouton. Destructive si le firmware la supporte.
- **Les commandes transcrites du SDK jamais exécutées** : vitesse, chauffe,
  horloge, mode. Elles viennent d'un SDK couvrant plus de 150 modèles, et rien
  ne garantit que l'A2Y les implémente. Le bouton *Extinction auto* de l'onglet
  Réglages en fait partie : sans danger, mais son effet réel est inconnu.
