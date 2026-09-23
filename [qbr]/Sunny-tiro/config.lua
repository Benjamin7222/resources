Config = {}

Config.Start = vector3(-3676.7964, -2588.6494, -13.7788)
Config.Blip = { Enabled = true, Sprite = 202506373, Name = 'Stand de tir', Scale = 0.8 }
Config.PlayerStart = vector4(-3672.0601, -2586.5632, -13.7322, 352.0440)

Config.GameDuration = 15
Config.MaxShots = 12
Config.FinalTargetDuration = 3
Config.MovementVariation = { MinSpeed = 0.85, MaxSpeed = 1.35 }

Config.Cooldown = 0

Config.ModelLoadTimeout = 5000
Config.SetupTimeout = 35
Config.WalkTimeout = 12000
Config.WalkSpeed = 1.0
Config.ArrivalRadius = 0.45
Config.Countdown = 3
Config.CountdownSoundVolume = 0.25
Config.PlayRadius = 20.0
Config.StartRadius = 4.0
Config.Debug = false
Config.BottleModel = 'p_bottle001x'

Config.TargetArrow = {
    Enabled = true,
    Duration = 0,
    Height = 0.25
}

Config.Bottles = {
    [1] = {
        Coords = vector3(-3673.938232421875, -2581.338623046875, -14.02236652374267),
        Model = 'p_bottle001x'
    },
    [2] = {
        Coords = vector3(-3671.119873046875, -2581.778076171875, -14.02236652374267),
        Model = 'p_bottle001x'
    },
    [3] = {
        Coords = vector3(-3669.6646, -2575.8257, -14.7289),
        Model = 's_confedtarget',
        Heading = 169.4577
    },
    [4] = {
        Coords = vector3(-3674.5376, -2575.0137, -14.7295),
        Model = 's_confedtarget',
        Heading = 173.4379
    },
    [5] = {
        Coords = vector3(-3668.5847, -2579.3572, -14.7242),
        Model = 's_confedtarget',
        Heading = 185.9984
    },
    [6] = {
        Coords = vector3(-3671.702392578125, -2573.61572265625, -11.92096900939941),
        Model = 'p_target02x',
        Movement = { Axis = 'vertical', Amplitude = 1.0, Period = 2.5, Direction = 1 }
    },
    [7] = {
        Coords = vector3(-3669.242431640625, -2573.582275390625, -12.84099006652832),
        Model = 'p_target02x',
        Movement = { Axis = 'vertical', Amplitude = 1.0, Period = 2.5, Direction = -1 }
    },
    [8] = {
        Coords = vector3(-3671.702392578125, -2573.61572265625, -11.92096900939941),
        Model = 'p_targetarchery01x',
        Movement = { Amplitude = 1.0, Period = 2.5, Direction = 1 }
    },
    [9] = {
        Coords = vector3(-3669.242431640625, -2573.582275390625, -12.84099006652832),
        Model = 'p_targetarchery01x',
        Movement = { Amplitude = 1.0, Period = 2.5, Direction = -1 }
    },
    [10] = {
        Coords = vector3(-3672.5293, -2578.7290, -13.7321),
        Model = 's_confedtarget',
        Heading = 173.4968,

        Movement = {
            Axis = 'combined', Amplitude = 1.2, Period = 1.6,
            VerticalAmplitude = 0.7, VerticalPeriod = 1.1
        }
    }
}

Config.LeaderboardLimit = 10

Config.EntryFee = 5

Config.Title = 'TIRO MEXICANO'
Config.Subtitle = 'CAMPEONATO DE TIRO'
