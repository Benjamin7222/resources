local Translations = {
    weather = {
        now_frozen = 'La météo est maintenant figée.',
        now_unfrozen = 'La météo n\'est plus figée.',
        invalid_syntax = 'Syntaxe invalide, la syntaxe correcte est : /weather <typedemétéo> ',
        invalid_syntaxc = 'Syntaxe invalide, utilisez plutôt /weather <typedemétéo> !',
        updated = 'La météo a été mise à jour.',
        invalid = 'Type de météo invalide, les types valides sont : \nEXTRASUNNY CLEAR NEUTRAL SMOG FOGGY OVERCAST CLOUDS CLEARING RAIN THUNDER SNOW BLIZZARD SNOWLIGHT XMAS HALLOWEEN ',
        invalidc = 'Type de météo invalide, les types valides sont : \nEXTRASUNNY CLEAR NEUTRAL SMOG FOGGY OVERCAST CLOUDS CLEARING RAIN THUNDER SNOW BLIZZARD SNOWLIGHT XMAS HALLOWEEN ',
        willchangeto = 'La météo va changer pour : %{value}.',
        accessdenied = 'Accès à la commande /weather refusé.',
    },
    dynamic_weather = {
        disabled = 'Les changements de météo dynamiques sont maintenant désactivés.',
        enabled = 'Les changements de météo dynamiques sont maintenant activés.',
    },
    time = {
        frozenc = 'L\'heure est maintenant figée.',
        unfrozenc = 'L\'heure n\'est plus figée.',
        now_frozen = 'L\'heure est maintenant figée.',
        now_unfrozen = 'L\'heure n\'est plus figée.',
        morning = 'Heure réglée sur le matin.',
        noon = 'Heure réglée sur midi.',
        evening = 'Heure réglée sur le soir.',
        night = 'Heure réglée sur la nuit.',
        change = 'L\'heure est maintenant %{value}:%{value2}.',
        changec = 'L\'heure a été changée pour : %{value} !',
        invalid = 'Syntaxe invalide, la syntaxe correcte est : time <heure> <minute> !',
        invalidc = 'Syntaxe invalide. Utilisez plutôt /time <heure> <minute> !',
        access = 'Accès à la commande /time refusé.',
    },
    blackout = {
        enabled = 'Le black-out est maintenant activé.',
        enabledc = 'Le black-out est maintenant activé.',
        disabled = 'Le black-out est maintenant désactivé.',
        disabledc = 'Le black-out est maintenant désactivé.',
    },
    help = {
        weathercommand = 'Changer la météo.',
        weathertype = 'typedemétéo',
        availableweather = 'Types disponibles : extrasunny, clear, neutral, smog, foggy, overcast, clouds, clearing, rain, thunder, snow, blizzard, snowlight, xmas & halloween',
        timecommand = 'Changer l\'heure.',
        timehname = 'heures',
        timemname = 'minutes',
        timeh = 'Un nombre entre 0 et 23',
        timem = 'Un nombre entre 0 et 59',
        freezecommand = 'Figer / défiger l\'heure.',
        freezeweathercommand = 'Activer/désactiver les changements de météo dynamiques.',
        morningcommand = 'Régler l\'heure sur 09:00',
        nooncommand = 'Régler l\'heure sur 12:00',
        eveningcommand = 'Régler l\'heure sur 18:00',
        nightcommand = 'Régler l\'heure sur 23:00',
        blackoutcommand = 'Activer/désactiver le mode black-out.',
    },
    error = {
        not_access = 'Vous n\'avez pas accès à cette commande.',
        not_allowed = 'Vous n\'êtes pas autorisé à utiliser cette commande.',
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
