-- The settings migration: its table exists after the boot, and
-- `settings.copy_place` moves an application's city over once — between
-- tables of this test's own, so a real application's settings are never
-- touched.
local test = require("test")
local sql = require("sql")
local settings = require("settings")

local LEGACY = "weather_test_legacy"
local TARGET = "weather_test_target"
local PLACE = '{"name":"Samara","country":"Russia","latitude":53.2,"longitude":50.15}'

local function exec(db: any, query: string, params: any?)
    local _, err = db:execute(query, params or {})
    if err then error(tostring(err)) end
end

local function rows(db: any, query: string, params: any?): any
    local found, err = db:query(query, params or {})
    if err then error(tostring(err)) end
    return found or {}
end

local function table_sql(name: string): string
    return "CREATE TABLE " .. name .. " (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)"
end

local function define_tests()
    test.describe("weather settings", function()
        test.it("the migration created the settings table", function()
            local db = assert(sql.get("app:db"))
            local found = rows(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = $1", {settings.TABLE})
            db:release()
            test.eq(#found, 1, settings.TABLE)
        end)

        test.it("copy_place: moved once; a city already there wins; no old table or no city is nothing", function()
            local db = assert(sql.get("app:db"))
            exec(db, "DROP TABLE IF EXISTS " .. LEGACY)
            exec(db, "DROP TABLE IF EXISTS " .. TARGET)
            exec(db, table_sql(TARGET))

            local none, nerr = settings.copy_place(db, "sqlite", LEGACY, TARGET)
            test.eq(none, 0, "no old table: nothing to move, and no error — " .. tostring(nerr))

            exec(db, table_sql(LEGACY))
            local empty = settings.copy_place(db, "sqlite", LEGACY, TARGET)
            test.eq(empty, 0, "an old table without a city: nothing to move")

            exec(db, "INSERT INTO " .. LEGACY .. " (key, value, updated_at) VALUES ($1, $2, $3)",
                {"place", PLACE, "2026-09-11T17:00:00Z"})
            local moved, merr = settings.copy_place(db, "sqlite", LEGACY, TARGET)
            test.eq(moved, 1, tostring(merr))
            local copied = rows(db, "SELECT value, updated_at FROM " .. TARGET .. " WHERE key = $1", {"place"})[1]
            test.eq(tostring(copied.value) .. "|" .. tostring(copied.updated_at), PLACE .. "|2026-09-11T17:00:00Z")

            exec(db, "UPDATE " .. LEGACY .. " SET value = $1 WHERE key = $2", {'{"name":"Moscow"}', "place"})
            test.eq(settings.copy_place(db, "sqlite", LEGACY, TARGET), 0, "run again: nothing new")
            local kept = rows(db, "SELECT value FROM " .. TARGET .. " WHERE key = $1", {"place"})[1]
            test.eq(kept.value, PLACE, "the city already in the new table wins")

            exec(db, "DROP TABLE IF EXISTS " .. LEGACY)
            exec(db, "DROP TABLE IF EXISTS " .. TARGET)
            db:release()
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
