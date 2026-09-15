-- Weather: one representation of the value for the service, the window, the
-- widget and the tray.
--
-- The service parses the Open-Meteo answer into this shape; the window, the
-- widget and the tray draw from it. The parsing lives here once: two parsers
-- of one answer would drift apart on the first field only one side needs.
--
-- Pure functions only — no network, database or processes — so a test checks
-- them without a running application.

local forecast = {}

-- The name the service is registered under, and the topics of talking to it.
forecast.SERVICE = "chicago.weather"
forecast.ASK = "weather.ask"
forecast.REPLY = "weather.reply"

-- The window a click on the tray item opens, and the tray item's key.
forecast.WINDOW = "chicago.weather:window"
forecast.TRAY_KEY = "chicago.weather"

-- Data older than this is no longer "now". The tray then shows a dash, not the
-- last temperature: a caption that does not change for hours looks healthy
-- and lies the more convincingly the longer it hangs there.
forecast.STALE_S = 60 * 60

-- WMO weather codes, as Open-Meteo gives them (`weather_code`).
local CODES: {[integer]: string} = {
    [0] = "Clear sky", [1] = "Mainly clear", [2] = "Partly cloudy", [3] = "Overcast",
    [45] = "Fog", [48] = "Rime fog",
    [51] = "Light drizzle", [53] = "Drizzle", [55] = "Dense drizzle",
    [56] = "Freezing drizzle", [57] = "Freezing drizzle",
    [61] = "Light rain", [63] = "Rain", [65] = "Heavy rain",
    [66] = "Freezing rain", [67] = "Freezing rain",
    [71] = "Light snow", [73] = "Snow", [75] = "Heavy snow", [77] = "Snow grains",
    [80] = "Rain showers", [81] = "Rain showers", [82] = "Violent showers",
    [85] = "Snow showers", [86] = "Snow showers",
    [95] = "Thunderstorm", [96] = "Thunderstorm, hail", [99] = "Thunderstorm, hail",
}

-- describe(code) -> text. An unknown code is named by its number, not left
-- empty: an empty cell in the forecast table reads as "no weather".
function forecast.describe(code: any): string
    local number = math.tointeger(tonumber(code))
    if number == nil then return "?" end
    return CODES[number] or ("code " .. tostring(number))
end

-- The picture for a code and the time of day. `image` is a picture of the
-- module's image pack `chicago.weather:images` (assets/images, PNG
-- in 32 and 16, drawn by tools/weather_icons.py); the shell finds the pack in
-- the registry by `meta.type: chicago.images` and rereads the file every few
-- seconds. `icon` is one character one cell wide for a theme without
-- graphics: ⛅ and ⚡ are left out on purpose, they are two cells wide and would
-- push the taskbar apart.
forecast.IMAGES = "chicago.weather:images"
local ICONS: {[string]: {image: string, icon: string}} = {
    sun = {image = forecast.IMAGES .. "/sun", icon = "☼"},
    moon = {image = forecast.IMAGES .. "/moon", icon = "☾"},
    sun_cloud = {image = forecast.IMAGES .. "/sun_cloud", icon = "☼"},
    moon_cloud = {image = forecast.IMAGES .. "/moon_cloud", icon = "☾"},
    cloud = {image = forecast.IMAGES .. "/cloud", icon = "☁"},
    fog = {image = forecast.IMAGES .. "/fog", icon = "≡"},
    rain = {image = forecast.IMAGES .. "/rain", icon = "☂"},
    snow = {image = forecast.IMAGES .. "/snow", icon = "❄"},
    storm = {image = forecast.IMAGES .. "/storm", icon = "↯"},
}

function forecast.icon(code: any, is_day: any): (string, string)
    local number = math.tointeger(tonumber(code)) or -1
    local day = is_day ~= false
    local kind = "cloud"
    if number == 0 then kind = day and "sun" or "moon"
    elseif number == 1 or number == 2 then kind = day and "sun_cloud" or "moon_cloud"
    elseif number == 3 then kind = "cloud"
    elseif number == 45 or number == 48 then kind = "fog"
    elseif (number >= 51 and number <= 67) or (number >= 80 and number <= 82) then kind = "rain"
    elseif (number >= 71 and number <= 77) or number == 85 or number == 86 then kind = "snow"
    elseif number >= 95 then kind = "storm" end
    local chosen: any = ICONS[kind] or ICONS.cloud
    return tostring(chosen.image), tostring(chosen.icon)
end

local function round(value: number): integer
    local rounded = value >= 0 and math.floor(value + 0.5) or -math.floor(-value + 0.5)
    return math.tointeger(rounded) or 0
end

-- degrees(value) -> "+17°" | "-3°" | "0°" | "--°"
--
-- The plus sign is written, as in weather reports: otherwise "17°" in summer
-- and "17°" of a frost that lost its sign look the same.
function forecast.degrees(value: any): string
    local number = tonumber(value)
    if number == nil then return "--°" end
    local whole = round(number)
    if whole > 0 then return "+" .. whole .. "°" end
    return tostring(whole) .. "°"
end

-- The wind's direction — where it blows from, eight points.
local POINTS = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
function forecast.compass(degrees: any): string
    local number = tonumber(degrees)
    if number == nil then return "" end
    local index = round((number % 360) / 45) % 8 + 1
    return POINTS[index] or ""
end

-- The day of the week of a "YYYY-MM-DD" date (Sakamoto's method). No `time`
-- module here: the date comes in the city's time zone, and converting it to
-- the application's zone would be wrong — "today" differs between cities
-- around midnight.
local WEEKDAYS = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
local OFFSETS = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
function forecast.weekday(date: any): string
    local y, m, d = tostring(date):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not y then return "?" end
    local year, month, day = math.tointeger(tonumber(y)) or 0, math.tointeger(tonumber(m)) or 1,
        math.tointeger(tonumber(d)) or 1
    if month < 3 then year = year - 1 end
    local offset = OFFSETS[month]
    if offset == nil then return "?" end
    local index = (year + year // 4 - year // 100 + year // 400 + offset + day) % 7
    return WEEKDAYS[index + 1] or "?"
end

local function field(source: any, key: string): any
    if type(source) ~= "table" then return nil end
    return source[key]
end

local function number_at(list: any, index: integer): any
    if type(list) ~= "table" then return nil end
    return tonumber(list[index])
end

-- parse(decoded) -> {current, days, timezone} | nil, reason
--
-- The shape is checked whole: an answer without `current` or without a
-- temperature is a refusal, not "empty". Otherwise the service would keep an
-- empty summary as fresh, and the tray would show a dash as the weather.
function forecast.parse(decoded: any): (any, string?)
    if type(decoded) ~= "table" then return nil, "the forecast is not an object" end
    if decoded.error then return nil, "Open-Meteo: " .. tostring(decoded.reason or "error") end
    local current = decoded.current
    if type(current) ~= "table" or tonumber(current.temperature_2m) == nil then
        return nil, "the forecast has no current temperature"
    end

    local out: any = {
        timezone = decoded.timezone,
        current = {
            time = current.time,
            temperature = tonumber(current.temperature_2m),
            feels_like = tonumber(current.apparent_temperature),
            humidity = tonumber(current.relative_humidity_2m),
            code = math.tointeger(tonumber(current.weather_code)),
            wind = tonumber(current.wind_speed_10m),
            wind_direction = tonumber(current.wind_direction_10m),
            pressure = tonumber(current.pressure_msl),
            is_day = tonumber(current.is_day) == 1,
        },
        days = {},
    }

    local daily = decoded.daily
    local dates = field(daily, "time")
    if type(dates) == "table" then
        for index, date in ipairs(dates) do
            out.days[#out.days + 1] = {
                date = tostring(date),
                code = math.tointeger(number_at(field(daily, "weather_code"), index)),
                max = number_at(field(daily, "temperature_2m_max"), index),
                min = number_at(field(daily, "temperature_2m_min"), index),
                precipitation = number_at(field(daily, "precipitation_probability_max"), index),
            }
        end
    end
    return out, nil
end

-- place(raw) -> {name, admin1, country, latitude, longitude, timezone} | nil, reason
--
-- One check for two inputs: a geocoder row and the city the window sends back
-- on "Use city". The second is not to be believed — it is the body of someone
-- else's message, and what is saved goes into every later request to
-- Open-Meteo.
function forecast.place(raw: any): (any, string?)
    if type(raw) ~= "table" then return nil, "the city is not an object" end
    local name = type(raw.name) == "string" and raw.name or ""
    if name == "" or #name > 120 then return nil, "the city has no name" end
    local latitude, longitude = tonumber(raw.latitude), tonumber(raw.longitude)
    if latitude == nil or latitude < -90 or latitude > 90 then return nil, "the city has no latitude" end
    if longitude == nil or longitude < -180 or longitude > 180 then return nil, "the city has no longitude" end
    local function text(value: any): any
        if type(value) == "string" and value ~= "" and #value <= 120 then return value end
        return nil
    end
    return {name = name, admin1 = text(raw.admin1), country = text(raw.country),
        latitude = latitude, longitude = longitude, timezone = text(raw.timezone)}, nil
end

-- places(decoded) -> the geocoder's rows that are cities, in its order. A row
-- that is not one is skipped rather than failing the whole search: the
-- geocoder has villages without a time zone and entries without a name.
function forecast.places(decoded: any): any
    local found: any = {}
    local rows = type(decoded) == "table" and decoded.results or nil
    for _, raw in ipairs(type(rows) == "table" and rows or {}) do
        local place = forecast.place(raw)
        if place then found[#found + 1] = place end
    end
    return found
end

-- label(place) -> "Samara, Samara Oblast, Russia"
function forecast.label(place: any): string
    if type(place) ~= "table" then return "" end
    local parts = {tostring(place.name)}
    if place.admin1 and place.admin1 ~= place.name then parts[#parts + 1] = place.admin1 end
    if place.country then parts[#parts + 1] = place.country end
    return table.concat(parts, ", ")
end

-- query_language(text) -> "ru" | "en"
--
-- Open-Meteo's geocoder looks the name up in the query's language: "Samara"
-- typed in Cyrillic with `language=en` answers an empty list (measured
-- 2026-09-11), in Latin letters three cities. So the language follows the
-- script the person typed.
function forecast.query_language(text: any): string
    if tostring(text or ""):find("[\128-\255]") then return "ru" end
    return "en"
end

-- ─── the two requests ──────────────────────────────────────────────────

forecast.FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
forecast.GEOCODER_URL = "https://geocoding-api.open-meteo.com/v1/search"
local CURRENT = "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,"
    .. "wind_speed_10m,wind_direction_10m,pressure_msl,is_day"
local DAILY = "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"

-- encode(text) -> the text percent-encoded byte by byte (RFC 3986 unreserved
-- characters stay). The hex is built by hand: in go-lua `string.format("%02X")`
-- with an integer prints the bytes of the number's text, so a space went out
-- as "%3332" and the geocoder was asked for garbage.
local HEX = "0123456789ABCDEF"
function forecast.encode(value: any): string
    return (tostring(value):gsub("[^%w%-_%.~]", function(char: string): string
        local byte = string.byte(char)
        local high, low = byte // 16 + 1, byte % 16 + 1
        return "%" .. string.sub(HEX, high, high) .. string.sub(HEX, low, low)
    end))
end

-- forecast_url(place) -> the forecast request for a city. The coordinates are
-- made floats first: in go-lua `%.4f` with an integer prints
-- "%!f(lua.LInteger=0)". `tonumber` already answers a float there; the
-- integer is the fallback 0 of a place without coordinates.
function forecast.forecast_url(place: any): string
    return forecast.FORECAST_URL
        .. "?latitude=" .. string.format("%.4f", (tonumber(place.latitude) or 0) + 0.0)
        .. "&longitude=" .. string.format("%.4f", (tonumber(place.longitude) or 0) + 0.0)
        .. "&current=" .. CURRENT .. "&daily=" .. DAILY
        .. "&timezone=auto&forecast_days=7&wind_speed_unit=ms"
end

-- geocoder_url(text) -> the city search in the language of the text's script.
function forecast.geocoder_url(text: any): string
    return forecast.GEOCODER_URL .. "?name=" .. forecast.encode(text)
        .. "&count=10&format=json&language=" .. forecast.query_language(text)
end

-- tray(place, data, age_s) -> caption, title, image, icon
--
-- The caption is what fits next to the clock; the title is the whole phrase.
-- Three states are told apart on screen: no city, fresh data, data gone stale
-- or never arrived.
function forecast.tray(place: any, data: any, age_s: any): (string, string, string?, string?)
    if type(place) ~= "table" then return "No city", "Weather: no city selected", nil, nil end
    local where = tostring(place.name)
    local age = tonumber(age_s)
    if type(data) ~= "table" or type(data.current) ~= "table" or age == nil or age > forecast.STALE_S then
        return "--°", where .. ": no fresh data", nil, nil
    end
    local now = data.current
    local image, icon = forecast.icon(now.code, now.is_day)
    return forecast.degrees(now.temperature),
        where .. ": " .. forecast.describe(now.code) .. ", " .. forecast.degrees(now.temperature) .. "C",
        image, icon
end

-- unwrap(value) -> a message's body as a table. A message arrives wrapped:
-- the payload is userdata, and inside may be a one-element array; a field read
-- directly would be nil without an error. One rule for the service, the
-- window and the widget.
function forecast.unwrap(value: any): any
    if type(value) == "userdata" then
        local ok, decoded = pcall(function() return value:data() end)
        if ok and type(decoded) == "table" then return forecast.unwrap(decoded) end
        return {}
    end
    if type(value) ~= "table" then return {} end
    if value[1] ~= nil and #value > 0 then return forecast.unwrap(value[1]) end
    return value
end

return forecast
