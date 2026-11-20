# Deck

Transforme un vieux téléphone Android en **Stream Deck** pour ton PC Windows, relié par câble USB.

Par MyBlackWhite.

## Ce que ça fait

- Lance tes jeux et tes apps du PC d'un appui sur le téléphone. Si tu rappuies sur une app déjà ouverte, elle se ferme. Si tu as du travail non enregistré, l'app te demande d'abord si tu veux enregistrer.
- Envoie des raccourcis clavier au PC (par exemple `CTRL+SHIFT+M`).
- Range les boutons par catégories. En mode édition (appui long), tu peux les déplacer.
- Ajoute ou retire des apps du PC depuis le téléphone.
- Affiche les performances du PC : CPU, GPU, RAM, mémoire vidéo, réseau, ping, FPS en jeu et températures, avec des courbes.
- Montre les composants du PC : carte graphique, processeur, mémoire, carte mère, disques et réseau.
- Se reconnecte tout seul dès que le PC ou le téléphone s'allume.

Le téléphone devient l'écran d'accueil (launcher) : il n'affiche que le Deck.

## Ce qu'il faut

### Sur le PC (obligatoire)

- **Windows 10 ou 11.** PowerShell est déjà inclus dans Windows.
- **ADB**, les outils Android de Google. Il est installé avec [Android Studio](https://developer.android.com/studio). Le serveur le cherche ici :
  `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`
  Si ton ADB est ailleurs, change le chemin à la ligne `$Adb = ...` au début de `pc/deck-serveur.ps1`.
- **Un câble USB** qui transmet les données, pas seulement la charge.

### Sur le PC (facultatif)

| Programme | À quoi il sert |
|---|---|
| [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) | Températures et détails des composants. Lance-le **en administrateur** et active son serveur web (Options > Remote Web Server) sur le port **8085**. |
| AMD Software Adrenalin | Compteur de FPS en jeu (il utilise le PresentMon d'AMD). Ne marche pour l'instant qu'avec une carte graphique AMD. |
| Google Chrome | Bouton qui affiche et ouvre les profils Chrome. |

Sans ces programmes, le reste du Deck marche quand même.

### Sur le téléphone

- **Android 8 ou plus récent.**
- **Débogage USB** activé. Pour l'activer : Paramètres > À propos du téléphone, puis appuie 7 fois sur « Numéro de build ». Va ensuite dans Options pour les développeurs > Débogage USB.
- Sur un Xiaomi, active aussi **« Installer via USB »** dans les mêmes options.

## Installation

### 1. Compiler et installer l'appli

Avec Android Studio, ouvre le dossier du projet et lance l'appli sur le téléphone branché.

Tu peux aussi passer par la ligne de commande :

```bat
gradlew.bat assembleDebug
adb install -r app\build\outputs\apk\debug\app-debug.apk
```

Appuie ensuite sur le bouton Accueil du téléphone et choisis **Deck** comme écran d'accueil, « Toujours ».

### 2. Lancer le serveur sur le PC

Double-clique sur `pc/Lancer Deck.cmd`. Le serveur démarre en arrière-plan, sans fenêtre.

Au premier lancement, il crée `pc/deck.json` avec les raccourcis de ton Bureau.

### 3. Le lancer au démarrage de Windows (conseillé)

`pc/deck-gardien.ps1` lance le serveur et le relance tout seul s'il s'arrête. Pour qu'il démarre avec Windows :

1. Appuie sur `Win + R`, tape `shell:startup` puis Entrée.
2. Dans ce dossier, crée un raccourci avec cette cible (remplace le chemin par le tien) :

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\chemin\vers\deck\pc\deck-gardien.ps1"
```

## Utilisation

Au premier lancement, l'appli affiche des explications en 4 étapes. Pour les revoir, fais un appui long sur le logo, puis choisis « Revoir les explications ».

### Raccourcis cachés du logo

Le **logo aux 6 carrés**, en haut à gauche de l'écran (au-dessus des catégories), donne accès aux pages cachées :

| Appuis sur le logo | Page qui s'ouvre |
|---|---|
| **1 appui** | **Performances du PC** : CPU, GPU, RAM, mémoire vidéo, réseau, ping, FPS. Appuie sur une case pour voir ses détails et sa courbe. |
| **2 appuis rapides** | **Composants du PC** : carte graphique, processeur, mémoire, carte mère, disques, réseau, système. |
| **3 appuis rapides** | **Ajouter ou retirer des apps** : la liste des apps du PC. Appuie sur une app pour l'ajouter au Deck, rappuie pour la retirer. |
| **1 appui depuis une de ces pages** | Retour aux boutons |

Les apps ne se retirent que depuis la page « Ajouter » (3 appuis).

### Boutons

| Geste | Effet |
|---|---|
| Appui sur un bouton | Lance l'app au moment où tu retires le doigt |
| Rappui sur une app ouverte (pastille verte) | Ferme l'app. Si du travail n'est pas enregistré, l'app te le demande sur le PC. |
| Appui long sur un bouton | Mode édition : glisse les boutons pour les ranger, puis appuie sur « Terminé » |

## Modifier les boutons à la main

Les boutons sont dans `pc/deck.json`. Le téléphone se met à jour tout seul quand tu enregistres le fichier.

```json
{
  "colonnes": 7,
  "boutons": [
    { "id": "b1", "nom": "Discord", "type": "app", "cible": "C:\\Users\\Moi\\Desktop\\Discord.lnk", "groupe": "Apps" },
    { "id": "b2", "nom": "Couper le micro", "type": "touches", "cible": "CTRL+SHIFT+M", "groupe": "Raccourcis" }
  ]
}
```

- `type` `app` : `cible` est un programme, un raccourci (`.lnk`, `.url`) ou une adresse.
- `type` `touches` : `cible` est une combinaison de touches. Touches connues : `CTRL`, `SHIFT`, `ALT`, `WIN`, `ESC`, `TAB`, `ENTREE`, `ESPACE`, `SUPPR`, `RETOUR`, `HAUT`, `BAS`, `GAUCHE`, `DROITE`, `IMPR`, `DEBUT`, `FIN`, `PGHAUT`, `PGBAS`, `F1` à `F12`, les lettres et les chiffres.

## Comment ça marche

Le serveur PowerShell (`pc/deck-serveur.ps1`) écoute sur `localhost:8765`. Il fait `adb reverse tcp:8765 tcp:8765`, ce qui fait arriver sur le PC tout ce que le téléphone envoie à son propre `localhost:8765`, à travers le câble USB. Il n'y a pas de Wi-Fi ni d'internet entre les deux.

## Problèmes fréquents

- **Le téléphone affiche « PC déconnecté ».** Vérifie que le serveur tourne et que `adb devices` montre le téléphone avec l'état `device`. Si le téléphone affiche une fenêtre « Autoriser le débogage USB ? », accepte-la.
- **Pas de températures.** LibreHardwareMonitor doit tourner en administrateur avec le serveur web sur le port 8085.
- **FPS à 0.** Il faut AMD Adrenalin, et un jeu au premier plan.
