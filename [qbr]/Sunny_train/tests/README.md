# Vérification de Sunny_train

Tests récupérés du travail de Claude et adaptés aux départs programmés.
Ils ne sont pas chargés par `fxmanifest.lua`.

Depuis ce dossier, avec Node.js et npm dans le PATH :

```powershell
npm install
npm run check
npm test
npm run test:ui
```

Le test NUI utilise Chrome sans fenêtre visible. Sous Windows, il cherche
`C:/Program Files/Google/Chrome/Application/chrome.exe`. Pour un autre emplacement :

```powershell
$env:CHROME_PATH = 'C:/chemin/vers/chrome.exe'
npm run test:ui
```

Les captures sont enregistrées dans `shots/` (ignoré par Git).
Les dépendances sont limitées aux tests, sans incidence sur la ressource RedM.

## Portée

- `run.js` : scripts serveur réels, framework, inventaire, natives et BDD simulés.
  Permissions, missions, programmation, rechargement des départs, réservation
  pendant la mise en voie, billets, contrôles, maintenance, braquages et charbon.
- `client-clock.lua` : maintien de l'heure lors d'une réouverture du registre et
  réception d'une nouvelle synchronisation.
- `late-join.lua` : reprise après un premier refus avant chargement du personnage,
  synchronisation à la connexion et mise à jour du tableau à l'ouverture du guichet.
- `run.js --deliveries` : configuration livraisons réelle, départs limités à
  Saint Denis, prix final, cargaisons, concurrence et cooldown global en BDD simulée.
  `npm test` exécute cette suite et celle des anciennes missions séparément.
- `driving-prompts.lua` : commandes et visibilité des prompts avec natives simulées,
  masquage dans le registre, en pause, hors cabine et pendant les arrêts imposés.
- `ui-test.js` : interface réelle dans Chrome, réponses serveur simulées.
  Navigation clavier/manette, programmation, guichet, avis, tableau, matériel,
  contrôles et six résolutions d'écran.
- `check.js` : compilation avec Fengari (Lua 5.3), complétée par `node --check`.
  Cela ne remplace pas l'exécution Lua 5.4 de RedM ni les natives du jeu.

## Recette en jeu encore nécessaire

1. Démarrer la ressource avec oxmysql et vérifier l'absence d'erreur SQL.
2. Avec un cheminot grade 0 (aucune prise de service nécessaire), programmer un départ depuis Valentine
   vers Saint Denis, sans préciser le train. Vérifier le tableau et l'avis.
3. Au guichet, choisir ce départ, une gare de descente puis une classe.
   Vérifier le débit, l'item et l'heure du billet.
4. Prendre le départ en charge dans « Sortir un train ». Un second conducteur
   doit être refusé dès l'affectation, avant même l'apparition du train.
5. Vérifier l'avis à quai, puis quitter la gare : le tableau doit indiquer
   « Parti » et le guichet doit refuser un nouvel achat pour ce départ.
6. Cibler le voyageur avec ox_target → « Vérifier les billets ». S'il possède
   un seul billet, celui-ci s'affiche directement au cheminot ; plusieurs billets
   sont proposés dans une liste. Dans un autre convoi, vérifier l'avertissement.
   Cliquer sur « Poinçonner le billet » : seul le billet choisi doit disparaître
   de l'inventaire du voyageur. Un joueur sans billet doit être signalé.
7. Remiser avant de partir : un départ manuel redevient disponible ; un départ
   automatique est annulé. Vérifier aussi l'échec d'apparition du train.
8. Programmer puis redémarrer la ressource : vérifier la restauration depuis
   la vraie BDD, ainsi que la persistance d'une annulation.
   Connecter aussi un second joueur après la programmation : « Départs et billets »
   doit proposer les mêmes départs encore disponibles, sans en programmer un nouveau.
9. Comparer l'heure du tableau, du billet et de l'avis à celle de la machine
   serveur. Attendre deux minutes puis rouvrir le registre : l'heure ne doit
   pas reculer. Vérifier sur une machine configurée en heure française si
   c'est l'heure souhaitée. Aucun changement de fuseau système n'est effectué.

Les essais locaux n'attestent pas du spawn, du déplacement des trains,
de l'intégration SQL réelle ni de la configuration du serveur d'hébergement.

## Kit pour les livraisons et le charbon

Redémarrer le serveur pour charger les définitions ajoutées dans
`qbr-core/shared/items.lua` avant le chargement des inventaires des joueurs.
Sunny_train déclare également ces items au démarrage s'ils sont absents.

En administrateur QBR : `/trainitems` remet le kit à soi-même ;
`/trainitems ID` le remet au joueur indiqué. Depuis la console : `trainitems ID`.
Les refus de l'inventaire sont signalés et aucun lot refusé n'est annoncé comme reçu.

| Item | Quantité | Usage |
| --- | ---: | --- |
| `train_coal` | 100 | Carburant à charger dans le wagon |
| `train_crate_corn` | 20 | Légumes Saint Denis → Valentine |
| `animal_meat` | 20 | Viande Saint Denis → Annesburg (item QBR existant) |
| `train_crate_tobacco` | 10 | Livraison Blackwater → Riggs Station |
| `train_payroll` | 2 | Solde fédérale Valentine → Saint Denis |
| `train_crate_iron` | 15 | Livraison Saint Denis → Annesburg |
| `train_crate_scrap` | 10 | Livraison Saint Denis → Annesburg |

Ouvrir le wagon au dépôt depuis le registre, déposer le charbon et les caisses
nécessaires, puis signer la mission. Porter les items sur soi ne charge pas le train.
Le nouveau carburant est `train_coal` ; le minerai `coal` reste un matériau
existant, notamment pour la maintenance. Le convoi de marchandises n°12 est
fourni au départ ; les autres trains sont achetés par le patron.

Pour les contrats actifs, utiliser `config/deliveries.lua` : les autres caisses
du kit permettent de préparer des contrats supplémentaires. Vérifier avec deux
cheminots que le contrat légumes signé par l'un devient indisponible pour l'autre,
que la viande reste possible, puis redémarrer la ressource et confirmer le délai.
En cabine, vérifier les prompts avancer, freiner / reculer, régulateur, sifflet, changement de voie et fin
de trajet, y compris à la manette. Leur rendu natif n'est pas couvert par Chrome.
