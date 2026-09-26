local Deliveries = {}
Sunny.Deliveries = Deliveries

function Deliveries.Allowed(src, mission)
    if not mission.allowedJobs then return true end
    local job, grade = Sunny.Bridge.GetJob(src)
    return Sunny.Utils.HasJobAccess(mission.allowedJobs, job, grade)
end

local function keys(src, mission)
    local owner = Config.Deliveries.cooldownScope == 'company' and '*'
        or Sunny.Bridge.GetCitizenId(src)
    return owner, mission.companyKey .. ':' .. mission.category
end

function Deliveries.RemainingAll(src)
    if not Config.Deliveries or not Config.Deliveries.enabled then return nil end
    local owner = Config.Deliveries.cooldownScope == 'company' and '*' or Sunny.Bridge.GetCitizenId(src)
    local result = {}
    for _, row in ipairs(MySQL.query.await('SELECT category, expires_at FROM sunny_train_delivery_cooldowns WHERE owner = ?', { owner }) or {}) do
        result[row.category] = tonumber(row.expires_at) or 0
    end
    return result
end

function Deliveries.Remaining(src, mission, snapshot)
    if not mission.delivery then return 0 end
    local owner, category = keys(src, mission)
    local expires
    if snapshot then expires = snapshot[category]
    else expires = MySQL.scalar.await('SELECT expires_at FROM sunny_train_delivery_cooldowns WHERE owner = ? AND category = ?', { owner, category }) end
    return math.max(0, (tonumber(expires) or 0) - os.time())
end

-- UPDATE conditionnel : un seul conducteur peut prendre la catégorie partagée.
function Deliveries.Claim(src, mission)
    if not mission.delivery or mission.cooldown == 0 then return true end
    local owner, category = keys(src, mission)
    MySQL.insert.await('INSERT IGNORE INTO sunny_train_delivery_cooldowns (owner, category, expires_at) VALUES (?, ?, 0)', { owner, category })
    local now = os.time()
    local changed = MySQL.update.await('UPDATE sunny_train_delivery_cooldowns SET expires_at = ? WHERE owner = ? AND category = ? AND expires_at <= ?',
        { now + mission.cooldown, owner, category, now })
    return changed == 1
end
