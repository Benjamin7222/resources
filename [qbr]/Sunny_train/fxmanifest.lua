fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'Sunny_train'
description 'Sunny_train - Compagnie ferroviaire RP (conduite, missions, billets, controle, maintenance, braquages)'
author 'Benji'
version '1.0.0'

lua54 'yes'

shared_scripts {
    'config/locale.lua',
    'config/config.lua',
    'config/items.lua',
    'config/deliveries.lua',
    'shared/utils.lua',
    'shared/deliveries.lua',
}

client_scripts {
    'client/main.lua',
    'client/ui.lua',
    'client/stations.lua',
    'client/interaction.lua',
    'client/target.lua',
    'client/junctions.lua',
    'client/train.lua',
    'client/missions.lua',
    'client/departures.lua',
    'client/tickets.lua',
    'client/controller.lua',
    'client/maintenance.lua',
    'client/robbery.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/items.lua',
    'server/security.lua',
    'server/main.lua',
    'server/dispatch.lua',
    'server/fleet.lua',
    'server/hold.lua',
    'server/deliveries.lua',
    'server/missions.lua',
    'server/departures.lua',
    'server/tickets.lua',
    'server/robbery.lua',
    'server/junctions.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'qbr-core',
    'oxmysql',
}
