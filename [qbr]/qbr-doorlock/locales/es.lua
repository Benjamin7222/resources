local Translations = {
    error = {
        nokey = "No tienes una llave!",
    },
    success = { 
        
    },
    info = {
        unlocked = "Abierto",
        unlocking = "Abriendo",
        locking = "Cerrando",
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
