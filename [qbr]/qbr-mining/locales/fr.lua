local Translations = {
    menu = {
        select = 'Choisir des marchandises',
        amount = 'Quantité',
        open = 'parler avec '
    },
    error = {
        amount = 'vous devez saisir une valeur pour %{text}',
        pickaxe = 'vous n\'avez pas de pioche !',
        mined = 'cette zone a déjà été exploitée',
        general = 'une erreur est survenue !',
        add_item = 'une erreur est survenue lors de l\'ajout de l\'objet !',
        remove_item = 'une erreur est survenue lors du retrait de l\'objet !',
        money = 'vous n\'avez pas assez d\'argent !'
    },
    mining = {
        entrance = 'Entrée de la mine',
        zone = 'Zone d\'extraction',
        start = 'pour commencer à miner ',
        progress = 'Extraction en cours..',
        success = 'vous avez trouvé %{text}',
        selling = 'vous avez vendu %{amount} x %{item}',
        bought = 'vous avez acheté %{amount} x %{item}'
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
