fx_version "cerulean"
game 'rdr3'
version '1.3.0'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

server_script 'server/main.lua'

shared_scripts {
	'@qbr-core/shared/locale.lua',
    	'locales/fr.lua',
	'config.lua'
}

client_script 'client/main.lua'

dependency 'qbr-core'

lua54 'yes'
