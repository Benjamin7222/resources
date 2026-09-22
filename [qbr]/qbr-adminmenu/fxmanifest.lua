fx_version 'cerulean'

game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description "QBR Admin Menu"

version '1.0.1'

ui_page 'html/index.html'

shared_scripts {
  '@qbr-core/shared/locale.lua',
  'locales/fr.lua',
  'shared/config.lua'
}

client_scripts {
  '@menuv/menuv.lua',
  'client/main.lua',
  'client/noclip.lua'
}

files {
  'html/index.html',
  'html/index.js'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua'
}

lua54 'yes'