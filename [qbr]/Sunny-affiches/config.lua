Config = {}

Config.Debug = false


Config.BoardBackground = true

Config.CameraTarget = true
Config.Camera = { forward = 0.2, height = 0.6, targetHeight = 0.4, fov = 55.0 }

Config.MaxPostersPerCategory = 30   -- affiches actives par pays et par catégorie (surchargeable : max = ... dans la catégorie)
Config.MaxTitleLength = 60
Config.MaxUrlLength = 100
Config.SaveCooldown = 3             -- secondes entre deux publications/modifications d'un joueur


Config.MaxDays = 30
Config.AllowIndefinite = true

Config.Durations = { 1, 3, 7, 14, 30, 0 }
Config.DefaultDays = 7


Config.MaxPinned = 3


Config.AuthorCanManageOwn = true

Config.AllowedHosts = {}

Config.AdminBypass = true 
Config.AdminGroups = { 'admin', 'god' }

Config.DefaultOpen = 'target'
Config.PromptFallback = false


Config.OpenKey = 0xCEFD9220
Config.MarkerDistance = 10.0
Config.ServerDistanceSlack = 6.0



Config.Blip = { sprite = 'blip_proc_bounty_poster', scale = 0.2, label = 'Panneau d\'affichage' }

Config.DefaultModel = false


Config.Webhook = 'https://discord.com/api/webhooks/1551597876965154876/G0d64syMaIK-6xEOQfTx0_GdA1ae6SIuQBhs0Z6TgUi4E0fw7WeHUIeJZWa_0-HHX5hM'
Config.WebhookName = 'Affichage RP'
Config.LogEvents = {
    create = true,
    edit = true,
    delete = true,
    pin = true,
    unpin = true,
    expire = false,
    collect = true, 
}

Config.Countries = {
    { key = 'usa',     label = 'États-Unis' },
    { key = 'mexique', label = 'Mexique' },
    { key = 'guarma',  label = 'Guarma' },
}

Config.Categories = {
    {
        key = 'gouvernement',
        label = 'Gouvernement',
        color = '#5c3a22',
        desc = 'Communiqués officiels, décrets et avis du gouvernement.',
        durations = { 3, 7, 14, 30, 0 },
        defaultDays = 14,
    },
    {
        key = 'fdo',
        label = 'Forces de l\'ordre',
        color = '#2f4a6b',
        desc = 'Avis, consignes et communiqués des forces de l\'ordre.',
        durations = { 1, 3, 7, 14, 30, 0 },
        defaultDays = 7,
    },
    {
        key = 'justice',
        label = 'Justice',
        color = '#6b4a8f',
        desc = 'Audiences, jugements et avis du Département de Justice.',

        -- JUSTICE UNIQUEMENT AUX ÉTATS-UNIS
        countries = { 'usa' },

        durations = { 3, 7, 14, 30, 0 },
        defaultDays = 14,
    },
    {
        key = 'wanted',
        label = 'Wanted',
        color = '#8f2d1f',
        desc = 'Individus recherchés. Toute information est la bienvenue.',
        durations = { 7, 14, 30, 0 },
        defaultDays = 30,
    },
    {
        key = 'journal',
        label = 'Journal',
        color = '#7a6a3a',
        desc = 'Unes, éditions et articles de la presse.',

        -- JOURNAL AUX USA + MEXIQUE, PAS À GUARMA
        countries = { 'usa', 'mexique' },

        durations = { 1, 3, 7, 14, 30, 0 },
        defaultDays = 7,
    },
    {
        key = 'propagande',
        label = 'Propagande',
        color = '#8B0000',
        desc = 'Messages, idées et affiches de propagande.',
        countries = { 'usa', 'mexique', 'guarma' },
        anonymous = true,   -- case « Publier anonymement » (propagande illégale) : l'auteur n'est pas affiché en jeu, le staff le voit toujours dans les logs
        durations = { 1 },
        defaultDays = 1,
    },
}
Config.Jobs = {
    usa = {
        gouvernement = { publier = { 'gouvernement' }, gerer = { gouvernement = 3, } },
        fdo          = { publier = { '_sheriff_newhanoverlua','police_lemoyne','_sheriff_westelizabethlua','marshal' },     gerer = { _sheriff_newhanoverlua = 3, police_lemoyne = 3, _sheriff_westelizabethlua = 3, marshal = 3 } },
        justice      = { publier = { 'justice' },        gerer = { justice = 5 } },
        wanted       = { publier = { 'justice','marshal' },     gerer = { justice = 4, marshal = 3 } },
        journal      = {
            publier = { 'journaliste_newhanover' },
            gerer   = { journaliste_newhanover = 3},
        },
    },
    mexique = {
        gouvernement = { publier = {'maire_newaustin'}, gerer = {maire_newaustin = 3} },
        fdo          = { publier = {'guardia'}, gerer = {guardia = 3} },
        justice      = { publier = {'maire_newaustin'}, gerer = {maire_newaustin = 3} },
        wanted       = { publier = {'maire_newaustin'}, gerer = {maire_newaustin = 3} },
        journal      = { publier = {'journaliste_newaustin'}, gerer = {journaliste_newaustin = 3} },
    },
    guarma = {
        gouvernement = { publier = {'guarma'}, gerer = {guarma = 3} },
        fdo          = { publier = {'milicedeguarma'}, gerer = {milicedeguarma = 3} },
        justice      = { publier = {'guarma'}, gerer = {guarma = 3} },
        wanted       = { publier = {'guarma'}, gerer = {guarma = 3} },
        journal      = { publier = {'journaliste_guarma'}, gerer = {journaliste_guarma = 3} },
    },
}


Config.Journal = {
    Enabled = true,
    Category = 'journal',         
    Currency = 'cash',            
    DefaultPrice = 2.0,
    MinPrice = 0.25,
    MaxPrice = 500.0,
    MaxStock = 100,                
    MaxLooseCopies = 3,
    Papers = {
        journaliste_newhanover = 'journal',
        journaliste_newaustin  = 'journal2',
    },
}

Config.Boards = {}
for _, city in ipairs({
    { 'valentine',  'Valentine',   'usa',     vector4(-180.0, 628.95, 114.09, 0.0) },   
    { 'saintdenis', 'Saint Denis', 'usa',     vector4(2753.21, -1384.58, 46.25, 0.0) },
    { 'blackwater', 'Blackwater',  'usa',     vector4(-873.11, -1334.18, 43.96, 0.0) },
    { 'rhodes',     'Rhodes',      'usa',     vector4(1233.84, -1293.51, 76.9, 0.0) },
    { 'annesburg',  'Annesburg',   'usa',     vector4(2933.04, 1286.24, 44.65, 0.0) },
    { 'armadillo',  'Armadillo',   'mexique', vector4(-3726.33, -2602.79, -12.94, 0.0) },
    { 'guarma',     'Guarma',      'guarma',  vector4(1310.34, -6911.67, 48.23, 0.0)},
}) do
    local board = {
        id = city[1],
        name = city[2],
        country = city[3],
        coords = city[4],
        enabled = city[5] ~= false,
        distance = 2.0,
        blip = Config.Blip and Config.Blip.sprite or false,
    }
    if city[4].w == 0.0 then
        board.boardOffset = 0.0
        board.camera = false
    end
    Config.Boards[#Config.Boards + 1] = board
end
