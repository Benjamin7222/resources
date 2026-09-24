game 'rdr3'
fx_version 'adamant'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'sunny_horseshoes'
author 'Benji'
description 'sunny_horseshoes - Lancer de fer à cheval (solo / multijoueur, score validé serveur) - Benji'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/physics.lua'
}

client_scripts {
    'client/main.lua',
    'client/throwing.lua',
    'client/game.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'qbr-core',
    'oxmysql'
}

lua54 'yes'
