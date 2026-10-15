# Music

Application iPhone **et** Android, dans un seul dépôt (comme Elara).

- `ios/` : app iPhone (SwiftUI)
- `android/` : app Android (Kotlin, Jetpack Compose)
- Version automatique : Année.Mois.N (ex. 2026.10.3 = 3e mise à jour d'octobre 2026), calculée par GitHub à chaque compilation.

## Mettre à jour (un seul geste)

1. Sur github.com : **Add file › Upload files**, déposez `music-src.zip` à la racine, puis **Commit**.
2. Le workflow **« Déballer le zip »** décompresse le zip, enregistre les fichiers et supprime le zip.
3. Il lance les compilations **Music – iPhone** et **Music – Android**.
4. Chaque compilation publie la nouvelle version dans **Releases** (`ios-NUMÉRO`, `android-NUMÉRO`).

## Dans l'app

- Au démarrage (une fois par jour), Music cherche une nouvelle version et la propose.
- **Réglages › Mises à jour** : rechercher maintenant.
- **iPhone** : avec SideStore / AltStore, la mise à jour s'installe toute seule
  (source : `https://github.com/Faxelh/Music/releases/download/ios-source/source.json`).
  Avec Sideloadly : « Télécharger l'IPA », puis l'installer par-dessus (fichiers conservés).
- **Android** : « Mettre à jour » télécharge l'APK et ouvre l'installation
  (Android demande une seule fois d'autoriser « Installer des applis inconnues »).

## Note

Les fichiers de `.github/workflows` ne peuvent pas être modifiés par un workflow (règle de GitHub) :
s'ils changent, il faut les déposer à la main dans `.github/workflows`.

## Historique des nouveautés
- `HISTORIQUE.json` : chaque mise à jour y ajoute ses nouveautés et correctifs (en tête de liste).
  Une copie est intégrée aux apps (`ios/Resources/historique.json`, `android/app/src/main/assets/historique.json`) :
  Réglages › Historique des nouveautés montre tout ; l'alerte de mise à jour lit la version en ligne
  et affiche ce que la nouvelle version corrige ; après l'installation, l'app montre ce qui a changé.
