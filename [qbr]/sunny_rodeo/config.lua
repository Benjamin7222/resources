Config = {}

Config.Debug = false -- true : affiche les zones ox_target

-- ARENE ------------------------------------------------------------------
-- Positions relevées avec /rodeopos (vector4 = x, y, z, cap).
Config.Arena = {
    name    = 'Rodéo de Valentine',
    center  = vector3(-236.9150, 664.2724, 113.2901), -- le buffle apparaît ici
    heading = 345.3426,
    -- CAGE INVISIBLE : l'animal ne peut jamais dépasser ce contour (il glisse le long des bords).
    -- Les points sont les coins de l'enclos, DANS L'ORDRE en faisant le tour (convexe, 3 points minimum).
    -- Réglage en jeu : /rodeocage = afficher/masquer le contour, /rodeocage clear = tout effacer,
    -- /rodeocage add = ajouter ta position comme coin. La liste à coller ici est donnée dans le chat / F8.
    cage = {
        margin = 1.3, -- marge intérieure : l'animal a une épaisseur, son centre reste à cette distance du bord (0.8 le laissait toucher la vraie barrière)
        points = {
            vector2(-236.2515, 673.4259),
            vector2(-244.0889, 663.7153),
            vector2(-236.6928, 657.3569),
            vector2(-228.2558, 667.3702),
        },
    },
}

-- Le maître du rodéo : c'est lui qu'on cible (ox_target) pour monter ou voir le classement.
Config.Desk = {
    coords   = vector4(-237.6835, 656.2724, 113.3208, 145.5969),
    radius   = 1.4,   -- taille de la zone ox_target
    distance = 2.5,   -- distance d'interaction
    npc      = true,  -- false = pas de personnage, la zone reste
    -- modèles candidats (le premier qui existe dans le jeu est utilisé)
    models   = { 'u_m_m_valbartender_01', 'a_m_m_valfarmer_01', 'a_m_m_farmer_01' },
}

Config.Blip = {
    enabled = true,
    sprite  = 'blip_ambient_horse', -- nom de sprite converti en hash
    scale   = 0.2,
    label   = 'Rodéo',
}

-- BUFFLE -----------------------------------------------------------------
Config.Buffalo = {
    -- modèles candidats (le premier qui existe dans le jeu est utilisé)
    -- TEST : cheval sauvage d'abord. Pour revenir au buffle, mets 'a_c_buffalo_01' en premier.
    models    = {
        'a_c_horse_mustang_wildbay', 'a_c_horse_mustang_buckskin', 'a_c_horse_mustang_grullodun',
        'a_c_horse_mustang_tigerstripedbay', 'a_c_horse_americanpaint_overo',
        'a_c_buffalo_01', 'a_c_buffalo_tatanka_01', 'a_c_bull_01',
    },
    cleanupMs = 5000, -- après le tour, le buffle s'éloigne ce temps (ms) puis disparaît
    fadeMs    = 800,  -- durée du fondu avant suppression (0 = disparition instantanée)
}

-- MONTE ---------------------------------------------------------------------
-- Avec un CHEVAL, le joueur est vraiment mis EN SELLE (SetPedOntoMount) : c'est l'animation de monte
-- de base de RDR2, et le cabrage / la chute sont ceux du jeu (TaskHorseAction). Si la monte échoue
-- (ou si l'animal n'est pas un cheval, ex. le buffle), on retombe sur le mode « attaché + pose »
-- de Config.Seat ci-dessous.
Config.Mount = {
    native    = true,     -- false = toujours le mode attaché + pose
    seat      = -1,       -- -1 = place du cavalier
    -- qui reçoit l'ordre de courir : 'horse' (le cheval) ou 'rider' (le cavalier, le cheval suit).
    -- À changer en direct avec /rodeodrive horse|rider si le cheval ne bouge pas.
    driveWith = 'horse',
    -- CAPTURE : le cheval est marqué « sauvage » (_SET_ANIMAL_IS_WILD) une fois le joueur en selle. Le jeu joue alors
    -- SON animation de cheval sauvage qu'on monte (il se cabre, rue, s'agite tout seul) : on ne lui donne plus d'ordres
    -- (ni course, ni mouvements du script), sinon on casserait l'animation. Le cavalier ne peut pas être jeté par le
    -- cheval : la chute vient du mini-jeu. Si le cheval reste immobile malgré tout (Config.Wild.stuckMs), on repasse
    -- sur les mouvements du script. false = toujours les mouvements du script. En jeu : /rodeowild on|off
    wild = true,
}

-- SIEGE DU CAVALIER (mode de secours : attaché + pose) ------------------------
-- Le joueur est attaché au dos de l'animal. Ces valeurs sont à régler EN JEU :
--   /rodeoseat <x> <y> <z> [rx ry rz]   modifie le décalage en direct (pendant un tour)
--   /rodeopose <dict> <nom>             teste une animation de pose (pendant un tour)
Config.Seat = {
    bone     = 0,                        -- index d'os, ou nom d'os (chaîne) ; 0 = origine du buffle
    offset   = vector3(0.0, -0.15, 0.35), -- x = droite, y = avant, z = haut (0.75 faisait « voler » le cavalier sur un cheval)
    rotation = vector3(0.0, 0.0, 0.0),
    -- animations de pose essayées dans l'ordre (la première qui se charge est jouée)
    anims = {
        { dict = 'amb_rest@world_human_sit_ground@male_a@base', name = 'base' },
        { dict = 'amb_rest@prop_human_seat_chair@male_a@base',  name = 'base' },
    },
}

-- CAMERA -----------------------------------------------------------------
Config.Camera = {
    enabled    = true,  -- false = caméra normale du jeu
    back       = 5.5,   -- recul derrière le buffle
    side       = 2.4,   -- décalage latéral
    height     = 2.3,   -- hauteur
    lookHeight = 1.0,
    fov        = 55.0,
    follow     = 5.0,   -- vitesse de suivi (plus grand = plus nerveux)
    -- la caméra ne tremble jamais : elle ignore les sauts et rattrape le cap / la hauteur de l'animal en douceur
    turnFollow = 1.5,   -- vitesse de rattrapage du cap (plus petit = plus lent, plus stable)
    zFollow    = 1.5,   -- vitesse de rattrapage de la hauteur
}

-- INTERFACE --------------------------------------------------------------
Config.UI = {
    Sound  = true,   -- bruitages de l'interface (déclic, erreur, battements de cœur...)
    Volume = 0.35,   -- 0.0 à 1.0
}

-- TOUR -------------------------------------------------------------------
Config.Price    = 5     -- prix d'entrée en $ (cash), 0 = gratuit
Config.Cooldown = 20    -- secondes d'attente entre deux tours (par personnage)
Config.MinRideMs = 3000 -- en dessous, le tour n'est pas compté au classement
Config.Countdown = 3

Config.Ride = {
    MaxSeconds   = 35,    -- DURÉE DE LA MANCHE (s) : enchaîne un maximum d'épreuves avant la fin du chrono
    GripStart    = 100.0, -- la « prise » du cavalier (0 = chute)
    GripGain     = 10.0,  -- séquence réussie
    GripFastGain = 5.0,   -- bonus si réussie en moins de la moitié du temps
    GripWrong    = 25.0,  -- mauvaise flèche
    GripTimeout  = 30.0,  -- temps écoulé
    -- Une erreur RETIRE du temps au chrono (il reste moins de temps pour enchaîner) : mauvaise flèche / temps écoulé (ms)
    FailPenaltyMs    = 2000,
    TimeoutPenaltyMs = 3000,
    DrainBase    = 1.5,   -- perte de prise par seconde...
    DrainPerMin  = 1.5,   -- ...augmentée de ça à chaque minute passée
    AnswerGraceMs = 250,  -- tolérance réseau/NUI

    -- Les épreuves s'ENCHAÎNENT : la suivante démarre dès que la précédente est finie (GapStart -> GapMin entre les deux).
    -- Le score = nombre d'épreuves réussies pendant la manche.
    FirstChallengeMs = 1000,
    -- difficulté : monte de 0 à 1 sur RampSeconds (= la manche)
    RampSeconds  = 30,
    SeqStart     = 2,     -- nombre de flèches au début
    SeqEvery     = 12,    -- +1 flèche toutes les N secondes
    SeqMax       = 5,
    BaseStart    = 1500,  -- temps de base (ms) au début -> BaseMin
    BaseMin      = 1000,
    PerArrowStart = 450,  -- temps par flèche (ms) au début -> PerArrowMin
    PerArrowMin  = 330,
    GapStart     = 700,   -- pause entre deux épreuves (ms) -> GapMin
    GapMin       = 250,
}

-- Mouvements du buffle
Config.Bucking = {
    speedStart = 2.0,     -- allure de course (1 pas, 2 trot, 3 galop)
    speedMax   = 3.0,
    hopMin     = 1200,    -- sauts spontanés toutes les X à Y ms
    hopMax     = 2600,
    hopPower   = 2.0,     -- vitesse verticale du saut (mode de secours seulement : en selle, pas de saut forcé)
}

-- Mouvements de cheval sauvage. Un mouvement démarre :
--   - à chaque nouvelle séquence de flèches (Config.Wild.onChallenge, un tiré au hasard)
--   - sur une erreur (Config.Wild.onMistake, toujours violent)
--   - spontanément, de plus en plus souvent avec la difficulté (gapStart -> gapMin)
-- Champs d'un mouvement :
--   weight  poids du tirage spontané      ms      durée totale (ms)
--   action  ACTION DE CHEVAL DE BASE du jeu (TaskHorseAction) quand le joueur est en selle :
--             1 ou 5 = se cabre · 3 = arrêt net · 8 = dérapage · 2 = jette le cavalier
--   hop     multiple de Config.Bucking.hopPower à chaque cycle (ignoré si `action` est jouée)
--   repeats nombre de cycles (ruades)     stop    l'animal s'arrête pendant le mouvement
--   turn    pivotement (degrés, sens aléatoire)
--   pitch / roll  inclinaison forcée : mode de secours « attaché » ET Config.Wild.tilt = true (en selle, le jeu anime)
Config.Wild = {
    enabled     = true,
    stuckMs     = 3500,   -- capture (Config.Mount.wild) : cheval quasi immobile aussi longtemps = on le relance, puis on passe au script
    steerRange  = 4.0,    -- capture : à moins de X m du bord de la cage (plus s'il va vite), le cheval qui fonce vers le mur pivote vers l'intérieur...
    steerRate   = 140.0,  -- ...à cette vitesse de pivotement au minimum (degrés/s ; il tourne plus vite si le mur est proche)
    unstickMs   = 1500,   -- capture : cheval immobile aussi longtemps contre un bord = on le décolle de 1,5 m vers le centre
    riderFlipMs = 1000,   -- capture : cavalier à l'envers / en ragdoll aussi longtemps sur le cheval = chute
    tilt        = false,  -- true = incline le cheval de force (pitch/roll) hors selle ; désactivé : rendu saccadé
    -- (en selle, les actions natives ci-dessous suffisent)
    gapStart    = 4500,   -- pause entre deux mouvements spontanés (ms)...
    gapMin      = 1800,   -- ...qui se réduit jusqu'à cette valeur
    onChallenge = { 'rear', 'buck', 'twist' },
    onMistake   = 'violent',
    moves = {
        rear    = { weight = 3, ms = 2400, action = 5, pitch = 34.0,  roll = 0.0,  turn = 0.0,   hop = 0.6, repeats = 1, stop = true  },
        buck    = { weight = 4, ms = 2400, action = 1, pitch = -22.0, roll = 10.0, turn = 0.0,   hop = 1.2, repeats = 2, stop = true  },
        twist   = { weight = 2, ms = 1500, action = 8, pitch = -8.0,  roll = 16.0, turn = 150.0, hop = 0.9, repeats = 1, stop = true  },
        violent = { weight = 0, ms = 2400, action = 5, pitch = -26.0, roll = 18.0, turn = 0.0,   hop = 1.9, repeats = 3, stop = false },
    },
}

-- Inclinaison visible du cavalier (rattache le joueur à chaque image ; false = fixe)
Config.Lean = {
    enabled = true,
    swayMax = 16.0,       -- degrés de balancement quand la prise est faible
    failPush = 26.0,      -- degrés d'inclinaison brusque sur une erreur
}

-- Chute : le joueur est éjecté et reste invincible ce temps (ms)
Config.Fall = {
    onTimeUp = true,   -- true = le cheval jette aussi le cavalier quand les 35 s sont écoulées ; false = descente calme
    protectMs = 3500,
    ragdollMs = 4500,
    throwSpeed = 4.5,
}

-- SCORE / NIVEAU ---------------------------------------------------------
-- Le SCORE d'une manche = nombre d'épreuves réussies (c'est lui qui fait le classement).
-- XP d'une manche = secondes * perSecond + épreuves réussies * perCombo (+ bonus si la manche va jusqu'au bout)
Config.XP = { perSecond = 0.5, perCombo = 5.0, maxBonus = 15 }   -- perCombo = par épreuve réussie ; maxBonus = manche menée jusqu'au bout

-- Le niveau dépend de l'XP totale (1er palier = niveau 1). Ajoute autant de paliers que tu veux.
Config.Levels = {
    { xp = 0,    title = 'Bleu-bec' },
    { xp = 100,  title = 'Apprenti cow-boy' },
    { xp = 300,  title = 'Cavalier' },
    { xp = 700,  title = 'Dompteur' },
    { xp = 1500, title = 'Champion' },
    { xp = 3000, title = 'Légende du rodéo' },
}

-- Gains d'argent (en $) : secondes * perSecond, plafonné à max ; bonus si record personnel battu
Config.Reward = { perCombo = 0.5, max = 15.0, recordBonus = 2.0 }   -- perCombo = $ par épreuve réussie (plafonné à max)

Config.TopSize = 15           -- lignes affichées dans le classement
Config.KeepRideDays = 60      -- historique des tours conservé (le classement 7 jours en dépend)
Config.AnnounceRecord = true  -- annonce à tous quand quelqu'un prend la 1re place

-- Discord : uniquement les nouveaux records (laisser '' pour désactiver)
Config.Webhook = ''
Config.WebhookName = 'Sunny Rodéo'

-- Permission pour /rodeoreset (remet le classement à zéro)
Config.AdminGroups = { 'god', 'admin' }
