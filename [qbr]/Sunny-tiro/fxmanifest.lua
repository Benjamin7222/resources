fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'Benji'
description 'Mexican Bottle Shooting Mini-Game for QBR RedM'
version '1.1.0'

shared_script 'config.lua'

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/sounds/*.wav'
}

lua54 'yes'

dependencies {
    'qbr-core',
    'ox_target',
    'oxmysql'
}
