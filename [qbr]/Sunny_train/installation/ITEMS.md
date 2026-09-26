# Items utilisés

| Nom interne | Libellé | Image noir et blanc | Usage / quantité du kit |
| --- | --- | --- | --- |
| `train_coal` | Charbon de locomotive | `train_coal.png` | Carburant / 100 |
| `train_crate_corn` | Caisse de maïs | `train_crate_corn.png` | Légumes vers Valentine / 20 |
| `train_crate_tobacco` | Caisse de tabac | `train_crate_tobacco.png` | Livraison Riggs Station / 10 |
| `train_payroll` | Caisse de solde fédérale | `train_payroll.png` | Livraison Saint Denis / 2 |
| `train_crate_iron` | Caisse de fer | `train_crate_iron.png` | Livraison Annesburg / 15 |
| `train_crate_scrap` | Caisse de pièces métalliques | `train_crate_scrap.png` | Livraison Annesburg / 10 |
| `train_ticket` | Billet de train | `train_ticket.png` | Achat au guichet, numéro unique en BDD |
| `coal` | Minerai de charbon | `sunny_material_coal.png` | Entretien : 2 ; révision : 4 |
| `metalscrap` | Ferraille | `sunny_material_metalscrap.png` | Entretien : 1 ; mécanique : 3 |
| `iron` | Minerai de fer | `sunny_material_iron.png` | Mécanique : 3 ; révision : 6 |
| `copper` | Minerai de cuivre | `sunny_material_copper.png` | Révision : 2 |

Le kit `/trainitems` contient les six premières lignes et les items des contrats
de `config/deliveries.lua`. La livraison de viande vers Annesburg utilise
20 `animal_meat`, déjà déclaré dans QBR avec son image d'origine `meat.png`.
Les anciennes cargaisons de tabac, solde, fer et ferraille restent disponibles
pour créer d'autres contrats ; leurs anciennes missions sont désactivées.
Les matériaux de
maintenance se donnent avec `/giveitem ID NOM QUANTITE` en administrateur.
`corn`, `tobacco` et `moneybag` ne sont pas les cargaisons actuelles : les
missions utilisent les caisses ferroviaires ci-dessus.

Les PNG se trouvent dans `images/`, à copier dans `qbr-inventory/html/images/`.
`items.lua` fournit les définitions à fusionner dans `QBShared.Items`.
Les quatre matériaux de maintenance existent déjà dans le serveur de travail.
Pour un matériau existant, conserver ses propriétés et modifier uniquement
le champ `image` si sa variante monochrome est souhaitée. Ne pas créer de doublons.

Un billet authentique doit être acheté au guichet : `/giveitem` seul ne crée
pas les métadonnées et la ligne SQL nécessaires. Le poinçonnage consomme le
billet sélectionné et conserve sa trace en base.

Les 11 images ont été créées avec l'outil intégré `image_gen` dans un style
photographique western de 1899, noir et blanc, sans texte et sur fond transparent.
Les prompts exacts sont conservés dans `images/sources.json`.
