local Items = {}
Sunny.Items = Items

function Items.Init()
    for name, definition in pairs(Config.RailItems) do
        Sunny.Bridge.EnsureItem(name, definition)
    end

    exports[Config.Framework.core]:AddCommand('trainitems', 'Recevoir le charbon et les caisses de test ferroviaires (Admin)',
        { { name = 'id', help = 'ID du joueur (soi-même si omis)' } }, false, function(src, args)
            local target = src
            if args[1] ~= nil then target = tonumber(args[1]) end
            if not target or not Sunny.Bridge.GetPlayer(target) then
                if src > 0 then Sunny.Srv.Notify(src, 'Joueur introuvable.', 'error') end
                return
            end
            local added, missing = {}, {}
            for _, entry in ipairs(Config.RailTestKit) do
                local label = ('%d × %s'):format(entry.amount, Sunny.Bridge.ItemLabel(entry.item))
                if Sunny.Bridge.AddItem(target, entry.item, entry.amount) then
                    added[#added + 1] = label
                else
                    missing[#missing + 1] = label
                end
            end
            Sunny.Srv.Notify(target, 'Matériel reçu : ' .. (#added > 0 and table.concat(added, ', ') or 'aucun') .. '.', 'info')
            if #missing > 0 then
                Sunny.Srv.Notify(target, 'Inventaire plein : non remis — ' .. table.concat(missing, ', ') .. '.', 'error')
            end
            if src > 0 and src ~= target then Sunny.Srv.Notify(src, 'Remise du matériel au joueur ' .. target .. ' : ' .. #added .. '/' .. #Config.RailTestKit .. ' lots.', 'info') end
        end, 'admin')
end
