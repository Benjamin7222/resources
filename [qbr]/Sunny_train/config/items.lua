-- Marchandises dédiées au rail. Les images existent dans qbr-inventory.
local function item(name, label, image, weight, description)
    return { name = name, label = label, image = image, weight = weight, type = 'item',
        unique = false, useable = false, shouldClose = true, combinable = nil, level = 0,
        description = description }
end

Config.RailItems = {
    train_coal = item('train_coal', 'Charbon de locomotive', 'train_coal.png', 100, 'Charbon prêt à charger dans le wagon du train.'),
    train_crate_corn = item('train_crate_corn', 'Caisse de maïs', 'train_crate_corn.png', 500, 'Cargaison ferroviaire pour le comptoir de Riggs Station.'),
    train_crate_tobacco = item('train_crate_tobacco', 'Caisse de tabac', 'train_crate_tobacco.png', 500, 'Cargaison ferroviaire pour le comptoir de Riggs Station.'),
    train_payroll = item('train_payroll', 'Caisse de solde fédérale', 'train_payroll.png', 500, 'Caisse scellée à livrer sous escorte à Saint Denis.'),
    train_crate_iron = item('train_crate_iron', 'Caisse de fer', 'train_crate_iron.png', 500, 'Matériel à livrer aux mines d’Annesburg.'),
    train_crate_scrap = item('train_crate_scrap', 'Caisse de pièces métalliques', 'train_crate_scrap.png', 500, 'Pièces de rechange à livrer aux mines d’Annesburg.'),
}

-- Quantités pour tester les trois livraisons et alimenter une locomotive.
Config.RailTestKit = {
    { item = 'train_coal', amount = 100 },
    { item = 'train_crate_corn', amount = 20 },
    { item = 'train_crate_tobacco', amount = 10 },
    { item = 'train_payroll', amount = 2 },
    { item = 'train_crate_iron', amount = 15 },
    { item = 'train_crate_scrap', amount = 10 },
}
