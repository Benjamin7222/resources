-- ============================================================================
--  Sunny_train - Configuration
--
--  Tout ce qui décrit le réseau (trains, gares, lignes, missions, prix,
--  récompenses, temps, items, permissions, dispatch) se règle ici.
--
--  ⚠ COORDONNÉES : les positions des gares ci-dessous sont des valeurs
--  approximatives marquées « À VÉRIFIER ». Utilisez /sunnytrain_pos en jeu
--  pour relever la position exacte (copiée dans la console F8) et
--  /sunnytrain_debug pour visualiser les points et rayons configurés.
--
--  ⚠ JOB : Sunny_train ne gère NI les jobs, NI les grades, NI les salaires.
--  Il lit simplement le job du joueur (PlayerData.job de qbr-core, alimenté
--  par Job Creator). Renseignez ici le nom technique du job créé dans
--  Job Creator.
-- ============================================================================

Config = {}

Config.Debug = false            -- Logs détaillés (console client/serveur)

-- ----------------------------------------------------------------------------
--  Framework / intégrations
-- ----------------------------------------------------------------------------
Config.Framework = {
    core = 'qbr-core',          -- nom du resource core (exports)
    ticketAccount = 'cash',     -- compte débité à l'achat d'un billet
    rewardAccount = 'cash',     -- compte crédité à la fin d'une mission
}

-- Notifications : 'nui' (télégramme Sunny_train) ou 'framework' (Notify qbr-core)
Config.Notify = {
    mode = 'nui',
    duration = 5500,
}

-- Identité visuelle de la compagnie (affichée dans la NUI)
Config.Company = {
    name     = 'Sunny Pacific',
    fullName = 'Sunny Pacific Railroad Company',
    motto    = 'Service Ferroviaire',
    founded  = 'Fondée en 1869',
    year     = 1899,              -- année affichée sur les billets / registres
}

-- ----------------------------------------------------------------------------
--  Permissions (lecture du job existant — aucun système de grade ici)
--  Format : [nom_du_job] = grade minimum (PlayerData.job.grade.level)
-- ----------------------------------------------------------------------------
Config.Permissions = {
    -- Accès au registre de la compagnie (menu employé)
    employees = {
        chemindefer = 0,
    },

    actions = {
        -- Job « chemindefer » : grades 0 à 5, le grade 5 est le patron.
        drive       = { chemindefer = 0 },        -- conduire (missions)
        control     = { chemindefer = 0 },        -- contrôle des billets
        maintenance = { chemindefer = 2 },        -- inspecter / réparer
        restore     = { chemindefer = 4 },        -- remettre / retirer du service (4 et patron)
        schedule    = { chemindefer = 0 },        -- programmer un départ (tous les cheminots)
        purchase    = { chemindefer = 5 },        -- acheter / revendre du matériel (patron)
    },

    -- Les cheminots sont toujours actifs, indépendamment du duty du framework.
    -- Surcharge optionnelle (serveur) : function(source, player) return jobName, gradeLevel, onDuty end
    -- Laisser nil pour lire PlayerData.job (qbr-core / Job Creator).
    getJob = nil,
}

-- ----------------------------------------------------------------------------
--  Commandes
-- ----------------------------------------------------------------------------
Config.Commands = {
    menu     = 'train',            -- ouvre le registre de la compagnie (employés, partout)
    position = 'sunnytrain_pos',    -- relève la position (admin / debug)
    debug    = 'sunnytrain_debug',  -- affiche les points configurés
    unlock   = 'sunnytrain_ui',     -- sécurité : force la fermeture de la NUI
    despawn  = 'sunnytrain_despawn', -- admin : supprime un train bloqué (ACE ci-dessous)
    positionAce = 'command',       -- ACE requise pour /sunnytrain_pos et /sunnytrain_debug
}

-- ----------------------------------------------------------------------------
--  Interaction (prompts natifs RedM)
-- ----------------------------------------------------------------------------
Config.Interaction = {
    key          = 0xCEFD9220,     -- E
    staffKey     = 0xE30CD707,     -- R : registre de la compagnie au guichet (personnel)
    holdKey      = 0x760A9C6F,     -- G (actions « maintenir »)
    scanInterval = 1000,           -- ms entre deux scans quand le joueur est loin
    nearDistance = 25.0,           -- distance à partir de laquelle on scanne plus vite
    blips = {
        enabled = true,
        sprite  = 1258184551,            -- sprite de gare (valeur utilisée par bcc-train)
        scale   = 0.2,
    },
    holdDuration = 1200,           -- ms pour valider un prompt « maintenir »
}

-- ----------------------------------------------------------------------------
--  ox_target
--  mode :
--    'target' : tout ce qui peut passer par ox_target y passe (bureau, guichet,
--               horaires, braquage du convoi, contrôle d'un voyageur) ; les
--               prompts restent pour ce qui n'est pas compatible (conduite,
--               aiguillages, sifflet, fin de trajet en cabine).
--               Si ox_target n'est pas démarré : repli automatique sur les prompts.
--    'both'   : ox_target ET prompts natifs aux mêmes endroits.
--    'prompt' : prompts natifs uniquement.
-- ----------------------------------------------------------------------------
Config.Target = {
    mode     = 'target',
    resource = 'ox_target',
    distance = 2.5,                -- distance d'interaction des zones (bureau, guichet)
    zoneRadius = 1.2,              -- rayon des zones ox_target
    playerDistance = 2.5,          -- contrôle d'un voyageur
    trainDistance  = 4.0,          -- braquage : distance au wagon visé
    icons = {
        office      = 'fa-solid fa-book',
        desk        = 'fa-solid fa-ticket',
        board       = 'fa-solid fa-clock',
        control     = 'fa-solid fa-clipboard-check',
        robbery     = 'fa-solid fa-sack-dollar',
        hold        = 'fa-solid fa-boxes-stacked',
    },
}

-- ----------------------------------------------------------------------------
--  Interface (NUI)
-- ----------------------------------------------------------------------------
Config.UI = {
    -- Contrôles manette relus côté Lua pendant que la NUI est ouverte
    gamepad = {
        enabled = true,
        up      = 0x6319DB71,      -- INPUT_FRONTEND_UP     (D-Pad / stick)
        down    = 0x05CA7C52,      -- INPUT_FRONTEND_DOWN
        accept  = 0xC7B5340A,      -- INPUT_FRONTEND_ACCEPT (A)
        cancel  = 0x156F7119,      -- INPUT_FRONTEND_CANCEL (B)
        repeatDelay = 320,         -- ms avant répétition quand on maintient
        repeatRate  = 110,         -- ms entre deux répétitions
    },
    -- Lecture Gamepad API du navigateur (secours, désactivée par défaut
    -- pour éviter les doublons avec la lecture Lua ci-dessus)
    browserGamepad = false,
    sounds = {
        enabled  = true,
        soundset = 'HUD_SHOP_SOUNDSET',
        nav      = 'NAV_UP',
        select   = 'SELECT',
        back     = 'BACK',
    },
    use24h = true,
}

-- ----------------------------------------------------------------------------
--  Conduite
-- ----------------------------------------------------------------------------
Config.Driving = {
    -- 'assisted' : conduite gérée par Sunny_train (recommandé)
    -- 'native'   : Sunny_train ne touche pas à la vitesse
    mode = 'assisted',
    -- Commandes (maintenir W / S) :
    --   W maintenu  : le train accélère (ou freine s'il recule)
    --   S maintenu  : le train freine ; arrêté et toujours maintenu, il recule
    --   Régulateur  : garde la vitesse actuelle ; S le coupe, W l'augmente
    --   Sans touche ni régulateur, le train ralentit doucement (sur l'erre).
    -- Le moteur du jeu plafonne un train à 30 m/s (_SET_TRAIN_MAX_SPEED).
    allowReverse  = true,             -- _SET_TRAIN_REVERSE_ENABLED
    reverseMaxSpeed = 5.0,            -- m/s : vitesse max en marche arrière
    reverseDelay  = 700,              -- ms à l'arrêt, S maintenu, avant de reculer
    -- Plusieurs contrôles par action : le premier est affiché par le prompt.
    forwardKeys   = { 0x8FD015D8, 0xDEBD7EF6 }, -- W : INPUT_MOVE_UP_ONLY, INPUT_VEH_MOVE_UP_ONLY
    -- S : INPUT_VEH_DRAFT_MOVE_DOWN_ONLY (affiché : sans axe de stick partagé avec W),
    -- INPUT_VEH_MOVE_DOWN_ONLY, INPUT_MOVE_DOWN_ONLY
    backKeys      = { 0x25493EB3, 0x16D73E1D, 0xD27782E3 },
    cruiseKey     = 0xD9D0E1C0,       -- ESPACE : régulateur (maintient la vitesse)
    -- F (INPUT_CONTEXT_B) maintenu : remiser / terminer le trajet. G et E ne conviennent
    -- pas en cabine (G inactif en véhicule, E = descendre du véhicule).
    cabHoldKey    = 0x3B24C470,
    -- Les touches ci-dessus sont affichées par les prompts natifs RedM.
    acceleration  = 0.8,              -- m/s² (inertie à la traction)
    braking       = 2.0,              -- m/s² (freinage, S maintenu)
    coasting      = 0.25,             -- m/s² (ralentissement sans traction)
    lockBraking   = 4.5,              -- m/s² (arrêt imposé : gare, braquage, tender vide)
    stationCheckInterval = 500,       -- ms entre deux détections de gare
    stopSpeed     = 0.9,              -- m/s : en dessous, le train est « à l'arrêt »
    teleportIntoCab = true,           -- place le conducteur en cabine au départ
    exitCabGrace  = 180,              -- s hors cabine avant échec de la mission (0 = jamais)
    trainStopsForStations = false,    -- arrêts automatiques natifs (laisser false)
    loadTimeout   = 6000,             -- ms max pour que le train soit chargé (_HAS_TRAIN_LOADED)

    -- Sifflet (_TRIGGER_TRAIN_WHISTLE). Séquences possibles :
    -- ACKNOWLEDGE, BACKING_UP, CROSSING, DANGER, MOVING, NEXT_STATION, PASSING, STOPPED
    whistle = {
        key        = 0xD8F73058,      -- U : sifflet manuel (H appelle le cheval)
        manual     = 'CROSSING',
        onDepart   = 'MOVING',        -- au départ d'une gare (nil = aucun)
        onApproach = 'NEXT_STATION',  -- à l'approche du prochain arrêt
        onReverse  = 'BACKING_UP',    -- en passant en marche arrière
    },
}

-- ----------------------------------------------------------------------------
--  Aiguillages
--  À l'approche d'une intersection, le conducteur peut choisir la position
--  de l'aiguillage (natives _RETURN_TRAIN_INFO_FROM_HANDLE,
--  _GET_TRAIN_TRACK_JUNCTION_AT_COORDS, _GET_JUNCTION_COORDS_FOR_TRAIN_TRACK,
--  _SET_TRAIN_TRACK_JUNCTION_SWITCH).
--
--  Le jeu n'expose pas quelle position correspond à « tout droit » : les
--  libellés ci-dessous sont à confirmer en jeu (inversez-les si besoin).
-- ----------------------------------------------------------------------------
Config.Junctions = {
    enabled        = true,
    -- Flèches gauche / droite : changer de voie (J = journal, inactif en cabine).
    keys           = { 0xA65EBAB4, 0xDEB34313 }, -- INPUT_FRONTEND_LEFT, INPUT_FRONTEND_RIGHT
    detectDistance = 180.0,           -- m : distance à laquelle l'aiguillage est proposé
    lockDistance   = 12.0,            -- m : trop près, le train est déjà engagé
    lookAhead      = { 0.0, 40.0, 90.0, 150.0 }, -- points sondés devant le train (m)
    scanInterval   = 500,             -- ms entre deux recherches
    sync           = true,            -- diffuse la position à tous les joueurs (via le serveur)
    labels = {
        [false] = 'Voie principale',
        [true]  = 'Voie déviée',
    },
    -- Réseaux de voies du jeu (trainTrack) sondés pour trouver les aiguillages.
    tracks = {
        'TRAINS3', 'TRAINS_NB1', 'TRAINS_NB2', 'TRAINS_NB3',
        'TRAINS_OLD_WEST01', 'TRAINS_OLD_WEST02', 'TRAINS_OLD_WEST03',
        'TRAINS_OLD_WEST_INTERSECTION01', 'TRAINS_OLD_WEST_INTERSECTION02',
        'TRAINS_INTERSECTION1_3', 'TRAINS_INTERSECTION1_ANN', 'TRAINS_INTERSECTION1_APP',
        'TRAINS_INTERSECTION2_3', 'TRAINS_INTERSECTION2_ANN', 'TRAINS_INTERSECTION3_COR',
        'FREIGHT_GROUP', 'FREIGHT_NB1_INTER', 'BRAITHWAITES2_TRACK_CONFIG', 'TRAINS_ROB3',
    },
    debugCommand   = 'sunnytrain_junction', -- affiche l'aiguillage détecté (ACE requise)
}

-- ----------------------------------------------------------------------------
--  Gares
--  office     : bureau de la compagnie (employés)
--  ticketDesk : guichet des billets (public)
--  platform   : zone de quai où le train doit s'arrêter (rayon large : un
--               train est long, la position vérifiée est celle du conducteur)
--  depot      : point de mise en voie des trains partant de cette gare
--               (direction = sens de circulation sur la voie, à tester)
--  services   : tickets / departures / maintenance
--  schedules  : départs supplémentaires affichés (en plus de Config.Routes)
-- ----------------------------------------------------------------------------
Config.Stations = {
    blackwater = {
        label  = 'Blackwater',
        region = 'Great Plains, West Elizabeth',
        coords = vector3(-875.20, -1328.60, 43.96),              -- À VÉRIFIER
        blip   = true,
        office     = { coords = vector3(-873.60, -1333.70, 43.96), radius = 1.8 },   -- À VÉRIFIER
        ticketDesk = { coords = vector3(-876.90, -1334.50, 43.96), radius = 1.8 },   -- À VÉRIFIER
        platform   = { coords = vector3(-872.50, -1322.00, 43.20), radius = 55.0 },  -- À VÉRIFIER
        depot      = { coords = vector3(-925.00, -1330.00, 43.20), direction = true },-- À VÉRIFIER
        services   = { tickets = true, departures = true, maintenance = true },
        schedules  = {},
    },
    riggs_station = {
        label  = 'Riggs Station',
        region = 'Big Valley, West Elizabeth',
        coords = vector3(-1094.40, -576.50, 82.40),              -- À VÉRIFIER
        blip   = true,
        office     = { coords = vector3(-1096.00, -580.00, 82.40), radius = 1.8 },   -- À VÉRIFIER
        ticketDesk = { coords = vector3(-1093.00, -580.50, 82.40), radius = 1.8 },   -- À VÉRIFIER
        platform   = { coords = vector3(-1092.00, -571.00, 82.00), radius = 55.0 },  -- À VÉRIFIER
        depot      = { coords = vector3(-1092.00, -620.00, 82.00), direction = true },-- À VÉRIFIER
        services   = { tickets = true, departures = true, maintenance = false },
        schedules  = {},
    },
    valentine = {
        label  = 'Valentine',
        region = 'Heartlands, New Hanover',
        coords = vector3(-163.80, 638.70, 114.03),               -- À VÉRIFIER
        blip   = true,
        office     = { coords = vector3(-175.10, 632.30, 114.09), radius = 1.8 },    -- À VÉRIFIER
        ticketDesk = { coords = vector3(-178.20, 631.50, 114.09), radius = 1.8 },    -- À VÉRIFIER
        platform   = { coords = vector3(-163.80, 638.70, 113.50), radius = 55.0 },   -- À VÉRIFIER
        depot      = { coords = vector3(-150.00, 610.00, 113.50), direction = true },-- À VÉRIFIER
        services   = { tickets = true, departures = true, maintenance = true },
        schedules  = {},
    },
    emerald_station = {
        label  = 'Emerald Station',
        region = 'Heartlands, New Hanover',
        coords = vector3(1525.20, 442.50, 90.68),                -- À VÉRIFIER
        blip   = true,
        office     = nil,
        ticketDesk = { coords = vector3(1522.00, 441.90, 90.68), radius = 1.8 },     -- À VÉRIFIER
        platform   = { coords = vector3(1530.00, 440.00, 90.20), radius = 55.0 },    -- À VÉRIFIER
        depot      = nil,
        services   = { tickets = true, departures = true, maintenance = false },
        schedules  = {},
    },
    rhodes = {
        label  = 'Rhodes',
        region = 'Scarlett Meadows, Lemoyne',
        coords = vector3(1225.80, -1296.50, 76.90),              -- À VÉRIFIER
        blip   = true,
        office     = { coords = vector3(1229.00, -1299.00, 76.90), radius = 1.8 },   -- À VÉRIFIER
        ticketDesk = { coords = vector3(1225.70, -1300.20, 76.90), radius = 1.8 },   -- À VÉRIFIER
        platform   = { coords = vector3(1220.00, -1290.00, 76.40), radius = 55.0 },  -- À VÉRIFIER
        depot      = { coords = vector3(1180.00, -1270.00, 76.40), direction = true },-- À VÉRIFIER
        services   = { tickets = true, departures = true, maintenance = false },
        schedules  = {},
    },
    saint_denis = {
        label  = 'Saint Denis',
        region = 'Bayou Nwa, Lemoyne',
        coords = vector3(2747.40, -1398.40, 46.18),              -- À VÉRIFIER
        blip   = true,
        office     = { coords = vector3(2742.00, -1394.00, 46.18), radius = 1.8 },   -- À VÉRIFIER
        ticketDesk = { coords = vector3(2747.70, -1395.90, 46.18), radius = 1.8 },   -- À VÉRIFIER
        platform   = { coords = vector3(2755.00, -1410.00, 45.70), radius = 60.0 },  -- À VÉRIFIER
        depot      = { coords = vector3(2780.00, -1450.00, 45.70), direction = false },-- À VÉRIFIER
        services   = { tickets = true, departures = true, maintenance = true },
        schedules  = {},
    },
    annesburg = {
        label  = 'Annesburg',
        region = 'Roanoke Ridge, New Hanover',
        coords = vector3(2933.50, 1282.50, 44.65),               -- À VÉRIFIER
        blip   = true,
        office     = nil,
        ticketDesk = { coords = vector3(2938.80, 1284.40, 44.65), radius = 1.8 },    -- À VÉRIFIER
        platform   = { coords = vector3(2930.00, 1290.00, 44.20), radius = 55.0 },   -- À VÉRIFIER
        depot      = nil,
        services   = { tickets = true, departures = true, maintenance = false },
        schedules  = {},
    },
}

-- ----------------------------------------------------------------------------
--  Lignes (trajets)
--  Une ligne se parcourt dans l'ordre de `stations`. Pour un trajet retour,
--  déclarez une seconde ligne (ex. west_return). La 1re gare doit avoir un
--  `depot` (point de mise en voie).
--
--  stations[i].stop : temps d'arrêt obligatoire en gare (secondes réelles)
--  stations[i].eta  : minutes (horloge du jeu) après le départ — horaires
--  (le prix des billets se calcule sur tout le réseau : voir Config.Tickets.pricing)
--  junctions       : aiguillages forcés à la mise en voie
--                     { track = 'TRAINS_OLD_WEST01', index = 2, enabled = true }
--                     (relevez track/index avec /sunnytrain_junction)
-- ----------------------------------------------------------------------------
Config.Routes = {
    west = {
        label       = "Blackwater → Riggs Station",
        color       = '#7b2d1d',
        stations = {
            { id = 'blackwater',    stop = 0,  eta = 0  },
            { id = 'riggs_station', stop = 0,  eta = 25 },
        },
        duration    = 12,                -- durée estimée affichée (minutes réelles)
        junctions   = {},
    },
    west_return = {
        label       = "Riggs Station → Blackwater",
        color       = '#7b2d1d',
        stations = {
            { id = 'riggs_station', stop = 0,  eta = 0  },
            { id = 'blackwater',    stop = 0,  eta = 25 },
        },
        duration    = 12,
        junctions   = {},
    },
    heartlands = {
        label       = "Valentine → Emerald Station → Rhodes → Saint Denis",
        color       = '#1f3d2b',
        stations = {
            { id = 'valentine',       stop = 0,  eta = 0   },
            { id = 'emerald_station', stop = 45, eta = 40  },
            { id = 'rhodes',          stop = 45, eta = 95  },
            { id = 'saint_denis',     stop = 0,  eta = 140 },
        },
        duration    = 20,
        junctions   = {},
    },
    northern = {
        label       = "Saint Denis → Annesburg",
        color       = '#2a3550',
        stations = {
            { id = 'saint_denis', stop = 0, eta = 0  },
            { id = 'annesburg',   stop = 0, eta = 70 },
        },
        duration    = 10,
        junctions   = {},
    },
    -- Liaison entre les Heartlands et l'Ouest (par Wallace Station dans le jeu).
    -- À VÉRIFIER en jeu : sens de l'aiguillage à Riggs Station.
    valley = {
        label       = "Valentine → Riggs Station → Blackwater",
        color       = '#5a4a1d',
        stations = {
            { id = 'valentine',     stop = 0,  eta = 0  },
            { id = 'riggs_station', stop = 45, eta = 50 },
            { id = 'blackwater',    stop = 0,  eta = 80 },
        },
        duration    = 16,
        junctions   = {},
    },
    valley_return = {
        label       = "Blackwater → Riggs Station → Valentine",
        color       = '#5a4a1d',
        stations = {
            { id = 'blackwater',    stop = 0,  eta = 0  },
            { id = 'riggs_station', stop = 45, eta = 30 },
            { id = 'valentine',     stop = 0,  eta = 80 },
        },
        duration    = 16,
        junctions   = {},
    },
}

-- ----------------------------------------------------------------------------
--  Catalogue du matériel roulant
--  La compagnie ne possède pas tout d'un coup : seuls les trains listés dans
--  Config.Fleet.starter sont fournis, le patron achète les autres (registre →
--  « Matériel & acquisitions »). Classés du plus modeste (tier 1) au plus
--  luxueux.
--
--  model        : « train config » RDR3 : hash (0x...) ou nom. Liste :
--                 alloc8or.re/rdr3/doc/enums/eTrainConfig.txt — À VÉRIFIER en
--                 jeu pour l'apparence exacte de chaque composition.
--  tier / category : rang et famille affichés au catalogue
--  price        : prix d'achat ($) — payé selon Config.Purchase
--  serviceTypes : types de missions acceptés (voir Config.MissionTypes)
--  routes       : lignes que ce train peut desservir en mission
--  maxSpeed     : vitesse max (m/s, 30 max) — sert aussi aux contrôles anti-triche
--  hold         : wagon de chargement (coffre de l'inventaire existant)
--  fuel         : false = aucun charbon nécessaire
--  coalPerKm    : charbon brûlé par kilomètre parcouru
-- ----------------------------------------------------------------------------
Config.Trains = {
    engine_only = {
        tier = 2, category = 'Locomotive', price = 1200,
        label         = "Locomotive de manœuvre n°1",
        model         = '0x3260CE89',   -- engine_config
        description   = 'Locomotive seule et son tender : convoyages et voyages rapides.',
        serviceTypes  = {},
        routes        = {},
        maxSpeed      = 20.0,
        hold          = { slots = 10, weight = 150000 },
        coalPerKm     = 1.5,
        allowMissions = false, allowFreeRun = true, allowRobbery = false,
        passengers    = false,
        wearPerRun    = 4,
    },
    western_freight = {
        tier = 3, category = 'Fret', price = 2500,
        label         = "Convoi de marchandises n°12",
        model         = '0x0392C83A',   -- Cargo Train 1
        description   = 'Wagons couverts et plateformes pour marchandises.',
        serviceTypes  = { 'freight', 'secure_convoy', 'risky' },
        routes        = { 'west', 'west_return', 'valley', 'valley_return' },
        maxSpeed      = 15.0,
        hold          = { slots = 30, weight = 1500000 },
        coalPerKm     = 2.0,
        allowMissions = true, allowFreeRun = true, allowRobbery = true,
        passengers    = false,
        wearPerRun    = 8,
    },
    lemoyne_freight = {
        tier = 4, category = 'Fret lourd', price = 4000,
        label         = "Convoi de fret lourd n°3",
        model         = '0x0660E567',   -- Cargo Train 2
        description   = 'Convoi lourd de marchandises et de fonds fédéraux.',
        serviceTypes  = { 'freight', 'government', 'secure_convoy', 'risky' },
        routes        = { 'heartlands', 'northern' },
        maxSpeed      = 16.0,
        hold          = { slots = 40, weight = 2500000 },
        coalPerKm     = 2.5,
        allowMissions = true, allowFreeRun = true, allowRobbery = true,
        passengers    = false,
        wearPerRun    = 9,
    },
    plains_mixed = {
        tier = 5, category = 'Mixte', price = 5000,
        label         = "Train mixte voyageurs et marchandises n°5",
        model         = '0x005E03AD',   -- Mixed Train 1
        description   = 'Voitures de voyageurs et wagons de marchandises.',
        serviceTypes  = { 'passengers', 'freight' },
        routes        = { 'west', 'west_return', 'valley', 'valley_return', 'heartlands', 'northern' },
        maxSpeed      = 17.0,
        hold          = { slots = 25, weight = 1200000 },
        coalPerKm     = 2.0,
        allowMissions = true, allowFreeRun = true, allowRobbery = true,
        passengers    = false,
        wearPerRun    = 7,
    },
    western_passenger = {
        tier = 6, category = 'Voyageurs', price = 6000,
        label         = "Train de voyageurs n°7",
        model         = '0x10461E19',   -- Passenger Train 1
        description   = 'Voitures de voyageurs, première et seconde classe.',
        serviceTypes  = { 'passengers', 'special' },
        routes        = { 'west', 'west_return', 'valley', 'valley_return' },
        maxSpeed      = 18.0,
        hold          = { slots = 15, weight = 500000 },
        coalPerKm     = 1.8,
        allowMissions = true, allowFreeRun = true, allowRobbery = true,
        passengers    = false,
        wearPerRun    = 6,
    },
    heartlands_express = {
        tier = 7, category = 'Express', price = 8500,
        label         = "Express de voyageurs n°9",
        model         = '0x1C043595',   -- Passenger Train 2
        description   = 'Express de voyageurs entre Valentine et Saint Denis.',
        serviceTypes  = { 'passengers', 'special', 'government' },
        routes        = { 'heartlands', 'northern' },
        maxSpeed      = 22.0,
        hold          = { slots = 15, weight = 500000 },
        coalPerKm     = 2.2,
        allowMissions = true, allowFreeRun = true, allowRobbery = true,
        passengers    = false,
        wearPerRun    = 5,
    },
    pullman_palace = {
        tier = 8, category = 'Luxe', price = 14000,
        label         = "Express de luxe n°11",
        model         = '0xDD920DAF',   -- Passenger Train 12 — À VÉRIFIER (voitures de luxe)
        description   = 'Voitures-salons, boiseries et velours : le fleuron de la compagnie.',
        serviceTypes  = { 'passengers', 'special', 'government' },
        routes        = { 'heartlands', 'northern', 'valley', 'valley_return' },
        maxSpeed      = 24.0,
        hold          = { slots = 20, weight = 600000 },
        coalPerKm     = 2.6,
        allowMissions = true, allowFreeRun = true, allowRobbery = true,
        passengers    = false,
        wearPerRun    = 4,
    },
}

-- ----------------------------------------------------------------------------
--  Flotte, achats, wagons et charbon
-- ----------------------------------------------------------------------------
Config.Fleet = {
    -- Trains fournis à la compagnie dès le départ (toujours possédés).
    starter = { 'western_freight' },
}

-- Paiement des achats de matériel. account :
--   'society' : compte de la société du job (qbr-management par défaut)
--   'cash' / 'bank' : argent du patron qui achète
-- society.system :
--   'qbr-management' : table management_menu + événements du boss menu
--   'custom'         : fonctions ci-dessous (ex. Job Creator sur le serveur principal)
Config.Purchase = {
    account   = 'society',
    sellRatio = 0.5,          -- revente : 50 % du prix d'achat (0 = revente désactivée)
    society = {
        system = 'qbr-management',
        -- Pour 'custom' : renvoyer le solde / true si le retrait a réussi.
        getBalance = function(job) return 0 end,
        remove     = function(job, amount) return false end,
        add        = function(job, amount) end,
    },
}

-- Wagon de chargement de chaque train = coffre de l'inventaire existant
-- (qbr-inventory, table stashitems). Il contient la cargaison des missions
-- et le charbon du tender.
Config.Hold = {
    enabled  = true,
    prefix   = 'sunnytrain_',   -- id des coffres (sans tiret : contrainte qbr-inventory)
    openDistance = 12.0,        -- distance max au train en circulation pour ouvrir son wagon
}

-- Charbon : sans charbon dans le wagon, le train n'avance pas.
Config.Fuel = {
    enabled       = true,
    item          = 'train_coal',
    minToStart    = 2,          -- charbon requis dans le wagon pour mettre en voie
    checkInterval = 10,         -- s entre deux relevés de distance (serveur)
}

-- ----------------------------------------------------------------------------
--  Voyage libre
--  Un employé en service peut sortir un train depuis une gare équipée d'un
--  dépôt, vers n'importe quelle gare reliée par le réseau : pas de mission,
--  pas de prime, pas d'arrêt imposé. Il remise le train quand il veut.
-- ----------------------------------------------------------------------------
Config.FreeTravel = {
    enabled        = true,
    announceDelays = { 0, 2, 5, 10 }, -- voyage sans départ programmé : départ dans N minutes (0 = immédiat)
    exitCabGrace   = 300,             -- s hors cabine avant remisage automatique (0 = jamais)
    wearFactor     = 0.5,             -- usure appliquée = wearPerRun du train × facteur
    parkRadius     = 80.0,            -- m autour du dépôt ou du quai d'une gare pour remiser (0 = partout)
}

-- ----------------------------------------------------------------------------
--  Départs programmés (heure RÉELLE du serveur)
--  Un cheminot (n'importe quel grade) programme un départ : gare, destination,
--  train (facultatif) et heure exacte. C'est la base de tout :
--    - le tableau des départs des guichets n'affiche QUE ces départs ;
--    - le guichet ne vend des billets QUE pour ces départs (gares du trajet) ;
--    - un voyage libre peut partir sur un départ programmé ;
--    - chaque départ envoie un avis aux voyageurs.
--  Un voyage sans horaire ou une mission crée automatiquement son départ.
-- ----------------------------------------------------------------------------
Config.Departures = {
    enabled        = true,
    slotStep       = 5,        -- minutes entre deux horaires proposés (14:00, 14:05...)
    slotCount      = 36,       -- nombre d'horaires proposés (36 × 5 min = 3 h)
    minLead        = 5,        -- délai minimal avant le premier horaire proposé (min)
    boardingWindow = 10,       -- min avant l'heure : statut « Embarquement »
    missionLead    = 2,        -- min : départ programmé automatiquement pour une mission
    maxPerPlayer   = 3,        -- départs programmés en attente par cheminot
    keepDeparted   = 5,        -- min d'affichage « Parti » au tableau
    expireAfter    = 30,       -- min après l'heure sans départ -> annulé automatiquement
    notify = {                 -- avis aux voyageurs envoyés
        created   = true,      -- départ programmé
        boarding  = true,      -- le train est à quai
        departed  = false,     -- le train a quitté la gare
        cancelled = true,      -- départ annulé
    },
    audience       = 'all',    -- 'all' : tous les joueurs | 'nearby' : autour de la gare
    nearbyRadius   = 800.0,
    duration       = 11000,    -- ms d'affichage d'un avis
    sound          = { name = 'SELECT', set = 'HUD_SHOP_SOUNDSET' },
}

-- ----------------------------------------------------------------------------
--  Missions
-- ----------------------------------------------------------------------------
Config.MissionTypes = {
    passengers    = { label = 'Transport de passagers' },
    freight       = { label = 'Transport de marchandises' },
    special       = { label = 'Transport spécial' },
    government    = { label = 'Transport gouvernemental' },
    secure_convoy = { label = 'Convoi sécurisé' },
    risky         = { label = 'Mission à risque' },
}

Config.MissionSettings = {
    cooldown         = 120,     -- s entre deux missions pour un même conducteur
    cancelCooldown   = 300,     -- s de pénalité après abandon
    speedTolerance   = 1.35,    -- tolérance sur maxSpeed pour le contrôle anti-téléportation
    spawnTimeout     = 30,      -- s pour que le client déclare le train mis en voie
    finishDeleteDelay = 5,      -- s avant la suppression du train en fin de run
    robbedFailDelete = 60,      -- s avant suppression d'un train dévalisé (mode 'fail')
}

-- Chaque mission est une commande d'une société (ou de la compagnie) :
-- company     : commanditaire affiché dans le registre
-- cargo       : items à charger dans le wagon du train AVANT la signature ;
--               ils sont prélevés du wagon au départ (livraison)
-- reward      : prime en cash versée à celui qui a lancé la mission
-- rewardPerStop : prime par gare intermédiaire desservie
-- rewardItems : items remis en plus à la fin, ex. { { item = 'train_crate_iron', amount = 2 } }
-- timeLimit   : minutes réelles ; au-delà, bonus perdu (0 = pas de limite)
-- onTimeBonus : bonus si terminé dans les temps
-- hardTimeout : minutes réelles avant échec automatique (0 = jamais)
-- robberyLoot : multiplicateur du butin en cas de braquage
Config.Missions = {
    -- Anciennes missions : remplacées par config/deliveries.lua lorsque activé.
    west_passengers = {
        label         = "Voyageurs : Blackwater → Riggs Station",
        company       = 'Sunny Pacific — service voyageurs',
        type          = 'passengers',
        route         = 'west',
        description   = 'Navette Blackwater — Riggs Station avec les voyageurs du jour.',
        cargo         = {},
        reward        = 350,
        rewardPerStop = 50,
        rewardItems   = {},
        timeLimit     = 20,
        onTimeBonus   = 75,
        hardTimeout   = 45,
        canBeRobbed   = true,
        robberyLoot   = 1.0,
    },
    west_freight = {
        label         = 'Livraison au comptoir de Riggs',
        company       = 'Comptoir agricole de Blackwater',
        type          = 'freight',
        route         = 'west',
        description   = 'Acheminer maïs et tabac jusqu\'à Riggs Station.',
        cargo         = { { item = 'train_crate_corn', amount = 20 }, { item = 'train_crate_tobacco', amount = 10 } },
        reward        = 500,
        rewardPerStop = 40,
        rewardItems   = {},
        timeLimit     = 25,
        onTimeBonus   = 60,
        hardTimeout   = 50,
        canBeRobbed   = true,
        robberyLoot   = 1.2,
    },
    west_return_passengers = {
        label         = "Voyageurs : Riggs Station → Blackwater",
        company       = 'Sunny Pacific — service voyageurs',
        type          = 'passengers',
        route         = 'west_return',
        description   = 'Ramener les voyageurs vers Blackwater.',
        cargo         = {},
        reward        = 350,
        rewardPerStop = 50,
        rewardItems   = {},
        timeLimit     = 20,
        onTimeBonus   = 75,
        hardTimeout   = 45,
        canBeRobbed   = false,
    },
    heartlands_mail = {
        label         = "Courrier et voyageurs : Valentine → Saint Denis",
        company       = 'Postes de New Hanover',
        type          = 'passengers',
        route         = 'heartlands',
        description   = 'Service régulier Valentine — Saint Denis.',
        cargo         = {},
        reward        = 600,
        rewardPerStop = 60,
        rewardItems   = {},
        timeLimit     = 30,
        onTimeBonus   = 100,
        hardTimeout   = 60,
        canBeRobbed   = true,
        robberyLoot   = 1.0,
    },
    federal_payroll = {
        label         = 'Solde fédérale',
        company       = 'Gouvernement fédéral',
        type          = 'government',
        route         = 'heartlands',
        description   = 'Acheminer la solde de l\'armée sous escorte jusqu\'à Saint Denis.',
        cargo         = { { item = 'train_payroll', amount = 2 } },
        reward        = 1100,
        rewardPerStop = 0,
        rewardItems   = {},
        timeLimit     = 30,
        onTimeBonus   = 150,
        hardTimeout   = 60,
        canBeRobbed   = true,
        robberyLoot   = 2.5,
    },
    annesburg_coal = {
        label         = 'Ravitaillement de la mine',
        company       = 'Mines d\'Annesburg',
        type          = 'risky',
        route         = 'northern',
        description   = 'Livrer fer et ferraille à la mine. Ligne isolée, bandes armées signalées.',
        cargo         = { { item = 'train_crate_iron', amount = 15 }, { item = 'train_crate_scrap', amount = 10 } },
        reward        = 800,
        rewardPerStop = 0,
        rewardItems   = { { item = 'train_coal', amount = 10 } },
        timeLimit     = 20,
        onTimeBonus   = 100,
        hardTimeout   = 40,
        canBeRobbed   = true,
        robberyLoot   = 1.5,
    },
}

-- ----------------------------------------------------------------------------
--  Billets
--  L'item doit exister dans l'inventaire du serveur. Si registerItem = true
--  et que l'item n'existe pas, Sunny_train l'ajoute via exports qbr-core:AddItem
--  (simple déclaration d'item, aucun inventaire n'est créé).
-- ----------------------------------------------------------------------------
Config.Tickets = {
    enabled         = true,
    item            = 'train_ticket',
    registerItem    = true,
    itemDefinition  = {
        name = 'train_ticket', label = 'Billet de train', weight = 5, type = 'item',
        image = 'train_ticket.png', -- fourni dans installation/images
        unique = true, useable = true, shouldClose = true, combinable = nil, level = 0,
        description = 'Titre de transport de la compagnie ferroviaire.',
    },
    classes = {
        { id = 'third',  label = 'Troisième classe', multiplier = 1.0, description = 'Banquettes de bois, voiture commune.' },
        { id = 'second', label = 'Seconde classe',   multiplier = 1.6, description = 'Sièges rembourrés, compartiment chauffé.' },
        { id = 'first',  label = 'Première classe',  multiplier = 2.5, description = 'Voiture-salon, service à la place.' },
    },
    -- Tarif : toutes les gares sont proposées depuis n'importe quel guichet.
    -- Le prix dépend de la distance parcourue SUR LE RÉSEAU (plus court
    -- chemin entre les gares, toutes lignes confondues, dans les deux sens).
    --   prix = (base + perKm × km) × multiplicateur de classe, arrondi à roundTo
    -- Exemple (config par défaut, 3e classe) : Saint Denis → Annesburg ≈ 2,5 km
    -- revient moins cher que Saint Denis → Valentine ≈ 5 km.
    pricing = {
        base      = 1.00,      -- prise en charge ($)
        perKm     = 0.60,      -- $ par kilomètre de voie
        minimum   = 1.50,      -- prix plancher (3e classe)
        roundTo   = 0.05,      -- arrondi
        -- Gare non reliée par le réseau : distance à vol d'oiseau × facteur
        -- (billet « avec correspondance »). false = ces gares ne sont pas vendues.
        unconnectedFactor = 1.35,
    },
    validityMinutes = 180,     -- minutes de validité après l'heure du départ programmé
    singleUse       = true,    -- un billet composté ne peut plus être utilisé
    nominative      = false,   -- true : le billet n'est valable que pour l'acheteur
    maxActive       = 4,       -- billets valides simultanés par personnage
    serialPrefix    = 'SP',
    purgeAfterDays  = 14,      -- nettoyage BDD des billets expirés
}

-- ----------------------------------------------------------------------------
--  Maintenance (état du matériel, persistant en BDD)
-- ----------------------------------------------------------------------------
Config.Maintenance = {
    enabled = true,
    -- Seuils d'état (en % d'état général)
    thresholds = {
        needsMaintenance = 60,   -- < 60 : Maintenance nécessaire
        damaged          = 30,   -- < 30 : Endommagé
    },
    -- États qui empêchent de prendre le train en mission
    blockedStates = { damaged = true, out_of_service = true },
    requireInspection   = true,  -- inspection récente requise avant réparation
    inspectionValidity  = 900,   -- s
    inspectDuration     = 6000,  -- ms (animation)
    restoreMinCondition = 60,    -- % minimum pour remettre en service
    -- Opérations de réparation : items retirés de l'inventaire existant
    repairs = {
        {
            id = 'routine', label = 'Entretien courant',
            description = 'Graissage, purge de la chaudière, serrage.',
            items = { { name = 'coal', amount = 2 }, { name = 'metalscrap', amount = 1 } },
            restore = 20, duration = 8000,
        },
        {
            id = 'mechanical', label = 'Réparation mécanique',
            description = 'Remplacement de bielles et de garnitures.',
            items = { { name = 'iron', amount = 3 }, { name = 'metalscrap', amount = 3 } },
            restore = 45, duration = 14000,
        },
        {
            id = 'overhaul', label = 'Révision complète',
            description = 'Remise à neuf de la locomotive et des voitures.',
            items = { { name = 'iron', amount = 6 }, { name = 'copper', amount = 2 }, { name = 'coal', amount = 4 } },
            restore = 100, duration = 20000,
        },
    },
    scenario = 'WORLD_HUMAN_CROUCH_INSPECT',   -- scénario joué pendant les travaux (nil = aucun)
}

-- ----------------------------------------------------------------------------
--  Braquages
-- ----------------------------------------------------------------------------
Config.Robbery = {
    enabled          = true,
    minPolice        = 2,                          -- forces de l'ordre en service requises
    policeJobs       = { 'police', 'sheriff' },
    blacklistedJobs  = { chemindefer = true, police = true, sheriff = true },
    requireWeapon    = true,
    maxTrainSpeed    = 3.0,                        -- m/s : le train doit être quasi à l'arrêt
    interactDistance = 8.0,                        -- distance au conducteur / à la locomotive
    holdKey          = 0x760A9C6F,                 -- G
    duration         = 90,                         -- s pour tenir la position
    cancelRadius     = 45.0,                       -- au-delà, le braquage échoue
    trainCooldown    = 1800,                       -- s avant de pouvoir re-braquer ce train
    globalCooldown   = 600,                        -- s entre deux braquages sur le serveur
    runOutcome       = 'penalty',                  -- 'penalty' (run continue) | 'fail'
    rewardMultiplier = 0.4,                        -- prime du conducteur après braquage (penalty)
    conditionDamage  = 15,                         -- usure infligée au train
    cargoShare       = 0.5,                        -- part de la cargaison du convoi remise au braqueur
    loot = {
        account = 'cash',
        cash    = { min = 120, max = 380 },        -- multiplié par mission.robberyLoot
        items   = {
            -- { name = 'moneybag', min = 1, max = 1, chance = 35 },
        },
    },
}

-- ----------------------------------------------------------------------------
--  Dispatch — Sunny_train ne fournit PAS de dispatch.
--  system :
--    'fallback' : simple télégramme + blip temporaire aux jobs listés
--                 (à utiliser tant qu'aucun dispatch n'est branché)
--    'event'    : TriggerEvent / TriggerClientEvent vers votre dispatch
--    'export'   : exports[resource][method](data)
--    'custom'   : Config.Dispatch.custom(data) (serveur)
--    'none'     : aucune alerte
--  data = { code, title, message, coords = {x,y,z}, jobs, train, mission, route }
-- ----------------------------------------------------------------------------
Config.Dispatch = {
    enabled = true,
    system  = 'fallback',
    jobs    = { 'police', 'sheriff' },
    code    = '10-90',
    event   = { name = 'my_dispatch:server:alert', side = 'server' }, -- side : 'server' | 'client'
    export  = { resource = 'my_dispatch', method = 'SendAlert' },
    custom  = function(data)
        -- Exemple : exports['my_dispatch']:SendAlert(data)
    end,
    fallback = {
        blipSprite = 'blip_ambient_law',  -- À VÉRIFIER
        blipRadius = 120.0,
        blipDuration = 120,               -- s
    },
}

-- ----------------------------------------------------------------------------
--  Sécurité serveur
-- ----------------------------------------------------------------------------
Config.Security = {
    interactionMargin = 3.0,      -- tolérance ajoutée aux rayons d'interaction
    rateLimit = 350,              -- ms minimum entre deux requêtes identiques
    burstLimit = 25,              -- requêtes max par fenêtre de 5 s
    dropOnExploit = false,        -- expulser en cas de tentative manifeste
    logExploits = true,
}

-- ----------------------------------------------------------------------------
--  Crochets (optionnels, serveur) — pour brancher société / logs / etc.
--  Aucune gestion de société n'est faite par Sunny_train.
-- ----------------------------------------------------------------------------
Config.Hooks = {
    onMissionCompleted = nil,  -- function(source, runSummary, reward) end
    onTicketSold       = nil,  -- function(source, ticket) end
    onRobbery          = nil,  -- function(robberSource, runSummary, loot) end
}
