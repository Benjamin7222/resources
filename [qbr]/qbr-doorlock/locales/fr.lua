local Translations = {
    error = {
        nokey = "Vous n\'avez pas la clé !",
    },
    success = {

    },
    info = {
        unlocked = "déverrouillée",
        unlocking = "Déverrouillage",
        locking = "Verrouillage",
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
