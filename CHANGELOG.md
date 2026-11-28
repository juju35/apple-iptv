# Changelog

## 1.5.0

### Added
- Live TV : chaque chaîne affiche le programme en cours (titre, horaires, progression) à la place de sa catégorie,
  y compris quand le fournisseur n'a pas de guide complet : le guide court de la chaîne est alors demandé à
  l'affichage de la ligne (4 à la fois, redemandé toutes les 10 min ou à la fin du dernier programme connu)
- Lecteur : programme en cours avec horaires, barre de progression et résumé, puis le programme suivant ; mis à
  jour à chaque changement de chaîne et à la fin d'un programme
- Stalker : guide court par chaîne (`itv/get_short_epg`)

### Changed
- Xtream : les chaînes sont associées au guide XMLTV sans tenir compte de la casse ni des espaces
- Lecteur VLC : « DIRECT » en pastille rouge

## 1.4.0

### Added
- Mac : bouton plein écran dans le lecteur (en haut à droite, touche F), avec le lecteur système comme avec VLC

## 1.3.1

### Fixed
- Saisie de la recherche fluide (Apple TV, Live TV, Films, Séries) : la recherche attend une pause de 300 ms dans la
  frappe et tourne en arrière-plan, une recherche dépassée est abandonnée ; les catégories ne sont plus recalculées à
  chaque caractère ; sur Apple TV les noms sont préparés dès l'ouverture de l'onglet Rechercher

## 1.3.0

### Changed
- Recherche plus tolérante (Apple TV, Live TV, Films, Séries) : sans tenir compte des accents, de la ponctuation, des
  espaces ni de l'ordre des mots (« pokemon » trouve « Pokémon », « spider man » ou « spiderman » trouvent
  « Spider-Man », « lete » trouve « L'Été »)
- Meilleurs résultats en premier : titre exact, puis titres qui commencent par la recherche, puis mots qui commencent
  par elle ; sur Apple TV les 40 résultats affichés par rangée ne sont plus les 40 premiers du catalogue
- Apple TV : la recherche attend une courte pause dans la saisie et ne recalcule plus à chaque déplacement du focus ;
  plus d'« Aucun résultat » affiché pendant la frappe

## 1.2.1

### Fixed
- Apple TV : la fiche d'un film ou d'une série affiche de nouveau sa jaquette, nette, à droite du titre (l'arrière-plan
  flouté et assombri ne la laissait pas voir)

## 1.2.0

### Added
- Écran d'ajout du premier fournisseur : bouton « Recharger depuis iCloud » pour récupérer les fournisseurs
  enregistrés sur les autres appareils quand la première synchronisation iCloud n'a rien ramené

## 1.1.2

### Fixed
- Première ouverture sur un nouvel appareil (Apple TV…) : l'app attend les fournisseurs enregistrés dans iCloud
  (« Recherche de vos fournisseurs dans iCloud… », 15 s au plus) au lieu de proposer tout de suite d'en ajouter un
- Un fournisseur ajouté avant l'arrivée des fournisseurs iCloud ne les remplace plus sur les autres appareils : les
  deux listes sont fusionnées

## 1.1.1

### Fixed
- iOS : le clavier se masque sur tous les écrans (clavier scindé de l'iPhone Duo, clavier flottant de l'iPad) — toucher
  hors du champ, faire défiler, touche Rechercher ou bouton au-dessus du clavier
- iPhone : le champ de recherche de Live TV s'affiche de nouveau (un espace vide le remplaçait) ; les catégories
  défilent avec les chaînes

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
