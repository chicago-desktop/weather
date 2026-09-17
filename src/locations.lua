-- Bounded cache for widget-owned locations; never reads or changes the tray city.
local forecast = require("forecast")
local locations = {}
function locations.get(cache: any, candidate: any, now: number, fetch: any): any
    local place, err = forecast.place(candidate)
    if not place then return {ok = false, error = tostring(err)} end
    local key = tostring(place.latitude) .. ":" .. tostring(place.longitude)
    local item = cache[key]
    if not item then
        local count, oldest, stamp = 0, nil, math.huge
        for id, value in pairs(cache) do
            count = count + 1
            if value.used < stamp then oldest, stamp = id, value.used end
        end
        if count >= 32 and oldest then cache[oldest] = nil end
        item = {attempted = nil, fetched = nil, used = now}
        cache[key] = item
    end
    item.used = now
    if item.attempted == nil or now - item.attempted >= (item.error and 120 or 900) then
        item.attempted = now
        local data, failure = fetch(place)
        if data then item.data, item.fetched, item.error = data, now, nil else item.error = tostring(failure) end
    end
    local age = item.fetched and now - item.fetched or nil
    return {op = "get", ok = true, place = place, data = item.data, age = age,
        stale = age == nil or age > forecast.STALE_S, error = item.error}
end
return locations
