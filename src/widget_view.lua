-- The weather widget's tree (FR-006 §9) — apart from the process, so a test
-- checks it without an application.
--
-- The three states are the tray's, decided by the same `forecast.tray`: no
-- city; fresh data; data gone stale or never arrived — then "--°", not the
-- last temperature. The tray gives a picture only to fresh data, and that is
-- what tells the states apart here: there is no second rule of what "fresh"
-- means.
local forecast = require("forecast")
local gadget = require("gadget")

local widget_view = {}

-- tree(model) — model: {place, data, age, problem}, the service's summary and
-- the reason when the service could not be asked.
function widget_view.tree(model: any, geometry: any?): any
    local m: any = type(model) == "table" and model or {}
    local value, _, image, icon = forecast.tray(m.place, m.data, m.age)
    local place = type(m.place) == "table" and tostring(m.place.name) or "No city selected"
    if geometry and ((tonumber(geometry.width) or 18) < 14 or (tonumber(geometry.height) or 5) < 4) then
        return {kind = "column", children = {
            {kind = "label", size = 1, text = value},
            {kind = "label", size = 1, text = place},
        }}
    end
    local caption, condition
    if image ~= nil then
        local now: any = m.data.current
        caption = "Feels like " .. forecast.degrees(now.feels_like)
        condition = forecast.describe(now.code)
    elseif type(m.place) == "table" then
        caption = "no fresh data"
        condition = m.problem and tostring(m.problem) or "waiting for the service"
    else
        caption = ""
        condition = m.problem and tostring(m.problem) or "open Weather to pick one"
    end
    return gadget.stack{
        gadget.stat{value = value, caption = caption, image = image, icon = icon},
        gadget.lines{lines = {place, condition}},
    }
end

return widget_view
