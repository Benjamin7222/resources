# Installation de Sunny_train — RedM / QBR

Ce dossier regroupe le SQL, les définitions des items et leurs images en noir
et blanc. Le raccordement au système de pigeons du serveur principal Sunny
reste à réaliser sur ce serveur : ses scripts et son API ne sont pas disponibles ici.

## Installer

1. Installer `Sunny_train` dans les ressources du serveur. Démarrer `qbr-core`,
   `oxmysql`, `qbr-inventory`, `ox_lib` et `ox_target` avant Sunny_train.
   Les achats par compte société utilisent aussi `qbr-management` par défaut.
2. Vérifier le job `chemindefer` et ses grades 0 à 5 dans le système de métiers
   du serveur. Les cheminots sont actifs automatiquement ; le grade 5 achète les trains.
3. Importer `sunny_train.sql` dans la base utilisée par oxmysql si une installation
   SQL manuelle est souhaitée. Les tables et migrations sont aussi traitées par
   `server/main.lua` au démarrage. Le SQL fourni crée les tables d'une installation
   neuve ; il ne remplace pas les migrations d'une ancienne installation.
4. Ouvrir `items.lua` et ajouter les définitions manquantes à la table
   `QBShared.Items` de `qbr-core/shared/items.lua`. Ne pas remplacer toute cette
   table. Adapter le format si l'inventaire du serveur principal est différent.
5. Copier les PNG de `images/` dans `qbr-inventory/html/images/`.
   Les sept items ferroviaires utilisent les noms de fichiers `train_*.png`.
   Les quatre matériaux de maintenance existent déjà dans ce serveur de travail :
   leurs variantes noir et blanc sont fournies pour une installation qui les souhaite.
   Pour un matériau existant, conserver ses propriétés et modifier uniquement
   son champ `image` vers le fichier indiqué dans `ITEMS.md`.
6. Vérifier `config/config.lua` : gares, jobs de police, charbon, inventaire,
   compte société et paramètres de dispatch. Ajouter `ensure Sunny_train` après
   les dépendances, puis redémarrer le serveur pour recharger les items avant
   les inventaires des joueurs.

Sur ce serveur de travail, les définitions ferroviaires sont déjà ajoutées au
core. `config/items.lua` et `server/items.lua` les déclarent aussi au démarrage
si elles manquent. Une déclaration persistante dans le core reste nécessaire
pour que les items soient connus avant le chargement des inventaires.

## Dispatch à raccorder aux pigeons de Sunny

**À FAIRE SUR LE SERVEUR PRINCIPAL : créer l'adaptateur qui envoie les alertes
de Sunny_train via le système de pigeons déjà présent sur Sunny.**

Le système de pigeons n'est pas fourni avec cette ressource. Aucun nom
d'événement, export, destinataire de pigeon ou format d'API Sunny n'a été
supposé. Le dispatch actuel est réglé sur `Config.Dispatch.system = 'fallback'` :
il affiche une notification de secours et un blip temporaire aux policiers et
sheriffs en service. Ce mode ne fait pas apparaître de pigeon.

Le point d'entrée existant est `Sunny.Dispatch.Send(data)` dans
`server/dispatch.lua`. Il est appelé par `server/robbery.lua` lors d'un braquage
validé. Avant transmission, les coordonnées deviennent une table `{ x, y, z }`.

| Champ envoyé | Contenu |
| --- | --- |
| `code` | Code d'alerte, `10-90` par défaut |
| `title` | Titre de l'alerte |
| `message` | Texte décrivant le train attaqué et la gare proche |
| `coords` | Coordonnées `{ x, y, z }` du convoi au moment de l'alerte |
| `jobs` | Métiers destinataires configurés, `police` et `sheriff` par défaut |
| `train` | Nom affiché du train |
| `mission` | Nom de la mission attaquée |
| `route` | Nom de la ligne de cette mission |

Travail à réaliser avec l'accès au serveur principal :

1. Identifier la ressource de pigeons, son export ou événement réel, le format
   de message et la façon de sélectionner les destinataires.
2. Dans `Config.Dispatch.custom(data)`, convertir ces champs vers son API,
   sélectionner les policiers/sheriffs en service et déclencher l'envoi du pigeon.
   Le mode `custom` reçoit les métiers mais ne filtre pas les destinataires à
   la place de l'intégration. `Sunny.Bridge.GetPlayersWithJobs(data.jobs, true)`
   fournit les IDs en service avec le bridge QBR actuel.
3. Passer à `Config.Dispatch.system = 'custom'` seulement une fois ce raccordement
   implémenté. Les modes `event` et `export` sont aussi disponibles si l'API réelle
   accepte directement les données. Ne pas utiliser les noms `my_dispatch`
   actuellement présents comme exemples dans la configuration.
4. Faire gérer par le système Sunny l'arrivée du pigeon et la lecture du message,
   ainsi que le repérage sur la carte si ce système le prévoit. Éviter d'envoyer
   en double un pigeon et le télégramme de secours.
5. Tester un braquage sur une mission autorisée : bons destinataires,
   message lisible, coordonnées justes, un seul envoi, aucun envoi aux civils,
   comportement contrôlé si la ressource de pigeons est arrêtée.

Les voyages libres ne sont actuellement pas braquables (`Runs.IsRobbable`
exige une mission). Ils ne déclenchent donc pas ce dispatch de braquage.

Le serveur principal étant indisponible, cette intégration ne peut pas être
validée ici. Le mode de secours est conservé pour les essais locaux.

## Tester les items et les billets

En administrateur QBR, `/trainitems` donne le kit de charbon et de livraison.
`/trainitems ID` le donne au joueur indiqué. Charger le charbon `train_coal`
et les caisses dans le wagon depuis le registre avant de signer la mission.
`coal` est le minerai destiné à certaines réparations, pas le carburant du train.

Pour un billet authentique, programmer un départ puis l'acheter au guichet :
un simple `/giveitem` ne crée pas son enregistrement en base. Le cheminot cible
le voyageur avec ox_target → « Vérifier les billets » → « Poinçonner le billet ».
Le billet sélectionné est retiré de l'inventaire du voyageur.

Voir `ITEMS.md` pour les noms et quantités, et `../tests/README.md` pour la recette
complète. Les images sont monochromes ; leur apparence finale dépend aussi
du fond et des éventuels filtres de l'inventaire du serveur principal.

## Livraisons et commandes de conduite

Les contrats se configurent dans `config/deliveries.lua` : entreprise, nom,
catégorie, gare de livraison, items et quantités, prix final, délai en secondes.
Deux exemples sont actifs : légumes vers Valentine (20 `train_crate_corn`, 500 $)
et viande vers Annesburg (20 `animal_meat`, 450 $). La viande utilise l'item QBR
existant. Les marchandises et le charbon doivent être déposés dans le wagon.
`/trainitems` fournit le kit ferroviaire et les marchandises des contrats configurés,
y compris les 20 viandes nécessaires au second contrat (items à déclarer dans QBR).

Tous les contrats partent uniquement de **Saint Denis**, avec un train de fret
possédé par la compagnie. Ils remplacent les anciennes missions quand
`Config.Deliveries.enabled = true`. Les cheminots les réalisent pour les entreprises ;
`allowedJobs = { nom_du_job = grade_minimum }` peut restreindre un contrat, en plus
des droits du registre et de conduite configurés dans `config.lua`.

Le cooldown par défaut est **global**, partagé par tous les personnages pour
chaque couple entreprise/catégorie. Il commence à la signature, dure deux heures,
reste actif en cas d'annulation et survit au redémarrage grâce à la table
`sunny_train_delivery_cooldowns`. La viande reste disponible pendant le cooldown
des légumes. Conserver la même `category` pour plusieurs variantes d'un même run.
Un refus pour cargaison ou charbon manquant ne consomme pas le cooldown.
Le mode `cooldownScope = 'player'` est optionnel ; la configuration fournie utilise
`'company'` pour le partage global. Une mise à jour SQL est fournie et la table
est également créée automatiquement au lancement de la ressource.

Les livraisons de fret ne créent pas de départ voyageurs ni de vente de billets.
Un voyage programmé se prend en charge depuis « Sortir un train » en sélectionnant
le départ existant. « Gare de départ » désigne l'origine ; « Gare d'arrivée »
désigne la destination du même trajet.

La conduite assistée affiche les commandes dans les **prompts natifs RedM** :
avancer (W maintenu), freiner puis reculer (S maintenu), régulateur (ESPACE, garde
la vitesse ; S le coupe), sifflet (U) et changement de voie (flèches ← →) à
l'approche d'un aiguillage. En voyage libre, train arrêté au dépôt ou au quai
d'une gare (`Config.FreeTravel.parkRadius`), « Ranger le train » (F maintenu)
termine le voyage. Les touches restent
configurables dans `Config.Driving` et `Config.Junctions`. Le HUD garde les données
de conduite, sans liste de touches. Les prompts sont masqués hors cabine, pendant
un arrêt imposé et lorsque le registre ou le menu pause est ouvert.

En voyage libre, la plaque affiche le train, la vitesse, l'état de conduite et le
charbon, sans destination ni compteur de gares. Le train peut continuer après
la destination annoncée ; un arrêt à cette gare ne l'immobilise plus. Le rangement
reste disponible dans le registre. Les missions de livraison conservent leur
prochain arrêt et leurs étapes. Le target et les menus utilisent le libellé
« Ouvrir le stockage ».

Au guichet, une seule interaction « Départs et billets » ouvre la liste des
départs programmés avec leurs statuts. Sélectionner un départ permet de choisir
la gare de descente, la classe et d'acheter sans fermer l'interface. Les nouveaux
départs apparaissent en direct ; les trains partis ne sont plus sélectionnables.
Les tarifs et la disponibilité sont revérifiés côté serveur lors de la sélection
et de l'achat. Si la vente est désactivée pour une gare, son tableau reste consultable.
