-- The weather window: the current weather, the week's forecast and a city search.
--
-- No network here at all: everything is asked of the service
-- `windows.weather` with a message, the answer arrives on its own
-- topic, and the window gets it as an action `{type = "channel"}` without
-- stopping drawing. A refusal — no service, the network did not answer, no
-- city found — becomes the status line, not an empty window.

local app = require("app")
local process = require("process")
local forecast = require("forecast")

local definition = {}
definition.interval = "60s"
definition.title = function(model: any): string
    if type(model.place) == "table" then return "Weather — " .. tostring(model.place.name) end
    return "Weather"
end

-- Ask the service. `busy` is what the status line says while waiting; the quiet
-- question on the timer does not set it, so the line does not blink every
-- minute.
local function ask(model: any, op: string, extra: any, busy: any)
    local pid = process.registry.lookup(forecast.SERVICE)
    if not pid then
        model.notice = "weather service is not running"
        return
    end
    local body: any = type(extra) == "table" and extra or {}
    body.op = op
    local sent, err = process.send(pid, forecast.ASK, body)
    if not sent then
        model.notice = "request not sent: " .. tostring(err)
        return
    end
    if busy then model.busy = busy end
end

local function trim(text: any): string
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function search(model: any)
    local query = trim(model.query)
    if query == "" then
        model.notice = "type a city name first"
        return
    end
    ask(model, "search", {query = query}, "Searching for " .. query .. "…")
end

local function choose(model: any)
    local place = type(model.results) == "table" and model.results[model.picked or 0] or nil
    if not place then return end
    ask(model, "choose", {place = place}, "Loading weather for " .. tostring(place.name) .. "…")
end

local function leave_search(model: any)
    model.mode, model.results, model.picked = "forecast", nil, nil
end

function definition.init(args: any, context: any): any
    local model: any = {mode = "forecast", query = "", place = nil, data = nil, stale = true,
        error = nil, notice = nil, busy = nil, results = nil, picked = nil, replies = nil}
    -- The subscription comes BEFORE the first question: a quick answer that
    -- arrived earlier would land in the inbox, where nobody reads it.
    local replies = process.listen(forecast.REPLY, {message = true})
    model.replies = replies
    if replies and context.watch then context.watch(replies) end
    ask(model, "get", nil, "Loading…")
    return model
end

local function apply(model: any, body: any)
    model.busy = nil
    if body.ok == false then
        model.notice = tostring(body.error or "the weather service refused")
        return
    end
    model.notice = nil
    if body.op == "search" then
        model.results = type(body.results) == "table" and body.results or {}
        model.picked = #model.results > 0 and 1 or nil
        model.mode = "search"
        if #model.results == 0 then model.notice = "nothing found for " .. tostring(body.query) end
        return
    end
    model.place, model.data, model.stale = body.place, body.data, body.stale == true
    model.error, model.age = body.error, tonumber(body.age)
    if body.op == "choose" then
        leave_search(model)
        model.query = ""
    end
end

function definition.update(model: any, action: any, context: any)
    if action.type == "channel" then
        if not action.ok then
            model.notice = "the reply channel closed"
            return
        end
        apply(model, forecast.unwrap(action.value:payload()))
    elseif action.type == "tick" then
        ask(model, "get", nil, nil)
        return false
    elseif action.id == "query" and action.type == "change" then
        -- Every keystroke redraws: the editor reads the field's text from the
        -- tree, so a frame skipped here would leave the old text on screen and
        -- append the next key to it (measured live on 2026-09-11).
        model.query = action.value
    elseif (action.id == "query" or action.id == "search") and action.type == "activate" then
        search(model)
    elseif action.id == "results" and action.type == "select" then
        -- A click on the row already picked is a double click: it works
        -- without a timer, as in the contact list.
        if action.pointer and action.index == model.picked then choose(model) end
        model.picked = action.index
    elseif action.id == "results" and action.type == "activate" then
        choose(model)
    elseif action.id == "use" then
        choose(model)
    elseif action.id == "cancel" then
        leave_search(model)
    elseif action.id == "refresh" then
        ask(model, "refresh", nil, "Updating…")
    elseif action.type == "key" and action.key_type == "f5" then
        ask(model, "refresh", nil, "Updating…")
    elseif action.type == "key" and action.key_type == "esc" then
        if model.mode == "search" then leave_search(model) else context.close() end
    end
end

local function now_lines(model: any): any
    local data = model.data
    if type(model.place) ~= "table" then
        return {{kind = "label", text = "No city selected.\nType a city name above and press Search."}}
    end
    if type(data) ~= "table" or type(data.current) ~= "table" then
        return {{kind = "label", text = model.error and ("No weather yet: " .. tostring(model.error)) or "Loading…"}}
    end
    local now = data.current
    local headline = forecast.degrees(now.temperature) .. "C   " .. forecast.describe(now.code)
    if model.stale then headline = headline .. "   (out of date)" end
    local wind = now.wind and string.format("%.1f m/s %s", now.wind + 0.0, forecast.compass(now.wind_direction)) or "—"
    local image, icon = forecast.icon(now.code, now.is_day)
    -- The picture on the left: a 32 px icon in pixels, one character in cells.
    return {{kind = "row", gap = 1, children = {
        {kind = "image", size = 5, image = image, icon = icon},
        {kind = "column", children = {
            {kind = "label", size = 1, text = headline},
            {kind = "label", size = 1, text = "Feels like " .. forecast.degrees(now.feels_like) .. "C"
                .. "   Humidity " .. (now.humidity and string.format("%d%%", math.floor(now.humidity + 0.5)) or "—")},
            {kind = "label", size = 1, text = "Wind " .. wind
                .. "   Pressure " .. (now.pressure and string.format("%d hPa", math.floor(now.pressure + 0.5)) or "—")},
        }},
    }}}
end

local function day_rows(model: any): any
    local rows = {}
    local days = type(model.data) == "table" and model.data.days or {}
    for index, day in ipairs(type(days) == "table" and days or {}) do
        rows[#rows + 1] = {id = tostring(day.date), cells = {
            index == 1 and "Today" or (forecast.weekday(day.date) .. " " .. tostring(day.date):sub(9, 10)),
            select(2, forecast.icon(day.code, true)) .. " " .. forecast.describe(day.code),
            forecast.degrees(day.max),
            forecast.degrees(day.min),
            day.precipitation and string.format("%d%%", math.floor(day.precipitation + 0.5)) or "—",
        }}
    end
    return rows
end

local function status_text(model: any): string
    if model.busy then return tostring(model.busy) end
    if model.notice then return tostring(model.notice) end
    if model.error then return "Update failed: " .. tostring(model.error) end
    if model.age then
        local minutes = math.floor((tonumber(model.age) or 0) / 60)
        return minutes < 1 and "Updated just now · F5 to refresh" or ("Updated " .. minutes .. " min ago · F5 to refresh")
    end
    return "F5 to refresh"
end

function definition.view(model: any, context: any): any
    local body: any
    if model.mode == "search" then
        local items = {}
        for index, place in ipairs(model.results or {}) do
            items[#items + 1] = {id = index, text = forecast.label(place)}
        end
        body = {
            {kind = "label", size = 1, text = "Pick a city:"},
            {kind = "list", id = "results", items = items, selected = model.picked},
            {kind = "row", size = 2, gap = 1, children = {
                {kind = "label", text = ""},
                {kind = "button", id = "use", size = 12, text = "Use city", default = true,
                    disabled = model.picked == nil},
                {kind = "button", id = "cancel", size = 12, text = "Cancel"},
            }},
        }
    else
        local title = type(model.place) == "table" and forecast.label(model.place) or "Current weather"
        body = {
            {kind = "group", title = title, size = 5, children = now_lines(model)},
            {kind = "table", id = "days", rows = day_rows(model), columns = {
                {title = "Day", width = 8},
                {title = "Weather", weight = 1},
                {title = "High", width = 5, align = "right"},
                {title = "Low", width = 5, align = "right"},
                {title = "Rain", width = 5, align = "right"},
            }},
        }
    end

    local children: any = {
        {kind = "row", size = 2, gap = 1, children = {
            {kind = "label", size = 5, text = "City:"},
            {kind = "input", id = "query", text = model.query},
            {kind = "button", id = "search", size = 10, text = "Search", default = model.mode ~= "search"},
            {kind = "button", id = "refresh", size = 10, text = "Refresh"},
        }},
    }
    for _, node in ipairs(body) do children[#children + 1] = node end
    children[#children + 1] = {kind = "statusbar", size = 1, fields = {
        {text = status_text(model)}, {text = "Open-Meteo", width = 12}}}
    return {kind = "column", padding = 1, padding_bottom = 0, gap = 1, children = children}
end

function definition.dispose(model: any, context: any)
    if model.replies then pcall(process.unlisten, model.replies) end
end

local function main(first: any, id: any, args: any, viewport: any)
    app.run(definition, first, id, args, viewport)
end

return {main = main, definition = definition}
