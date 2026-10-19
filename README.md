# Music 🎶

**Music** est un lecteur de musique pour **iPhone et Android**, en français : bibliothèque, lecteur complet, égaliseur, paroles, playlists et mix automatiques. Un seul dépôt sert les deux plateformes.

## ✨ Fonctionnalités

### 📚 Bibliothèque et playlists
- Bibliothèque musicale, albums et artistes
- Playlists, file d'attente et favoris
- **Sélection multiple** : bouton « Sélectionner » ou appui long, puis « Tout sélectionner »
- Actions groupées : exporter vers Fichiers ou un dossier, partager, ajouter à une playlist, à la file ou aux favoris, supprimer

### 🧭 Découvrir
- Mix automatiques : favoris, en boucle, nouveautés, à redécouvrir, jamais écoutés, express, grand format
- Radios sans fin autour d'un titre, artiste du jour, album à réécouter
- Parcours par décennies et par genres
- **Statistiques d'écoute** : minutes de la semaine, nombre d'écoutes, jours d'affilée, artiste et titre n°1

### 🎧 Lecteur
- Double-toucher la pochette pour ajouter aux favoris
- **Vitesse et tonalité** réglables (de −6 à +6 demi-tons, idéal pour chanter)
- **Boucle A–B** pour répéter un passage
- Radio du morceau en cours et fiche d'informations (format, qualité, nombre d'écoutes…)
- Minuteur « fin du morceau » avec baisse douce du son avant la pause
- Fondu doux à la pause et à la reprise
- Égaliseur et paroles

### ⚙️ Réglages
- Nom de l'application modifiable
- Icône personnalisée sur l'écran d'accueil
- Historique des nouveautés et liste des correctifs à chaque mise à jour
- Journal du lecteur pour diagnostiquer un problème (iPhone)

## 📲 Installation

Music n'est pas sur l'App Store ni sur le Play Store : on l'installe soi-même avec un fichier d'installation, à télécharger dans les [**Releases**](https://github.com/Faxelh/Music/releases) du dépôt.

### 🤖 Android

1. Sur votre téléphone, ouvrez la page [**Releases**](https://github.com/Faxelh/Music/releases) et téléchargez le fichier **`.apk`** de la dernière version.
2. Ouvrez le fichier téléchargé (depuis la notification ou l'app *Fichiers*).
3. Si Android demande une autorisation, activez **« Autoriser depuis cette source »** pour votre navigateur ou votre gestionnaire de fichiers, puis revenez en arrière.
4. Touchez **Installer**. Si Play Protect affiche un avertissement, choisissez **« Installer quand même »**.
5. Ouvrez **Music** : c'est prêt.

L'application est compatible téléphones et tablettes.

### 🍎 iPhone

Il faut un ordinateur (Windows ou Mac) pour la première installation, avec **Sideloadly**.

1. Téléchargez le fichier **`.ipa`** de la dernière version dans les [**Releases**](https://github.com/Faxelh/Music/releases).
2. Installez [**Sideloadly**](https://sideloadly.io/) sur votre ordinateur.
   *Sous Windows, installez aussi iTunes et iCloud depuis le site d'Apple (pas depuis le Microsoft Store).*
3. Branchez votre iPhone avec un câble et touchez **Se fier** sur l'iPhone si la question s'affiche.
4. Ouvrez Sideloadly, glissez le fichier `.ipa` dans la fenêtre et saisissez votre identifiant Apple.
5. Cliquez sur **Start** et attendez la fin de l'installation.
6. Sur l'iPhone, allez dans **Réglages › Général › VPN et gestion de l'appareil**, touchez votre identifiant Apple puis **Faire confiance**.
7. Sur iOS 16 ou plus récent, activez aussi **Réglages › Confidentialité et sécurité › Mode développeur**, puis redémarrez l'iPhone.
8. Ouvrez **Music**.

> ⚠️ Avec un identifiant Apple gratuit, l'app expire au bout de **7 jours** : il faut la réinstaller avec Sideloadly. Pour éviter cela, utilisez **SideStore** ou **AltStore**, qui renouvellent l'app automatiquement.

### ✅ Vérifier que ça marche

Allez dans **Réglages** de l'application : le numéro de version s'affiche (par exemple `2026.10.3`).

## 🔄 Mises à jour

Après la première installation, l'application vérifie elle-même les nouvelles versions et vous propose de mettre à jour :

- **Android** : l'APK se télécharge et s'installe depuis l'application.
- **iPhone** : mise à jour via SideStore / AltStore, ou en réinstallant le nouvel IPA avec Sideloadly.

## 🔢 Versions

Numérotation automatique **Année.Mois.N** : `2026.10.3` correspond à la 3e mise à jour d'octobre 2026.
Le détail de chaque version est dans [`HISTORIQUE.json`](HISTORIQUE.json).

## 📁 Structure du dépôt

```
├── android/            Application Android
├── ios/                Application iPhone
├── assets/             Ressources
├── .github/workflows/  Compilation automatique
├── HISTORIQUE.json     Historique des nouveautés
└── VERSION             Numéro de version
```

## 👤 Auteur
Créé par **Faxel Kwadio** — [@Faxelh](https://github.com/Faxelh)
Développeur autodidacte, je crée des applications utiles pour mon quotidien et celui des autres.

## 🚀 Mes projets
| Projet | Description |
|---|---|
| [**Elara**](https://github.com/Faxelh/elara) | Application iPhone : lecteur vidéo/audio, dossier privé, compression, transfert Wi‑Fi |
| [**Faxel**](https://github.com/Faxelh/Faxel) | Application iPhone et Android : navigateur avec téléchargement intégré, lecteur vidéo/audio, bibliothèque |

## 🛠️ Technologies
![Swift](https://img.shields.io/badge/Swift-FA7343?style=flat&logo=swift&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Django](https://img.shields.io/badge/Django-092E20?style=flat&logo=django&logoColor=white)
![Git](https://img.shields.io/badge/Git-F05032?style=flat&logo=git&logoColor=white)
![VS Code](https://img.shields.io/badge/VS_Code-007ACC?style=flat&logo=visualstudiocode&logoColor=white)
