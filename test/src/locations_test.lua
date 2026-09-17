local test = require("test")
local locations = require("locations")
local function define_tests()
    test.describe("widget-owned weather locations", function()
        test.it("keeps different cities independent and reuses fresh forecasts", function()
            local cache, calls = {}, {n = 0}
            local function fetch(place: any): any calls.n = calls.n + 1; return {city = place.name}, nil end
            local a = {name = "Tbilisi", latitude = 41.7, longitude = 44.8}
            local b = {name = "Berlin", latitude = 52.5, longitude = 13.4}
            test.eq(locations.get(cache, a, 100, fetch).data.city, "Tbilisi")
            test.eq(locations.get(cache, b, 100, fetch).data.city, "Berlin")
            test.eq(locations.get(cache, a, 160, fetch).age, 60)
            test.eq(calls.n, 2)
            local failed = locations.get(cache, a, 1000, function() return nil, "offline" end)
            test.eq(failed.error, "offline")
            test.eq(failed.data.city, "Tbilisi")
            test.eq(locations.get(cache, b, 200, fetch).error, nil)
        end)
        test.it("rejects invalid locations and bounds the service cache", function()
            test.eq(locations.get({}, {}, 0, function() error("must not fetch") end).ok, false)
            local cache = {}
            for i = 1, 40 do locations.get(cache, {name = tostring(i), latitude = i, longitude = i}, i, function() return {} end) end
            local count = 0
            for _ in pairs(cache) do count = count + 1 end
            test.eq(count, 32)
        end)
    end)
end
local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
