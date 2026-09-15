-- The forecast library on Open-Meteo answers recorded on 2026-09-15 (no
-- network in tests): the forecast for Samara, a refusal for a latitude out of
-- range, and the geocoder asked for "Samara" in English and in Russian
-- (the name typed in Cyrillic). The raw answers are kept in test/src/fixtures/ as they came.
local test = require("test")
local json = require("json")
local forecast = require("forecast")

local SAMARA = [[{"latitude":53.1875,"longitude":50.125,"generationtime_ms":0.25093555450439453,"utc_offset_seconds":14400,"timezone":"Europe/Samara","timezone_abbreviation":"GMT+4","elevation":117.0,"current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"°C","apparent_temperature":"°C","relative_humidity_2m":"%","weather_code":"wmo code","wind_speed_10m":"m/s","wind_direction_10m":"°","pressure_msl":"hPa","is_day":""},"current":{"time":"2026-09-15T12:00","interval":900,"temperature_2m":18.5,"apparent_temperature":18.5,"relative_humidity_2m":78,"weather_code":3,"wind_speed_10m":3.00,"wind_direction_10m":90,"pressure_msl":1017.0,"is_day":1},"daily_units":{"time":"iso8601","weather_code":"wmo code","temperature_2m_max":"°C","temperature_2m_min":"°C","precipitation_probability_max":"%"},"daily":{"time":["2026-09-15","2026-09-16","2026-09-17","2026-09-18","2026-09-19","2026-09-20","2026-09-21"],"weather_code":[3,80,3,45,45,3,3],"temperature_2m_max":[19.8,21.4,16.6,17.6,18.8,21.0,21.4],"temperature_2m_min":[13.3,15.3,12.1,10.3,8.7,11.9,13.7],"precipitation_probability_max":[30,53,10,0,0,5,6]}}]]
local REFUSAL = [[{"reason":"Latitude must be in range of -90 to 90°. Given: 999.0.","error":true}]]
local GEOCODE_EN = [[{"results":[{"id":499099,"name":"Samara","latitude":53.20767,"longitude":50.13553,"elevation":107.0,"feature_code":"PPLA","country_code":"RU","admin1_id":499068,"timezone":"Europe/Samara","population":1163399,"country_id":2017370,"country":"Russia","admin1":"Samara Oblast"},{"id":339686,"name":"Debre Tabor","latitude":11.85,"longitude":38.01667,"elevation":2692.0,"feature_code":"PPL","country_code":"ET","admin1_id":444180,"timezone":"Africa/Addis_Ababa","population":125300,"country_id":337996,"country":"Ethiopia","admin1":"Amhara"},{"id":6913519,"name":"Semera","latitude":11.79342,"longitude":41.00578,"elevation":433.0,"feature_code":"PPLA","country_code":"ET","admin1_id":444179,"timezone":"Africa/Addis_Ababa","population":50000,"country_id":337996,"country":"Ethiopia","admin1":"Afar Region"},{"id":1166275,"name":"Samaro","latitude":25.28143,"longitude":69.39623,"elevation":18.0,"feature_code":"PPL","country_code":"PK","admin1_id":1164807,"admin2_id":9072726,"timezone":"Asia/Karachi","population":8784,"country_id":1168579,"country":"Pakistan","admin1":"Sindh","admin2":"Umerkot District"},{"id":3621990,"name":"Sámara","latitude":9.88147,"longitude":-85.52809,"elevation":10.0,"feature_code":"PPL","country_code":"CR","admin1_id":3623582,"admin2_id":3622715,"admin3_id":11239401,"timezone":"America/Costa_Rica","population":1071,"country_id":3624060,"country":"Costa Rica","admin1":"Guanacaste Province","admin2":"Nicoya","admin3":"Sámara"},{"id":668121,"name":"Sămara","latitude":44.82574,"longitude":24.71409,"elevation":315.0,"feature_code":"PPL","country_code":"RO","admin1_id":686192,"admin2_id":670074,"timezone":"Europe/Bucharest","population":571,"country_id":798549,"country":"Romania","admin1":"Arges","admin2":"Comuna Poiana Lacului"},{"id":179406,"name":"Thamara","latitude":-0.83333,"longitude":37.06667,"elevation":1539.0,"feature_code":"PPL","country_code":"KE","admin1_id":185578,"timezone":"Africa/Nairobi","country_id":192950,"country":"Kenya","admin1":"Murang'A"},{"id":247005,"name":"Samrā’","latitude":31.19889,"longitude":35.65139,"elevation":858.0,"feature_code":"PPL","country_code":"JO","admin1_id":250625,"timezone":"Asia/Amman","country_id":248816,"country":"Jordan","admin1":"Karak"},{"id":499097,"name":"Samara","latitude":59.96944,"longitude":34.38556,"elevation":119.0,"feature_code":"PPL","country_code":"RU","admin1_id":536199,"timezone":"Europe/Moscow","country_id":2017370,"country":"Russia","admin1":"Leningradskaya Oblast'"},{"id":499098,"name":"Samara","latitude":54.01264,"longitude":38.83453,"elevation":166.0,"feature_code":"PPL","country_code":"RU","admin1_id":500059,"timezone":"Europe/Moscow","country_id":2017370,"country":"Russia","admin1":"Ryazan Oblast"}],"generationtime_ms":1.0552406}]]
local GEOCODE_RU = [[{"results":[{"id":499099,"name":"Самара","latitude":53.20767,"longitude":50.13553,"elevation":107.0,"feature_code":"PPLA","country_code":"RU","admin1_id":499068,"timezone":"Europe/Samara","population":1163399,"country_id":2017370,"country":"Россия","admin1":"Самарская Область"},{"id":499097,"name":"Самара","latitude":59.96944,"longitude":34.38556,"elevation":119.0,"feature_code":"PPL","country_code":"RU","admin1_id":536199,"timezone":"Europe/Moscow","country_id":2017370,"country":"Россия","admin1":"Ленинградская область"},{"id":499098,"name":"Самара","latitude":54.01264,"longitude":38.83453,"elevation":166.0,"feature_code":"PPL","country_code":"RU","admin1_id":500059,"timezone":"Europe/Moscow","country_id":2017370,"country":"Россия","admin1":"Рязанская Область"},{"id":499100,"name":"Самара","latitude":52.35827,"longitude":34.99753,"elevation":243.0,"feature_code":"PPL","country_code":"RU","admin1_id":514801,"timezone":"Europe/Moscow","country_id":2017370,"country":"Россия","admin1":"Орловская Область"},{"id":1493153,"name":"Самара","latitude":54.91667,"longitude":60.91667,"elevation":270.0,"feature_code":"PPL","country_code":"RU","admin1_id":1508290,"timezone":"Asia/Yekaterinburg","country_id":2017370,"country":"Россия","admin1":"Челябинская"},{"id":2017247,"name":"Самара","latitude":53.849,"longitude":102.0126,"elevation":454.0,"feature_code":"PPL","country_code":"RU","admin1_id":2023468,"timezone":"Asia/Irkutsk","country_id":2017370,"country":"Россия","admin1":"Иркутская Область"},{"id":2017248,"name":"Самара","latitude":47.82883,"longitude":131.22842,"elevation":68.0,"feature_code":"PPL","country_code":"RU","admin1_id":2026639,"timezone":"Asia/Vladivostok","country_id":2017370,"country":"Россия","admin1":"Еврейская АО"}],"generationtime_ms":0.71394444}]]

local function decode(text: string): any
    local value, err = json.decode(text)
    if err then error("fixture is not JSON: " .. tostring(err)) end
    return value
end

local function define_tests()
    test.describe("forecast library", function()
        test.it("parse: the recorded answer — the zone, every current field, seven days field by field", function()
            local raw = decode(SAMARA)
            local parsed, err = forecast.parse(raw)
            test.not_nil(parsed, tostring(err))
            test.eq(parsed.timezone, "Europe/Samara")
            local now, cur = parsed.current, raw.current
            test.eq(now.time, cur.time)
            test.eq(now.temperature, cur.temperature_2m)
            test.eq(now.feels_like, cur.apparent_temperature)
            test.eq(now.humidity, cur.relative_humidity_2m)
            test.eq(now.code, math.tointeger(cur.weather_code))
            test.eq(now.wind, cur.wind_speed_10m)
            test.eq(now.wind_direction, cur.wind_direction_10m)
            test.eq(now.pressure, cur.pressure_msl)
            test.eq(now.is_day, cur.is_day == 1)
            test.eq(#parsed.days, 7)
            for index, day in ipairs(parsed.days) do
                test.eq(day.date, raw.daily.time[index])
                test.eq(day.code, math.tointeger(raw.daily.weather_code[index]))
                test.eq(day.max, raw.daily.temperature_2m_max[index])
                test.eq(day.min, raw.daily.temperature_2m_min[index])
                test.eq(day.precipitation, raw.daily.precipitation_probability_max[index])
            end
            test.eq(forecast.weekday(parsed.days[1].date), "Tue", "the first day's weekday")
        end)

        test.it("parse: a refusal is named, never an empty summary", function()
            local refused, why = forecast.parse(decode(REFUSAL))
            test.is_nil(refused)
            test.eq(why, "Open-Meteo: Latitude must be in range of -90 to 90°. Given: 999.0.")
            local raw = decode(SAMARA)
            raw.current.temperature_2m = nil
            local cold, cwhy = forecast.parse(raw)
            test.is_nil(cold)
            test.eq(cwhy, "the forecast has no current temperature")
            local blank, bwhy = forecast.parse({})
            test.is_nil(blank)
            test.eq(bwhy, "the forecast has no current temperature")
            local text, twhy = forecast.parse("sunny")
            test.is_nil(text)
            test.eq(twhy, "the forecast is not an object")
        end)

        test.it("places: the recorded geocoder answers in two languages; a row that is not a city is skipped", function()
            local english = forecast.places(decode(GEOCODE_EN))
            test.eq(#english, 10)
            test.eq(english[1].name .. "|" .. tostring(english[1].admin1) .. "|" .. tostring(english[1].country),
                "Samara" .. "|" .. "Samara Oblast" .. "|" .. "Russia")
            test.eq(forecast.label(english[1]), "Samara, Samara Oblast, Russia")
            local russian = forecast.places(decode(GEOCODE_RU))
            test.eq(#russian, 7)
            test.eq(russian[1].name, "Самара")
            local mixed = forecast.places({results = {{name = "Nowhere"}, {name = "Samara", latitude = 53.2, longitude = 50.15},
                {name = "", latitude = 1, longitude = 1}, "text"}})
            test.eq(#mixed, 1, "only the row with a name and both coordinates")
            test.eq(#forecast.places({}), 0, "no results: no cities, not an error")
            local far, fwhy = forecast.place({name = "Pole", latitude = 91, longitude = 0})
            test.is_nil(far)
            test.eq(fwhy, "the city has no latitude")
        end)

        test.it("urls: whole-degree coordinates as decimals, a Russian name encoded byte by byte, the language by script", function()
            local url = forecast.forecast_url({latitude = 53, longitude = -50})
            test.not_nil(string.find(url, "?latitude=53.0000&longitude=-50.0000&", 1, true), url)
            test.eq(string.sub(url, 1, #forecast.FORECAST_URL), forecast.FORECAST_URL)
            local nowhere = forecast.forecast_url({})
            test.not_nil(string.find(nowhere, "?latitude=0.0000&longitude=0.0000&", 1, true), nowhere)
            local russian = forecast.geocoder_url("Самара")
            test.eq(russian, forecast.GEOCODER_URL .. "?name=%D0%A1%D0%B0%D0%BC%D0%B0%D1%80%D0%B0&count=10&format=json&language=ru")
            test.eq(forecast.geocoder_url("New York"), forecast.GEOCODER_URL .. "?name=New%20York&count=10&format=json&language=en")
            test.eq(forecast.encode("a-b_c.d~e9"), "a-b_c.d~e9", "unreserved characters stay")
            test.eq(forecast.encode("a&b=c"), "a%26b%3Dc")
        end)

        test.it("captions: codes in words, pictures by day and night, degrees with a sign, compass points, weekdays", function()
            test.eq(forecast.describe(2) .. "|" .. forecast.describe(42) .. "|" .. forecast.describe(nil), "Partly cloudy|code 42|?")
            local sun_image, sun_icon = forecast.icon(0, true)
            local moon_image, moon_icon = forecast.icon(0, false)
            test.eq(sun_image .. "|" .. sun_icon .. "|" .. moon_image .. "|" .. moon_icon,
                "chicago.weather:images/sun|☼|chicago.weather:images/moon|☾")
            test.eq(select(1, forecast.icon(63, true)), "chicago.weather:images/rain")
            test.eq(select(1, forecast.icon(95, true)), "chicago.weather:images/storm")
            test.eq(select(1, forecast.icon(73, true)), "chicago.weather:images/snow")
            test.eq(select(1, forecast.icon(48, true)), "chicago.weather:images/fog")
            test.eq(table.concat({forecast.degrees(17.4), forecast.degrees(-2.5), forecast.degrees(0.4), forecast.degrees(nil)}, "|"),
                "+17°|-3°|0°|--°")
            test.eq(table.concat({forecast.compass(0), forecast.compass(225), forecast.compass(359), forecast.compass(nil)}, "|"),
                "N|SW|N|")
            test.eq(forecast.weekday("2026-09-15") .. "|" .. forecast.weekday("2024-02-29") .. "|" .. forecast.weekday("x"), "Tue|Thu|?")
            test.eq(forecast.query_language("Самара") .. "|" .. forecast.query_language("Samara"), "ru|en")
        end)

        test.it("tray: no city, fresh data from the recording, stale data — three states apart", function()
            local place = forecast.places(decode(GEOCODE_EN))[1]
            local data = forecast.parse(decode(SAMARA))
            local text, title, image, icon = forecast.tray(place, data, 60)
            local want_image, want_icon = forecast.icon(data.current.code, data.current.is_day)
            test.eq(text, forecast.degrees(data.current.temperature))
            test.eq(title, place.name .. ": " .. forecast.describe(data.current.code) .. ", " .. text .. "C")
            test.eq(tostring(image) .. "|" .. tostring(icon), want_image .. "|" .. want_icon)
            local stale, stitle, simage = forecast.tray(place, data, forecast.STALE_S + 1)
            test.eq(stale .. "|" .. stitle .. "|" .. tostring(simage), "--°|" .. place.name .. ": no fresh data|nil")
            local never = forecast.tray(place, data, nil)
            test.eq(never, "--°", "data that never arrived is stale too")
            local none, ntitle = forecast.tray(nil, data, 60)
            test.eq(none .. "|" .. ntitle, "No city|Weather: no city selected")
        end)

        test.it("unwrap: a message's one-element array, a plain table, and not a table", function()
            test.eq(forecast.unwrap({{op = "get"}}).op, "get")
            test.eq(forecast.unwrap({op = "search"}).op, "search")
            test.is_nil(next(forecast.unwrap("text")), "not a table: an empty body")
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
