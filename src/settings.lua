-- The weather service's settings table and the one-time move of the city the
-- stand kept before this module existed.
--
-- The settings are key → value rows; so far only `place`, the chosen city as
-- JSON. A table, not a column per setting: the next setting (units, a second
-- city) must not need a migration.
--
-- The table names are parameters of `copy_place`, not constants inside it, so
-- a test copies between tables of its own and never touches a real
-- application's settings.

local settings = {}

settings.TABLE = "windows_weather_settings"
-- Where the stand kept the city while the weather lived in its src/app/weather.
settings.LEGACY = "app_weather_settings"

-- exists(db, driver, name) -> whether that table exists | nil, reason.
local function exists(db: any, driver: string, name: string): (boolean?, string?)
    local rows: any, err: any
    if driver == "postgres" then
        rows, err = db:query("SELECT to_regclass($1) AS found", {name})
    else
        rows, err = db:query("SELECT name AS found FROM sqlite_master WHERE type = 'table' AND name = $1", {name})
    end
    if err then return nil, tostring(err) end
    local first: any = type(rows) == "table" and rows[1] or nil
    return first ~= nil and first.found ~= nil, nil
end

-- copy_place(db, driver, from, to) -> how many rows were copied (0 or 1) | nil, reason
--
-- Copies the `place` row of `from` into `to` when `from` exists and has one;
-- a place already in `to` wins. No `from` table is not an error: an
-- application that never had the stand's weather has nothing to move.
function settings.copy_place(db: any, driver: string, from: string, to: string): (integer?, string?)
    local present, err = exists(db, driver, from)
    if present == nil then return nil, "could not tell whether " .. from .. " exists: " .. tostring(err) end
    if not present then return 0, nil end
    local rows, qerr = db:query("SELECT value, updated_at FROM " .. from .. " WHERE key = $1", {"place"})
    if qerr then return nil, "could not read " .. from .. ": " .. tostring(qerr) end
    local row: any = type(rows) == "table" and rows[1] or nil
    if row == nil then return 0, nil end
    local result, xerr = db:execute("INSERT INTO " .. to .. " (key, value, updated_at) VALUES ($1, $2, $3)"
        .. " ON CONFLICT (key) DO NOTHING", {"place", row.value, row.updated_at})
    if xerr then return nil, "could not write " .. to .. ": " .. tostring(xerr) end
    return math.tointeger(tonumber(type(result) == "table" and result.rows_affected or 0)) or 0, nil
end

return settings
