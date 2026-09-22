fx_version 'cerulean'
game 'rdr3'
version '1.3.0'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

ui_page "html/ui.html"

shared_script 'config.lua'

client_script 'client.lua'

server_script 'server.lua'

files {
    "html/*"
}

lua54 'yes'
