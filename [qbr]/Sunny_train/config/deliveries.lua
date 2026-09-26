-- Contrats de livraison : tous les départs se font à Saint Denis.
-- Les cheminots transportent pour ces entreprises. allowedJobs, facultatif,
-- ajoute une restriction { nom_du_job = grade_minimum } aux droits de conduite.
-- Une catégorie conserve le même cooldown même avec plusieurs destinations.
Config.Deliveries = {
    enabled = true,
    startStation = 'saint_denis',
    cooldown = 2 * 60 * 60, -- secondes après la signature ; conservé si annulation
    cooldownScope = 'company', -- GLOBAL : partagé par tous pour entreprise + catégorie
    companies = {
        farm = {
            label = 'Coopérative agricole',
            -- allowedJobs = { railway = 0 },
            runs = {
                vegetables = {
                    label = 'Livrer des légumes',
                    category = 'vegetables',
                    destination = 'valentine',
                    items = { { item = 'train_crate_corn', amount = 20 } },
                    reward = 500, -- prix final, sans prime par arrêt
                    cooldown = 7200,
                },
            },
        },
        butcher = {
            label = 'Boucherie de Saint Denis',
            runs = {
                meat = {
                    label = 'Livrer de la viande',
                    category = 'meat',
                    destination = 'annesburg',
                    items = { { item = 'animal_meat', amount = 20 } },
                    reward = 450,
                    cooldown = 7200,
                },
            },
        },
    },
}
