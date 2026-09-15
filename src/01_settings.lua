-- The weather settings table, key → value; the first setting is the chosen
-- city. Where the stand kept a city in app_weather_settings, it is copied
-- over once (settings.copy_place), so switching the stand to this module
-- keeps its city; elsewhere there is nothing to copy.
local settings = require("settings")

local CREATE = {
    postgres = "CREATE TABLE " .. settings.TABLE .. " (key TEXT PRIMARY KEY, value TEXT NOT NULL,"
        .. " updated_at TEXT NOT NULL DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')))",
    sqlite = "CREATE TABLE " .. settings.TABLE .. " (key TEXT PRIMARY KEY, value TEXT NOT NULL,"
        .. " updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')))",
}

local function up_on(driver: string): any
    return function(db: any)
        local _, err = db:execute(CREATE[driver])
        if err then error("Failed to create " .. settings.TABLE .. ": " .. tostring(err)) end
        local copied, cerr = settings.copy_place(db, driver, settings.LEGACY, settings.TABLE)
        if copied == nil then error("Failed to copy the stand's city: " .. tostring(cerr)) end
    end
end

local function drop(db: any)
    local _, err = db:execute("DROP TABLE IF EXISTS " .. settings.TABLE)
    if err then error("Failed to drop " .. settings.TABLE .. ": " .. tostring(err)) end
end

return require("migration").define(function()
    migration("Create windows_weather_settings, copying the stand's city", function()
        database("postgres", function()
            up(up_on("postgres"))
            down(drop)
        end)
        database("sqlite", function()
            up(up_on("sqlite"))
            down(drop)
        end)
    end)
end)
