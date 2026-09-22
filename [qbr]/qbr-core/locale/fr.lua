local Translations = {
    error = {
        not_online = 'Le joueur n\'est pas connecté',
        wrong_format = 'Format incorrect',
        missing_args = 'Arguments manquants (x, y, z)',
        missing_args2 = 'Tous les arguments doivent être remplis !',
        no_access = 'Vous n\'avez pas accès à cette commande',
        company_too_poor = 'Votre employeur est fauché',
        item_not_exist = 'Cet objet n\'existe pas',
        too_heavy = 'Inventaire trop plein',
        no_skill = 'Cette compétence n\'existe pas'
    },
    success = {},
    info = {
        received_paycheck = 'Vous avez reçu votre salaire de %{value} $',
        job_info = 'Métier : %{value} | Grade : %{value2} | Service : %{value3}',
        gang_info = 'Gang : %{value} | Grade : %{value2}',
        on_duty = 'Vous êtes maintenant en service !',
        off_duty = 'Vous n\'êtes plus en service !',
        level_info = 'Votre niveau est %{value} dans la compétence : %{value2}',
        xp_info = 'Vous avez %{value} xp dans la compétence : %{value2}',
        xp_removed = 'Le joueur a perdu de l\'expérience',
        xp_added = 'Le joueur a reçu de l\'expérience'
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
