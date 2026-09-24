Config = {}

Config.Debug = false

Config.Arena = {
    name    = 'Rodéo',
    center  = vector3(526.3021, -233.0454, 146.8617),
    heading = 260.3087,

    radius = 10.0,
}

Config.Desk = {
    coords   = vector4(513.8974, -241.9083, 145.2943, 292.1214),
    radius   = 1.4,
    distance = 2.5,
    npc      = true,
    models   = { 'u_m_m_wtccowboy_04' },
}

Config.Blip = {
    enabled = true,
    sprite  = 'blip_ambient_horse',
    scale   = 0.2,
    label   = 'Rodéo',
}

Config.Buffalo = {

    models    = {
        'a_c_horse_mustang_wildbay', 'a_c_horse_mustang_buckskin', 'a_c_horse_mustang_grullodun',
        'a_c_horse_mustang_tigerstripedbay', 'a_c_horse_americanpaint_overo',
    },
    cleanupMs = 5000,
    fadeMs    = 800,
}

Config.Mount = {
    native    = true,
    seat      = -1,

    driveWith = 'rider',

    wild = true,
}

Config.Seat = {
    bone     = 0,
    offset   = vector3(0.0, -0.15, 0.35),
    rotation = vector3(0.0, 0.0, 0.0),

    anims = {
        { dict = 'amb_rest@world_human_sit_ground@male_a@base', name = 'base' },
        { dict = 'amb_rest@prop_human_seat_chair@male_a@base',  name = 'base' },
    },
}

Config.Camera = {
    enabled    = true,
    back       = 5.5,
    side       = 2.4,
    height     = 1.3,
    lookHeight = 0.9,
    fov        = 55.0,
    follow     = 5.0,

    turnFollow = 1.5,
    zFollow    = 1.5,
}

Config.UI = {
    Sound  = true,
    Volume = 0.35,
}

Config.Price    = 5
Config.Cooldown = 20
Config.MinRideMs = 3000
Config.Countdown = 3

Config.Ride = {
    MaxSeconds   = 20,
    GripStart    = 100.0,
    GripGain     = 10.0,
    GripFastGain = 5.0,
    GripWrong    = 25.0,
    GripTimeout  = 30.0,

    FailPenaltyMs    = 2000,
    TimeoutPenaltyMs = 3000,
    DrainBase    = 1.5,
    DrainPerMin  = 1.5,
    AnswerGraceMs = 250,

    FirstChallengeMs = 1000,

    RampSeconds  = 17,
    SeqStart     = 2,
    SeqEvery     = 12,
    SeqMax       = 5,
    BaseStart    = 1500,
    BaseMin      = 1000,
    PerArrowStart = 450,
    PerArrowMin  = 330,
    GapStart     = 700,
    GapMin       = 250,
}

Config.Bucking = {
    speedStart = 3.6,
    speedMax   = 3.6,
    hopMin     = 1200,
    hopMax     = 2600,
    hopPower   = 3.0,
}

Config.Wild = {
    enabled     = true,
    stuckMs     = 3500,
    startupGraceMs = 3500,

    tilt        = false,

    gapStart    = 2000,
    gapMin      = 900,
    moveCooldownMs = 1100,

    onChallenge = { 'rear', 'buck', 'twist', 'spin' },
    onMistake   = 'violent',

    moves = {
        rear    = { weight = 3, ms = 1500, action = 5, pitch = 34.0,  roll = 0.0,  turn = 0.0,    hop = 0.6, repeats = 4, stop = false },
        buck    = { weight = 2, ms = 1500, action = 1, pitch = -22.0, roll = 10.0, turn = 0.0,    hop = 1.2, repeats = 4, stop = false },
        twist   = { weight = 3, ms = 1100, action = 8, pitch = -8.0,  roll = 16.0, turn = 150.0,  hop = 0.9, repeats = 3, stop = false },
        spin    = { weight = 3, ms = 1200, action = 8, pitch = -8.0,  roll = 16.0, turn = -220.0, hop = 1.0, repeats = 3, stop = false },
        violent = { weight = 0, ms = 2400, action = 5, pitch = -26.0, roll = 18.0, turn = 0.0,    hop = 1.9, repeats = 5, stop = false },
    },
}

Config.Lean = {
    enabled = true,
    swayMax = 16.0,
    failPush = 26.0,
}

Config.Fall = {
    onTimeUp = true,
    protectMs = 3500,
    ragdollMs = 4500,
    throwSpeed = 4.5,
}

Config.XP = { perSecond = 0.25, perCombo = 2.0, maxBonus = 5 }

Config.Levels = {
    { xp = 0,    title = 'Bleu-bec' },
    { xp = 200,  title = 'Apprenti cow-boy' },
    { xp = 600,  title = 'Cavalier' },
    { xp = 1500, title = 'Dompteur' },
    { xp = 3500, title = 'Champion' },
    { xp = 7500, title = 'Légende du rodéo' },
}

Config.TopSize = 15
Config.AnnounceRecord = true

Config.AdminGroups = { 'god', 'admin' }
