-- The weather service: remembers the city, asks Open-Meteo, keeps the tray item.
--
-- A service and not the window, for two reasons. The tray shows the weather
-- when the window is closed too, so someone must refresh it without the
-- window. And the network here is synchronous: a window waiting for
-- Open-Meteo itself would stand frozen for the length of the request. The
-- window asks the service with a message and gets the answer on a channel of
-- its own, drawing all the while.
--
-- The tray item is refreshed every minute even when the weather did not
-- change: so it comes back by itself after the shell restarts (a new
-- compositor starts with an empty tray), and `TRAY_TTL` takes it away if the
-- service stops.
--
-- The database is the one the application named for this module: the
-- `target_db` requirement writes it into the migration entry's meta, and the
-- service reads it back from there, as the shell's persist does. A second name
-- of its own could only diverge from where the table was created.

local process = require("process")
local channel = require("channel")
local time = require("time")
local json = require("json")
local sql = require("sql")
local registry = require("registry")
local http_client = require("http_client")
local logger = require("logger")
local desktop = require("desktop")
local control = require("control")
local forecast = require("forecast")
local settings = require("settings")

local log = logger:named("chicago.weather")

local MIGRATION = "chicago.weather:01_settings"
local TICK = "60s"
local REFRESH_S = 15 * 60
local RETRY_S = 2 * 60
local TRAY_TTL = 180
local HTTP_TIMEOUT = "10s"

-- The desktop families whose tray gets the weather: the Chicago shell's
-- and the base's own. The service was not started by a compositor and has no
-- name in its context, so it takes the names from their owners. Each is a
-- FAMILY of names — `name`, `name.2`, … one desktop per terminal.ssh
-- connection — and `desktop.desktops(family)` lists the running ones.
local FAMILIES = {control.SERVICE_NAME, desktop.DEFAULT_SERVICE}

-- The service's state is a table, not locals: after an error under pcall in
-- go-lua a closure and its owner stop sharing a local.
local state: any = {place = nil, data = nil, fetched_at = 0, attempted_at = 0, error = nil}

local function now_s(): integer
    return math.tointeger(time.now():unix_nano() // 1000000000) or 0
end

-- ─── database ──────────────────────────────────────────────────────────

-- db_id() -> the database this module keeps its table in | nil, reason.
local function db_id(): (string?, string?)
    local entry: any, err = registry.get(MIGRATION)
    if not entry then return nil, MIGRATION .. " (it names the database) is unreadable: " .. tostring(err) end
    local meta: any = entry.meta or {}
    local id = meta.target_db
    if type(id) ~= "string" or id == "" then return nil, MIGRATION .. " has no meta.target_db" end
    return id, nil
end

local function with_db(work: any): (any, any)
    local id, iderr = db_id()
    if not id then return nil, iderr end
    local db, err = sql.get(id)
    if err or not db then return nil, err or ("database unavailable: " .. id) end
    local ok, result, work_err = pcall(work, db)
    db:release()
    if not ok then return nil, tostring(result) end
    return result, work_err
end

-- The city is kept as a JSON string under the key `place`. "Not chosen" and
-- "the database is unavailable" differ by the second value: the first is nil
-- without a reason.
local function load_place(): (any, any)
    local raw, err = with_db(function(db)
        local rows, qerr = db:query("SELECT value FROM " .. settings.TABLE .. " WHERE key = $1 LIMIT 1", {"place"})
        if qerr then return nil, tostring(qerr) end
        local first: any = type(rows) == "table" and rows[1] or nil
        return type(first) == "table" and first.value or nil, nil
    end)
    if err then return nil, err end
    if type(raw) ~= "string" or raw == "" then return nil, nil end
    local decoded, derr = json.decode(raw)
    if derr then return nil, "stored city is not JSON: " .. tostring(derr) end
    local place, perr = forecast.place(decoded)
    if not place then return nil, "stored city is invalid: " .. tostring(perr) end
    return place, nil
end

local function save_place(place: any): (any, any)
    local encoded, eerr = json.encode(place)
    if eerr then return nil, tostring(eerr) end
    local stamp = time.now():utc():format("2006-01-02T15:04:05Z")
    local saved, err = with_db(function(db)
        local _, xerr = db:execute("INSERT INTO " .. settings.TABLE .. " (key, value, updated_at) VALUES ($1, $2, $3)"
            .. " ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            {"place", encoded, stamp})
        if xerr then return nil, tostring(xerr) end
        return true, nil
    end)
    return saved, err
end

-- ─── network ───────────────────────────────────────────────────────────

local function get_json(url: string): (any, any)
    local response, err = http_client.get(url, {timeout = HTTP_TIMEOUT})
    if not response then return nil, "request failed: " .. tostring(err) end
    if response.status_code < 200 or response.status_code >= 300 then
        return nil, "HTTP " .. tostring(response.status_code)
    end
    local decoded, derr = json.decode(response.body or "")
    if derr then return nil, "answer is not JSON: " .. tostring(derr) end
    return decoded, nil
end

local function fetch_forecast(place: any): (any, any)
    local decoded, err = get_json(forecast.forecast_url(place))
    if not decoded then return nil, err end
    local parsed, perr = forecast.parse(decoded)
    return parsed, perr
end

local function geocode(query: any): (any, any)
    local text = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "type a city name" end
    if #text > 100 then return nil, "the name is too long" end
    local decoded, err = get_json(forecast.geocoder_url(text))
    if not decoded then return nil, err end
    return forecast.places(decoded), nil
end

-- ─── refresh and tray ──────────────────────────────────────────────────

-- Refresh when it is time (or when asked). A network failure does not wipe the
-- last summary: it stays with its time, and the tray decides by its age
-- whether to show it.
local function refresh(force: boolean)
    if not state.place then return end
    local now = now_s()
    local wait = state.error and RETRY_S or REFRESH_S
    if not force and now - state.attempted_at < wait then return end
    state.attempted_at = now
    local data, err = fetch_forecast(state.place)
    if data then
        state.data, state.fetched_at, state.error = data, now, nil
    else
        state.error = tostring(err)
        log:warn("forecast not updated", {city = state.place.name, error = state.error})
    end
end

-- Every running desktop of every family. No desktop is not an error but an
-- ordinary state, and `desktop.tray` would complain in the log every minute.
local function push_tray()
    local age = state.fetched_at > 0 and now_s() - state.fetched_at or nil
    local text, title, image, icon = forecast.tray(state.place, state.data, age)
    for _, family in ipairs(FAMILIES) do
        for _, found in ipairs(desktop.desktops(family)) do
            local ok, err = desktop.tray({key = forecast.TRAY_KEY, text = text, title = title,
                image = image, icon = icon, entry = forecast.WINDOW, ttl = TRAY_TTL}, tostring(found.name))
            if not ok then log:warn("tray not updated", {desktop = found.name, error = tostring(err)}) end
        end
    end
end

local function drop_tray()
    for _, family in ipairs(FAMILIES) do
        for _, found in ipairs(desktop.desktops(family)) do
            desktop.tray({key = forecast.TRAY_KEY, remove = true}, tostring(found.name))
        end
    end
end

-- The summary for the window and the widget: everything they draw, nothing more.
local function snapshot(op: string): any
    local now = now_s()
    local age = state.fetched_at > 0 and now - state.fetched_at or nil
    return {op = op, ok = true, place = state.place, data = state.data,
        fetched_at = state.fetched_at > 0 and state.fetched_at or nil,
        age = age, stale = age == nil or age > forecast.STALE_S, error = state.error}
end

-- The answer goes to the message's sender, not to an address in its body: an
-- address in a body can be planted, the sender cannot.
local function answer(to: any, body: any)
    if to == nil then return end
    local sent, err = process.send(tostring(to), forecast.REPLY, body)
    if not sent then log:warn("reply not delivered", {to = tostring(to), error = tostring(err)}) end
end

local function handle(message: any)
    if message:topic() ~= forecast.ASK then return end
    local body = forecast.unwrap(message:payload())
    local to = message:from()
    local op = type(body.op) == "string" and body.op or ""

    if op == "get" then
        answer(to, snapshot(op))
    elseif op == "refresh" then
        refresh(true)
        push_tray()
        answer(to, snapshot(op))
    elseif op == "search" then
        local found, err = geocode(body.query)
        if found then answer(to, {op = op, ok = true, results = found, query = body.query})
        else answer(to, {op = op, ok = false, error = tostring(err), query = body.query}) end
    elseif op == "choose" then
        local place, err = forecast.place(body.place)
        if not place then
            answer(to, {op = op, ok = false, error = tostring(err)})
            return
        end
        local saved, serr = save_place(place)
        if not saved then
            -- A city that was not saved is not passed off as chosen: after a
            -- restart the service would return to the old one, and the person
            -- would not know why.
            answer(to, {op = op, ok = false, error = "city not saved: " .. tostring(serr)})
            return
        end
        state.place, state.data, state.fetched_at, state.error = place, nil, 0, nil
        refresh(true)
        push_tray()
        answer(to, snapshot(op))
    else
        answer(to, {op = op, ok = false, error = "unknown request: " .. op})
    end
end

local function main()
    local events = process.events()
    local inbox = process.inbox()
    local registered, rerr = process.registry.register(forecast.SERVICE)
    if not registered then
        -- A second instance under the same name is invisible to the window: the
        -- window would find the first. Working silently past the window is
        -- worse than stopping with a reason.
        log:error("weather service not registered", {name = forecast.SERVICE, error = tostring(rerr)})
        return {status = "failed", error = tostring(rerr)}
    end

    local place, perr = load_place()
    if perr then log:warn("city not loaded", {error = tostring(perr)}) end
    state.place = place
    refresh(true)
    push_tray()

    local ticker = time.after(TICK)
    while true do
        local picked = channel.select({events:case_receive(), inbox:case_receive(), ticker:case_receive()})
        if not picked.ok then break end
        if picked.channel == events then
            if picked.value and picked.value.kind == process.event.CANCEL then break end
        elseif picked.channel == ticker then
            ticker = time.after(TICK)
            refresh(false)
            push_tray()
        elseif picked.value then
            local ok, err = pcall(handle, picked.value)
            if not ok then log:error("request failed", {error = tostring(err)}) end
        end
    end

    drop_tray()
    return {status = "completed"}
end

return {main = main}
