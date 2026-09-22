local Translations = {
    error = {

    },
    success = {

    },
    info = {
        getstress = "Vous êtes stressé",
        thirsty = "Vous avez un peu soif",
        relaxing = "Vous vous détendez",
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
