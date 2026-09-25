Config = {}

Config.ThrowsPerRound = 3
Config.Rounds = 5
Config.MaxPlayers = 2

Config.Lobby = {
    timeout = 120,
}

Config.Turn = {
    timeout = 45,
    afterThrowMs = 1600,
    positionTolerance = 3.0,
    leaveDistance = 30.0,
    endScreenMs = 4500,
}

Config.Score = {
    ringer = 3,
    leaner = 2,
    zones = {
        { distance = 0.75, points = 1, label = 'PROCHE DU PIQUET' },
    },
}

Config.Money = {
    account = 'cash',
}

Config.Bet = {
    enabled = true,
    min = 10,
    max = 1000,
    houseCut = 0.0,
}

Config.ThrowForce = 10.0
Config.ThrowForceMin = 1.2
Config.ThrowHeight = 2.0
Config.ThrowGravity = true

Config.Physics = {
    releaseHeight = 0.95,
    releaseForward = 0.45,
    restHeight = 0.012,
    slide = 0.035,
    slideRandom = 0.35,
    bounce = 0.035,
    leanerChance = 0.30,
    spinMin = 300.0,
    spinMax = 620.0,
}

Config.Accuracy = {
    aimNoiseDeg = 0.55,
    powerNoise = 0.012,
}

Config.Aim = {
    maxAngle = 10.0,
    speed = 7.0,
}

Config.Power = {
    cycleMs = 1500,
}

Config.HorseshoeModel = 'p_horseshoe01x'
Config.StakeModel = 'p_horseshoestake01x'

Config.Shoe = {
    radius = 0.075,
    leg = 0.085,
    inset = 0.012,
    steel = 0.011,
    pitch = 0.0,
    roll = 0.0,
    yaw = 0.0,
    zOffset = 0.0,
    handBone = 'PH_R_Hand',
    handPos = vector3(0.02, 0.0, -0.02),
    handRot = vector3(0.0, 90.0, 0.0),
}

Config.Stake = {
    spawn = true,
    height = 0.35,
    radius = 0.018,
    zOffset = 0.0,
}

Config.Animations = {
    { dict = 'mech_weapons_thrown@base_str', name = 'throw_m_fb_forward', releaseAt = 0.40 },
    { dict = 'amb_camp@world_camp_jack_throw_rocks_casual@male_a@idle_a', name = 'idle_a', releaseAt = 0.50 },
    { dict = 'mech_inventory@eating@multi_bite@sphere_d8-4_fruit', name = 'quick_right_hand_throw', releaseAt = 0.50 },
}
Config.AnimReleaseMin = 250
Config.AnimReleaseMax = 1400

Config.UI = {
    enabled = true,
    sound = true,
    volume = 0.45,
    popupMs = 2600,
}

Config.Interaction = {
    target = true,
    radius = 1.4,
    distance = 2.5,
    command = 'fer',
}

Config.Controls = {
    throw = 0xD9D0E1C0,
    left = 0xA65EBAB4,
    right = 0xDEB34313,
    quit = 0x156F7119,
}

Config.Leaderboard = {
    enabled = true,
    size = 10,
    command = 'fertop',
}

Config.Blip = {
    enabled = true,
    sprite = 1938782895,
    scale = 0.2,
    label = 'Lancer de fer',
}

Config.SyncDistance = 90.0

Config.HorseshoePits = {
    {
        id = 'terrain1',
        label = 'Terrain de lancer de fer',
        throwPoints = {
            vector3(-822.3028, -1386.4152, 42.6672),
            vector3(-819.9376, -1386.3729, 42.6690),
            vector3(-824.6340, -1388.0596, 42.6490),
            vector3(-823.2286, -1389.5513, 42.6271),
            vector3(-819.7090, -1390.0526, 42.6228),
        },
        stakePoint = vector3(-822.9427, -1378.7867, 42.5482),
        heading = 184.0727,
        maxPlayers = 2,
        npc = {
            coords = vector4(-817.6855, -1383.9614, 43.6581, 86.0928),
            model = 'u_m_m_wtccowboy_04',
        },
    },
    {
        enabled = false, -- Passer a true une fois les positions configurees.
        id = 'terrain2',
        label = 'Terrain de lancer de fer 2',
        -- Positions de lancer : une par manche, reutilisees en boucle.
        throwPoints = {
            vector3(0.0, 0.0, 0.0), -- Manche 1 : x, y, z du sol.
            vector3(0.0, 0.0, 0.0), -- Manche 2.
            vector3(0.0, 0.0, 0.0), -- Manche 3.
            vector3(0.0, 0.0, 0.0), -- Manche 4.
            vector3(0.0, 0.0, 0.0), -- Manche 5.
        },
        stakePoint = vector3(0.0, 0.0, 0.0), -- Position du piquet au sol.
        heading = 0.0, -- Orientation du piquet en degres ; visee automatique vers lui.
        maxPlayers = 2,
        npc = {
            coords = vector4(0.0, 0.0, 0.0, 0.0), -- PNJ : x, y, z, orientation.
            model = 'u_m_m_wtccowboy_04',
        },
    },
}
