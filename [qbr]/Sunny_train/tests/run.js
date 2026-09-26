const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const deliveries = process.argv.includes('--deliveries');
const res = process.argv.slice(2).find((a) => !a.startsWith('--')) || path.join(__dirname, '..');
console.log(deliveries ? 'Configuration de production : livraisons globales' : 'Régression : anciennes missions (sans configuration livraisons)');
const here = __dirname;
const files = [
    path.join(here, 'mocks.lua'),
    ...['config/locale.lua', 'config/config.lua', 'config/items.lua',
        ...(deliveries ? ['config/deliveries.lua'] : []), 'shared/utils.lua',
        ...(deliveries ? ['shared/deliveries.lua'] : []),
        'server/bridge.lua', 'server/items.lua', 'server/security.lua', 'server/main.lua', 'server/dispatch.lua',
        'server/fleet.lua', 'server/hold.lua', 'server/deliveries.lua', 'server/missions.lua', 'server/departures.lua', 'server/tickets.lua', 'server/robbery.lua', 'server/junctions.lua'].map((f) => path.join(res, f)),
    path.join(here, deliveries ? 'deliveries.lua' : 'test.lua'),
    path.join(res, 'client/departures.lua'),
    path.join(here, 'client-clock.lua'),
    path.join(res, 'client/tickets.lua'),
    path.join(here, 'late-join.lua'),
    ...['client/interaction.lua', 'client/junctions.lua', 'client/train.lua'].map((f) => path.join(res, f)),
    path.join(here, 'driving-prompts.lua'),
    path.join(res, 'client/missions.lua'),
    path.join(here, 'free-driving.lua'),
];
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
for (const f of files) {
    const st = lauxlib.luaL_loadbuffer(L, fs.readFileSync(f), null, to_luastring('@' + path.basename(path.dirname(f)) + '/' + path.basename(f)));
    if (st !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
        console.error('ERREUR dans', f, ':', lua.lua_tojsstring(L, -1));
        process.exit(2);
    }
}
lua.lua_getglobal(L, to_luastring('TEST_FAILED'));
process.exit(lua.lua_tointeger(L, -1) > 0 ? 1 : 0);
