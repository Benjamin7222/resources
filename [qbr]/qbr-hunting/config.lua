Config = Config or {}

Config.Items = {
    -- You Can Sell Price for Certain Items in Inventory They Must Be Listed Here
    ['Inv'] = {
        ['skin_alligator'] = 0.50,
        ['skin_snake'] = 0.15,
        ['animal_pelt'] = 0.20,
        ['animal_heart'] = 0.30,
        ['animal_squirrel'] = 0.30,
        ['skin_muskrat'] = 0.25,
        ['animal_toad'] = 0.20,
        ['animal_wool'] = 0.25,
        ['meat_bird'] = 0.3,
        ['skin_iguana'] = 0.45,
        ['feather'] = 0.25,
    },
    -- You Can Sell, Skin or Trade Items Carrying over Shoulder Include the Hash. 
    --Skin means it gives you a item when skinning butcher is what they will offer you for the animal when carrying
    ['Pickup'] = {
        [40345436]     = {name = 'Merino Sheep',      skin = {item = 'animal_wool'}, butcher = {cash = 5, items = {animal_meat = 2}}},
        [-1568716381]  = {name = 'Bighorn Sheep',     skin = {item = 'animal_wool'}, butcher = {cash = 5, items = {animal_meat = 2}}},
        [-1414989025]  = {name = 'Virginia OPossum',  skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 1}}},
        [480688259]    = {name = 'Valley Coyote',     skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 2}}}, --pelt 
        [-541762431]   = {name = 'Jackrabbit',        skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 1}}},
        [1007418994]   = {name = 'Big China Pig',     skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 1}}},
        [1458540991]   = {name = 'Raccoon',           skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 1}}},
        [-407730502]   = {name = 'Turtle',            skin = {item = 'animal_heart'},butcher = {cash = 5, items = {animal_meat = 2}}},
        [252669332]    = {name = 'American Red Fox',  skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 2}}},
        [-1143398950]  = {name = 'Big Grey Wolf',     skin = {item = 'animal_pelt', amount = 2}, butcher = {cash = 5, items = {animal_meat = 4}}},
        [-885451903]   = {name = 'Medium Grey Wolf',  skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 3}}},
        [-829273561]   = {name = 'Small Grey Wolf',   skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 2}}},
        [-1295720802]  = {name = "American Alligator",skin = {item = 'skin_alligator'}, butcher = {cash = 5, items = {skin_alligator = 2}}},
        [759906147]    = {name = "American Beaver",   skin = {item = 'animal_pelt'}, butcher = {cash = 5, items = {animal_meat = 1}}},

        ------- DEER --------
        [1110710183]   = {name = 'White Tail Deer', skin = {item = 'animal_pelt', amount = 2}, butcher = {cash = 5, items = {animal_pelt = 2, animal_meat = 3}}},
        [-1963605336]  = {name = 'Whitetail Buck',  skin = {item = 'animal_pelt', amount = 2}, butcher = {cash = 5, items = {animal_pelt = 2, animal_meat = 3}}},
        [1755643085]   = {name = 'Pronghorn Doe',   skin = {item = 'animal_pelt', amount = 2}, butcher = {cash = 5, items = {animal_pelt = 2, animal_meat = 3}}},

        ------- SNAKES -------
        [-22968827]    = {name = "Water Snake",              skin = {item = 'skin_snake'}, butcher = {cash = 5, items = {skin_snake = 2}}},
        [-229688157]   = {name = "Northern Water Snake",     skin = {item = 'skin_snake'}, butcher = {cash = 5, items = {skin_snake = 2}}},
        [-1790499186]  = {name = "Snake Red Boa",            skin = {item = 'skin_snake'}, butcher = {cash = 5, items = {skin_snake = 2}}},
        [1464167925]   = {name = "Snake Fer-De-Lance",       skin = {item = 'skin_snake'}, butcher = {cash = 5, items = {skin_snake = 2}}},
        [846659001]    = {name = "Black-Tailed Rattlesnake", skin = {item = 'skin_snake'}, butcher = {cash = 5, items = {skin_snake = 2}}},
        [545068538]    = {name = "Timber Rattlesnake",       skin = {item = 'skin_snake'}, butcher = {cash = 5, items = {skin_snake = 2}}},

        ------ BIRDS -------
        [-2063183075]  = {name = 'Dominique Chicken',        skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}},
        [1095117488]   = {name = "Great Blue Heron",         skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}},--
        [-861544272]   = {name = "Coastal Horned Owl",       skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}},-- Pluck feathers
        [1416324601]   = {name = "Ring-Necked Pheasant",     skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}},-- gives heart 
        [-1003616053]  = {name = "Mallard Duck",             skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}},-- gives heart
        [-1076508705]  = {name = "Roseate SpoonBill", skin = {item = 'feather', amount = 2}, butcher = {cash = 5, items = {meat_bird = 2}}},
        [-2145890973]  = {name = "Ferruginous Hawk",  skin = {item = 'feather', amount = 2}, butcher = {cash = 5, items = {meat_bird = 2}}},
        [-164963696]   = {name = "Herring Seagull",   skin = {item = 'feather', amount = 2}, butcher = {cash = 5, items = {meat_bird = 2}}}, --Feathers
        [-2011226991]  = {name = "Eastern Wild Turkey",      skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}}, --heart
        [-466054788]   = {name = "Eastern Wild Turkey",      skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}}, -- heart
        [-166054593]   = {name = "Eastern Wild Turkey",      skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}}, -- heart
        [1104697660]   = {name = "Western Turkey Vulture",   skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}}, --feathers
        [2023522846]   = {name = "Dominique Rooster",        skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}}, --heart
        [-466687768]   = {name = "Red-Footed Booby",         skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}}, --feathers
        [-575340245]   = {name = "Western Raven",      skin = {item = 'feather', amount = 2},butcher = {cash = 5, items = {meat_bird = 2}}}, --feathers
        [2079703102]   = {name = "Greater Prairie Chicken",  skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}}, --heart
        [1265966684]   = {name = "American White Pelican",   skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}}, --feathers
        [-1797450568]  = {name = "Blue And Yellow Macaw",    skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}}, --feathers
        [-2073130256]  = {name = "Double-Crested Cormorant", skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}}, --feathers
        [-564099192]   = {name = "Whooping Crane",           skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}}, --feathers
        [723190474]    = {name = "Canada Goose",             skin = {item = 'feather'},      butcher = {cash = 5, items = {meat_bird = 2}}}, --feathers
        [386506078]    = {name = "Common Loon",              skin = {item = 'animal_heart'}, butcher = {cash = 5, items = {meat_bird = 2}}}, --heart
        [1205982615]   = {name = "Californian Condor",skin = {item = 'feather', amount = 2}, butcher = {cash = 5, items = {meat_bird = 2}}}, --Feathers
        --- OTHER ---
        [-753902995]   = {name = "Alpine Goat",           skin = {item = 'animal_wool'},  butcher = {cash = 5, items = {animal_meat = 3}}},
        [-1134449699]  = {name = "American Muskrat",      skin = {item = 'skin_muskrat'}, butcher = {cash = 5, items = {animal_meat = 1}}},
        [1654513481]   = {name = "Panther",               skin = {item = 'animal_pelt'},  butcher = {cash = 5, items = {animal_pelt = 2, animal_meat = 3}}},
        [90264823]     = {name = "Cougar",                skin = {item = 'animal_pelt', amount = 2}, butcher = {cash = 5, items = {animal_pelt = 2, animal_meat = 3}}},
        [-1854059305]  = {name = "Green Iguana",          skin = {item = 'skin_iguana'},  butcher = {cash = 5, items = {animal_meat = 1}}}, --skin
        [-593056309]   = {name = "Desert Iguana",         skin = {item = 'skin_iguana'},  butcher = {cash = 5, items = {animal_meat = 1}}}, --skin
        [-1433814131]  = {name = "Legendary Maza Cougar", skin = {item = 'animal_pelt', amount = 2}, butcher = {cash = 5, items = {animal_pelt = 2, animal_meat = 3}}}, --pelt
        [252669332]    = {name = "American Red Fox",      skin = {item = 'animal_pelt'},  butcher = {cash = 5, items = {animal_meat = 2}}}, -- pelt and carcass rare hard to kill
        [-1170118274]  = {name = "American Badger",       skin = {item = 'animal_pelt'},  butcher = {cash = 5, items = {animal_meat = 2}}}, --pelt and carcass
        [-1211566332]   = {name = "Stripped Skunk",       skin = {item = 'animal_pelt'},  butcher = {cash = 5, items = {animal_meat = 2}}}, --pelt and carcass

        ------- LARGE ANIMALS NO CARRY --------
        [-2004866590]  = {name = 'American Alligator Skin', butcher = {cash = 5, items = {skin_alligator = 2}}}, -- lage alligator skin takes lotta shots -1892280447
        [85379810]     = {name = "Animal Pelt",             butcher = {cash = 5, items = {animal_pelt = 2}}}, -- -50684386 & -2021043433 & -1098441944 & 556355544 & 195700131
        [1631768462]   = {name = 'Bear Pelt',               butcher = {cash = 5, items = {animal_pelt = 2}}}, -- -1124266369
        [1780825678]   = {name = 'Black Bear Pelt',         butcher = {cash = 5, items = {animal_pelt = 2}}}, -- 730092646
        [-368368059]   = {name = "Alligator Skin",          butcher = {cash = 5, items = {skin_alligator = 3}}}, ---- -1598866821(legendary)
        [-1804478060]  = {name = "Teca Gator Skin",         butcher = {cash = 5, items = {skin_alligator = 3}}}, ---- 674287411(legendary)
        [-1962493114]  = {name = "Tatanka Bison Pelt",      butcher = {cash = 5, items = {animal_pelt = 3}}}, ---- -915290938(legendary)

        [1751700893]  = {name = "Pig Pelt", skin = {item = 'animal_pelt'}}, -- 1751700893 & 2028722809 & -389300196 & 2028722809
        [2028722809]  = {name = "Pig Pelt", skin = {item = 'animal_pelt'}}, -- 1751700893 & 2028722809 & -389300196 & 2028722809
        [-389300196]  = {name = "Pig Pelt", skin = {item = 'animal_pelt'}}, -- 1751700893 & 2028722809 & -389300196 & 2028722809
        [2028722809]  = {name = "Pig Pelt", skin = {item = 'animal_pelt'}}, -- 1751700893 & 2028722809 & -389300196 & 2028722809

        ------ DIRECT POCKET ITEMS --------
        [-1028170431]  = {name = "Golden Sparrow", skin = {item = 'meat_bird'}}, -- Full Bird
        [1582986780]   = {name = "Blue Jay",       skin = {item = 'meat_bird'}}, -- Full Bird
        [1784941179]   = {name = "Cardinal",       skin = {item = 'meat_bird'}}, -- Full Bird
        [-292997097]   = {name = "Cedar waxwing",  skin = {item = 'meat_bird'}}, -- Full Bird
        [-2037578922]  = {name = "Cuban Crab",     skin = {item = 'animal_heart'}}, -- Full Bird
        [-1763055991]  = {name = "Crawfish",       skin = {item = 'animal_heart'}}, -- Full Bird
        [98537260]     = {name = "Crow",           skin = {item = 'meat_bird'}}, -- Full Bird
        [-930822792]   = {name = "Frogbull",       skin = {item = 'animal_toad'}},
        [-1302821723]  = {name = "Hooded Oriole",  skin = {item = 'meat_bird'}}, -- Full Bird
        [111281960]    = {name = "Pigeon",         skin = {item = 'meat_bird'}}, -- Full Bird
        [674267496]    = {name = "Bat",            skin = {item = 'animal_heart'}}, -- Full Bird
        [-1210546580]  = {name = "Robin",          skin = {item = 'meat_bird'}}, -- Full Bird
        [-1910795227]  = {name = "Songbird",       skin = {item = 'meat_bird'}}, -- Full Bird
        [-1028170431]  = {name = "Sparrow",        skin = {item = 'meat_bird'}}, -- Full Bird
        [1502581273]   = {name = "Toad",           skin = {item = 'animal_toad'}},
        [510312109]    = {name = "Red Woodpecker", skin = {item = 'meat_bird'}}, -- Full Bird
        [729471181]    = {name = "Woodpecker",     skin = {item = 'meat_bird'}}, -- Full Bird
        [1465438313]   = {name = "Squirrel",       skin = {item = 'animal_squirrel'}}, -- Full Bird
    },
}

Config.Butchers = {
    ["Locations"] = {
        ['Saint Denis Butcher'] = vector4(2819.540, -1331.2100, 45.50, 51.82),
        ['Strawberry Butcher']  = vector4(-1753.14, -392.420, 155.25, 181.37),
        ['Blackwater Butcher']  = vector4(-753.040, -1284.96, 42.500, 282.06),
        ['Tumbleweed Butcher']  = vector4(-5510.371, -2947.00, -2.79, 251.54),
        ['Valentine Butcher']   = vector4(-339.014, 767.6358, 115.56, 100.41),
        ['Annesburg Butcher']   = vector4(2934.510, 1301.159, 43.480, 70.570),
        ['Armadillo Butcher']   = vector4(-3691.438, -2623.152, -14.75, 0.46),
        ['Van Horn Butcher']    = vector4(2991.844, 572.0218, 43.360, 259.52),
        ['Rhodes Butcher']      = vector4(1297.578, -1277.589, 74.80, 146.60),
    },
    ['Blip'] = -1665418949, -- Or False to Disable
    ['PedModel'] = `S_M_M_UNIBUTCHERS_01`, -- Or False to Disable
}