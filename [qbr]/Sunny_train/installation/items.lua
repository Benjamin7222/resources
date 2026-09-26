-- À fusionner dans QBShared.Items, sans remplacer les items existants.
-- Les quatre matériaux standards sont fournis à titre de référence.
return {
    ['train_coal'] = { name = 'train_coal', label = 'Charbon de locomotive', weight = 100, type = 'item', image = 'train_coal.png', unique = false, useable = false, shouldClose = true, level = 0, description = 'Charbon prêt à charger dans le wagon du train.' },
    ['train_crate_corn'] = { name = 'train_crate_corn', label = 'Caisse de maïs', weight = 500, type = 'item', image = 'train_crate_corn.png', unique = false, useable = false, shouldClose = true, level = 0, description = 'Cargaison ferroviaire pour le comptoir de Riggs Station.' },
    ['train_crate_tobacco'] = { name = 'train_crate_tobacco', label = 'Caisse de tabac', weight = 500, type = 'item', image = 'train_crate_tobacco.png', unique = false, useable = false, shouldClose = true, level = 0, description = 'Cargaison ferroviaire pour le comptoir de Riggs Station.' },
    ['train_payroll'] = { name = 'train_payroll', label = 'Caisse de solde fédérale', weight = 500, type = 'item', image = 'train_payroll.png', unique = false, useable = false, shouldClose = true, level = 0, description = 'Caisse scellée à livrer sous escorte à Saint Denis.' },
    ['train_crate_iron'] = { name = 'train_crate_iron', label = 'Caisse de fer', weight = 500, type = 'item', image = 'train_crate_iron.png', unique = false, useable = false, shouldClose = true, level = 0, description = 'Matériel à livrer aux mines d’Annesburg.' },
    ['train_crate_scrap'] = { name = 'train_crate_scrap', label = 'Caisse de pièces métalliques', weight = 500, type = 'item', image = 'train_crate_scrap.png', unique = false, useable = false, shouldClose = true, level = 0, description = 'Pièces de rechange à livrer aux mines d’Annesburg.' },
    ['train_ticket'] = { name = 'train_ticket', label = 'Billet de train', weight = 5, type = 'item', image = 'train_ticket.png', unique = true, useable = true, shouldClose = true, level = 0, description = 'Titre de transport de la compagnie ferroviaire.' },
    ['coal'] = {
        ['name'] = 'coal',
        ['label'] = 'Minerai de charbon',
        ['weight'] = 40,
        ['type'] = 'item',
        ['image'] = 'sunny_material_coal.png',
        ['unique'] = true,
        ['useable'] = false,
        ['shouldClose'] = true,
        ['combinable'] = false,
        ['level'] = 0,
        ['description'] = 'Du minerai de charbon'
    },
    ['iron'] = {
        ['name'] = 'iron',
        ['label'] = 'Minerai de fer',
        ['weight'] = 50,
        ['type'] = 'item',
        ['image'] = 'sunny_material_iron.png',
        ['unique'] = true,
        ['useable'] = false,
        ['shouldClose'] = true,
        ['combinable'] = false,
        ['level'] = 0,
        ['description'] = 'Du minerai de fer'
    },
    ['copper'] = {
        ['name'] = 'copper',
        ['label'] = 'Minerai de cuivre',
        ['weight'] = 60,
        ['type'] = 'item',
        ['image'] = 'sunny_material_copper.png',
        ['unique'] = true,
        ['useable'] = false,
        ['shouldClose'] = true,
        ['combinable'] = false,
        ['level'] = 0,
        ['description'] = 'Du minerai de cuivre'
    },
    ['metalscrap'] = {
        ['name'] = 'metalscrap',
        ['label'] = 'Ferraille',
        ['weight'] = 100,
        ['type'] = 'item',
        ['image'] = 'sunny_material_metalscrap.png',
        ['unique'] = false,
        ['useable'] = true,
        ['shouldClose'] = true,
        ['combinable'] = nil,
        ['level'] = 0,
        ['description'] = 'Aucune description'
    },
}
