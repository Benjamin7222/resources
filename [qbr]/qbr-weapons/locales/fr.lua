local Translations = {
    error = {
        canceled = 'Annulé',
        max_ammo = 'Capacité maximale de munitions',
        no_weapon = 'Vous n\'avez pas d\'arme.',
        no_support_attachment = 'Cette arme ne supporte pas cet accessoire.',
        no_weapon_in_hand = 'Vous n\'avez pas d\'arme en main.',
        weapon_broken = 'Cette arme est cassée et ne peut pas être utilisée.',
        no_damage_on_weapon = 'Cette arme n\'est pas endommagée..',
        weapon_broken_need_repair = 'Votre arme est cassée, vous devez la réparer avant de pouvoir l\'utiliser à nouveau.',
        attachment_already_on_weapon = 'Votre arme a déjà un(e) %{value}.'
    },
    success = {
        reloaded = 'Rechargée',
        weapon_ready = 'Votre arme est prête'
    },
    info = {
        loading_bullets = 'Chargement des balles',
        repair_button = 'Réparer les armes'
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
