local Translations = {
    stable  = {
        stable = "Écurie",
        set_name = "Donnez un nom à votre cheval :",
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
