const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const root = process.argv[2];
const files = [];
(function walk(d){ for (const f of fs.readdirSync(d)) { if (['node_modules', '.git', 'shots'].includes(f)) continue; const p = path.join(d,f); if (fs.statSync(p).isDirectory()) walk(p); else if (p.endsWith('.lua')) files.push(p); } })(root);
let bad = 0;
for (const f of files) {
  const L = lauxlib.luaL_newstate();
  const src = fs.readFileSync(f);
  const st = lauxlib.luaL_loadbuffer(L, src, null, to_luastring('@'+path.relative(root,f)));
  if (st !== 0) { bad++; console.log('FAIL', lua.lua_tojsstring(L, -1)); } else console.log('ok  ', path.relative(root, f));
}
process.exit(bad ? 1 : 0);
