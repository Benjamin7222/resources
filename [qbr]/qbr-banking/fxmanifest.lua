fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'QBR-banking'
version '1.0.1'

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/*.lua',
    'server/wrappers/*.lua'
}

client_script 'client/*.lua'
shared_scripts {
	'config.lua'
}

ui_page 'nui/index.html'

files {
    'nui/images/*.png',
    'nui/scripting/jquery-ui.css',
    'nui/scripting/external/jquery/jquery.js',
    'nui/scripting/jquery-ui.js',
    'nui/style.css',
    'nui/index.html',
    'nui/qbr-banking.js',
}
