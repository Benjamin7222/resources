Config = Config or {}

Config.Ticker = 20 -- Tick Every 20 Min
Config.Debug = false
--- Blips List https://github.com/femga/rdr3_discoveries/tree/3f8917d8b581736548387d3296aa6288b5168869/useful_info_from_rpfs/textures/blips
Config.FarmingZones = {
    [1] = {
        ['blip'] = 669307703, -- Remove or set to false to disable
        ['coords'] = vector4(1701.36, -1460.74, 47.86, 110.0),
        ['dim'] = vector2(50.0, 100.0)
    },
    [2] = {
        ['coords'] = vector4(1136.83, 457.08, 96.84, 130.79), -- Farm House
        ['dim'] = vector2(70.0, 50.0)
    },
    [3] = {
        ['coords'] = vector4(1802.88, -1468.22, 45.40, 116.95), -- Farm House
        ['dim'] = vector2(100.0, 30.0)
    }
}

---- This is the Prop that Adds a Prompt to be able to Pick It as well as the item to receive once picked
Config.FarmingCrops = {
    [`ginseng_p`]            = 'american_ginseng',
    [`alaskanginseng_p`]     = 'alaskan_ginseng',
    [`blackcurrant_p`]       = 'black_currant',
    [`s_inv_huckleberry01x`] = 'huckle_berry',
    [`s_inv_blackberry01x`]  = 'black_berry',
    [`s_inv_baybolete01bx`]  = 'bay_bolete',
    [`wildmint_p`]           = 'mint',
    [`s_indiantobacco01x`]   = 'tobacco',
    [`crp_cornstalks_bc_sim`]= 'corn',
    [`indtobacco_p`]         = 'coffee',
}