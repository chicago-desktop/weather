-- The weather widget on the Chicago shell's desktop (FR-006 §9).
--
-- No network and no database here, as in the window: once a minute it asks
-- the weather service for the summary with the same `weather.ask` →
-- `weather.reply` and draws it with `widget_view`'s tree. A service that does
-- not answer is a dash and a reason, not the last temperature passed off as
-- the current one.
local app = require("app")
local process = require("process")
local forecast = require("forecast")
local widget_view = require("widget_view")

local definition: any = {interval = "60s"}

-- Ask for the summary. A silent service takes the freshness away: `age = nil`
-- is "--°" by the tray's rule.
local function ask(model: any)
    local pid = process.registry.lookup(forecast.SERVICE)
    if not pid then
        model.problem, model.age = "weather service is not running", nil
        return
    end
    local sent, err = process.send(pid, forecast.ASK, {op = model.configured_place and "get_location" or "get", place = model.configured_place})
    if not sent then model.problem, model.age = "request not sent: " .. tostring(err), nil end
end

function definition.init(args: any, context: any): any
    local model: any = {place = nil, data = nil, age = nil, problem = nil, replies = nil}
    if type(args) == "table" and args.place ~= nil then
        local place, err = forecast.place(args.place)
        if not place then model.problem = tostring(err); model.invalid_config = true; return model end
        model.configured_place = place
    end
    -- The subscription comes BEFORE the first question: a quick answer that
    -- arrived earlier would land in the inbox, where nobody reads it.
    local replies = process.listen(forecast.REPLY, {message = true})
    model.replies = replies
    if replies and context.watch then context.watch(replies) end
    ask(model)
    return model
end

function definition.update(model: any, action: any, context: any): any
    if action.type == "channel" then
        if not action.ok then
            model.problem, model.age = "the reply channel closed", nil
            return nil
        end
        local body: any = forecast.unwrap(action.value:payload())
        if body.ok == false then
            model.problem = tostring(body.error or "the weather service refused")
            return nil
        end
        model.problem = body.error
        model.place, model.data, model.age = body.place, body.data, tonumber(body.age)
        return nil
    elseif action.type == "tick" then
        if model.invalid_config then return false end
        -- The answer comes as its own action; a redraw now is needed only
        -- when asking failed.
        local before = model.problem
        ask(model)
        if model.problem == before then return false end
        return nil
    end
    return false
end

function definition.view(model: any, context: any): any
    return widget_view.tree(model, context)
end

function definition.dispose(model: any, context: any)
    if model.replies then process.unlisten(model.replies) end
end

return {main = app.main(definition), definition = definition}
