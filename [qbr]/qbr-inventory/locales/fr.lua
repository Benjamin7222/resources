local Translations = {
    error = {
        failed = "Échec",
        not_owned = "Vous ne possédez pas cet objet !",
        no_near = "Personne à proximité !",
        no_access = "Inaccessible",
        veh_locked = "Le véhicule est verrouillé !",
        not_exist = "Cet objet n\'existe pas ??",
        no_cash = "Vous n\'avez pas assez d\'argent liquide..",
        missing_item = "Vous n\'avez pas les bons objets..",
        yourself = "Vous ne pouvez pas vous donner un objet à vous-même ?",
        toofar = "Vous êtes trop loin pour donner des objets !",
        otherfull = "L\'inventaire de l\'autre joueur est plein !",
        invfull = "Votre inventaire est plein !",
        not_enough = "Vous n\'avez pas assez d\'objets à transférer",
        invalid_type = "Type invalide..",
        arguments = "Arguments mal renseignés..",
        cant_give = "Impossible de donner l\'objet !",
        invalid_amount = "Quantité invalide",
        not_online = "Le joueur n\'est pas connecté",
    },
    success = {
        bought_item = "%{item} acheté !",
        recieved = "Vous avez reçu %{amount}x %{item} de %{firstname} %{lastname} !",
        gave = "Vous avez donné %{amount}x %{item} à %{firstname} %{lastname} !",
        yougave = "Vous avez donné %{amount}x %{item} à %{name} !",
    },
    info = {
        pickup_snow = "Ramassage de boules de neige..",
        stash_none = "Coffre-Aucun",
        stash = "Coffre-",
        trunk_none = "Malle-Aucune",
        trunk = "Malle-",
        glove_none = "Boîte à gants-Aucune",
        glovebox = "Boîte à gants-",
        playerLabel = "Joueur-",
        dropped_none = "Au sol-Aucun",
        dropped = "Au sol-",
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
