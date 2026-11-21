# Changelog

## 1.1.1

### Fixed
- iOS : le clavier se masque sur tous les écrans (clavier scindé de l'iPhone Duo, clavier flottant de l'iPad) — toucher
  hors du champ, faire défiler, touche Rechercher ou bouton au-dessus du clavier

## 1.1.0

### Changed
- Accueil façon Netflix : bannière plein écran sous la barre de navigation (Lecture, Ma liste, Plus d'infos),
  titre mis en avant tiré au hasard, rangées d'affiches sans légende, Top 10 films et séries (note du
  fournisseur) avec grands chiffres, « Tout afficher » sur chaque rangée, squelette animé pendant le chargement
- Apple TV : billboard au-dessus des rangées qui suit l'affiche sous le focus (artwork, titre, infos, résumé)
- Fiche détail iPhone, iPad et Mac : artwork bord à bord, titre et ligne d'infos, bouton Lecture blanc pleine
  largeur, Reprendre au début en gris, action Ma liste ; la Lecture de la bannière démarre directement
- Favoris des films et séries renommés « Ma liste » (+ / ✓), les chaînes gardent leurs favoris
- Fluidité : rangées de l'accueil calculées une fois par catalogue (plus à chaque rafraîchissement), artwork de
  la bannière et de la fiche en cache (affiche de la rangée affichée tout de suite), affiches qui réagissent
  au toucher et au survol

### Fixed
- iPhone Duo en paysage : le sélecteur de fournisseur passe juste au-dessus de la barre d'onglets latérale ; sous
  les icônes réseau, la Dynamic Island le recouvrait

## 1.0.0

### New
- Client IPTV pour iPhone (iPhone Duo compris), iPad, Mac et Apple TV, en SwiftUI, à l'interface inspirée de Netflix :
  accueil avec bannière et carrousels par catégorie, onglets Live TV, Films et Séries avec grille, filtre par
  catégorie et recherche
- Fournisseurs Xtream Codes (identifiant / mot de passe) et Stalker / Ministra (adresse MAC), plusieurs comptes,
  test de connexion, synchronisés entre appareils via iCloud
- Fiche détail : affiche, résumé, note, guide des programmes pour les chaînes en direct (Xtream)
- Séries : sélecteur de saison et liste des épisodes de la saison, avec vignettes et résumés
- Lecture avec le lecteur système (HLS, MP4, AirPlay) et bascule automatique sur VLC pour les autres formats
  (MKV, AVI, MPEG-TS…)
- iPhone Duo à moitié plié : vidéo d'un côté du pli et commandes de l'autre (posture ordinateur ou livre)
- Icône pour iOS, macOS et Apple TV (icône à couches et images top shelf)
