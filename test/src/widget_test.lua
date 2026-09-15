-- The weather widget: the tray's three states — no city, fresh data, stale
-- data — drawn by the same `forecast.tray` rule, "--°" instead of the last
-- temperature, and the tree laid out in the panel's 18×5 body without
-- overlaps — in cells and at two pixel cell sizes.
local test = require("test")
local widget_view = require("widget_view")
local forecast = require("forecast")
local ui = require("ui")

local SAMARA = {name = "Samara", country = "Russia", latitude = 53.2, longitude = 50.1}
local DATA = {current = {temperature = 17.4, feels_like = 15.2, code = 2, is_day = true}}

-- Every label and picture of the tree in order: what the widget shows.
local function shown(tree: any, out: any): any
    local found: any = out or {}
    if type(tree) ~= "table" then return found end
    if tree.kind == "label" then found[#found + 1] = tostring(tree.text) end
    if tree.kind == "image" then found[#found + 1] = "[" .. tostring(tree.image) .. "]" end
    for _, child in ipairs(type(tree.children) == "table" and tree.children or {}) do shown(child, found) end
    return found
end

local function overlap(plan: any): any
    for index, item in ipairs(plan.items) do
        for other = index + 1, #plan.items do
            local b = plan.items[other]
            local r = item.rect
            if not (r.x + r.w <= b.rect.x or b.rect.x + b.rect.w <= r.x
                or r.y + r.h <= b.rect.y or b.rect.y + b.rect.h <= r.y) then
                return tostring(item.node.kind) .. "/" .. tostring(b.node.kind)
            end
        end
    end
    return nil
end

-- The widget is 20×7, its body 18×5: the panel takes a cell on every side.
local function fits(tree: any, name: string)
    test.is_nil(ui.problem(tree), name .. ": " .. tostring(ui.problem(tree)))
    for _, cell in ipairs({false, {w = 10, h = 20}, {w = 8, h = 16}}) do
        local where = name .. (cell and (" @" .. cell.w .. "x" .. cell.h) or " cells")
        local plan = ui.plan(tree, 18, 5, ui.interaction(), cell and {cell = cell} or nil)
        for _, item in ipairs(plan.items) do
            local r = item.rect
            test.is_true(r.w >= 1 and r.h >= 1 and r.x >= 1 and r.y >= 1 and r.x + r.w - 1 <= 18 and r.y + r.h - 1 <= 5,
                where .. ": " .. tostring(item.node.kind) .. " outside the body")
        end
        test.is_nil(overlap(plan), where)
    end
end

local function define_tests()
    test.describe("weather widget", function()
        test.it("fresh data: the temperature with a picture, what it feels like, the city and the weather in words", function()
            local tree = widget_view.tree({place = SAMARA, data = DATA, age = 120})
            test.eq(table.concat(shown(tree), " | "),
                "[chicago.weather:images/sun_cloud] | +17° | Feels like +15° | Samara | Partly cloudy")
            fits(tree, "fresh")
        end)

        test.it("stale data: --° by the tray's rule, no picture, never the last temperature", function()
            local stale = widget_view.tree({place = SAMARA, data = DATA, age = forecast.STALE_S + 1})
            test.eq(table.concat(shown(stale), " | "), "--° | no fresh data | Samara | waiting for the service")
            fits(stale, "stale")
            -- The service does not answer: the reason as a line instead of the weather.
            local silent = widget_view.tree({place = SAMARA, data = DATA, age = nil,
                problem = "weather service is not running"})
            test.eq(table.concat(shown(silent), " | "),
                "--° | no fresh data | Samara | weather service is not running")
            fits(silent, "silent")
        end)

        test.it("no city: says so, and where to pick one", function()
            local tree = widget_view.tree({})
            test.eq(table.concat(shown(tree), " | "), "No city |  | No city selected | open Weather to pick one")
            fits(tree, "no city")
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
