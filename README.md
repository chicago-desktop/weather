# chicago/weather

Weather for the Chicago desktop (`chicago/shell`):

- a **window** with the current weather, the week's forecast and a city search;
- the **temperature in the tray** next to the clock, on every running desktop;
- a **desktop widget** with the temperature, what it feels like, the city and
  the weather in words.

The data comes from [Open-Meteo](https://open-meteo.com), which needs no key.

## Parts

Namespace `chicago.weather`.

| Entry | What |
|---|---|
| `forecaster` + `forecaster.service` | The service. The only part that goes to the network and the database: it remembers the city, asks Open-Meteo every 15 minutes and refreshes the tray item every minute. Registered in the process registry as `chicago.weather`; actor `chicago.weather.forecaster`. |
| `window` | The window, in Programs. It asks the service with `weather.ask` and gets the answer on `weather.reply`; no network, no database. |
| `widget` + `widget_view` | The desktop widget (20×7), the same question once a minute; a click opens the window. |
| `forecast` | The pure library the others share: parsing Open-Meteo's answers, WMO codes, the two request URLs, captions, the tray's three states. |
| `settings` + `01_settings` | The settings table `chicago_weather_settings` (key → value; `place` is the chosen city as JSON) and its migration. |
| `images` | The image pack: 9 pictures in 32 and 16 px under `assets/images`, called `chicago.weather:images/<name>`. |

The tray item's key is `chicago.weather`. A tray item that was not
refreshed for 180 s is removed by the compositor, so a stopped service does not
leave a temperature behind. Data older than an hour is shown as `--°`, never as
the last temperature.

## What the application provides

| Requirement | Default | What |
|---|---|---|
| `chicago.weather:target_db` | `app:db` | The database of the settings table. The service reads it back from the migration entry. |
| `chicago.weather:process_host` | `app:processes` | The host the service runs on. |

```yaml
- name: chicago-weather
  kind: ns.dependency
  component: chicago/weather
  version: "*"
  parameters:
    - name: chicago.weather:target_db
      value: app:db
    - name: chicago.weather:process_host
      value: app:processes
```

The service is allowed only the two Open-Meteo hosts (`api.open-meteo.com`,
`geocoding-api.open-meteo.com`), `db.get` on the named database, `registry.get`
on its own migration entry, and the process registry.

### Moving from the stand's `src/app/weather`

Before this module the weather lived in an application's `src/app/weather`
(namespace `app.weather`, table `app_weather_settings`). The migration copies
the `place` row from `app_weather_settings` when that table exists, so the city
survives the switch. Where the table does not exist there is nothing to copy. A
city already in the new table wins. The entry ids moved to the new namespace:
`app.weather:window` → `chicago.weather:window`, and the same for
the service, the widget and the image pack.

## Development

```bash
make lint    # late locals, then `wippy lint` with the runtime fork's build
make test    # the harness in test/ boots the module with the shell and the base
make icons   # redraw assets/images/{32,16}/*.png
```

**A build of the runtime fork from its releases is required**
([chicago-desktop/runtime](https://github.com/chicago-desktop/runtime),
`v0.3.40a-chicago.2` or newer): it resolves the shell from GitHub by tag,
and the shell declares entries with the `gfx` module, which the release
runtime does not have. The Makefile uses
`~/repos/wippy/runtime/dist/wippy-linux-amd64`; override it with `WIPPY=…`.

`chicago/shell` and `chicago/tui-desktop` are resolved from their GitHub
repositories by tag (`component: github.com/chicago-desktop/shell`,
`version: ">=0.2.0"` in `src/_index.yaml`, the shell also in the harness;
v0.2.0 is the first tag). The module names the base itself although it
reaches it through the shell: the shell's own dependency on the base is a
Hub name, and the base is not in the Hub. No working copy of either is
needed beside the module: `cd test && wippy update` writes them into
`test/wippy.lock`, the first time by cloning them into `~/.wippy/git`.

The suites live in `test/src`, not in `src`: `exclude_meta: type: [test]` drops test
entries from a module loaded as a dependency, and the harness loads it as one.
Tests run without the network. The forecast library is checked on Open-Meteo
answers recorded on 2026-09-15, kept verbatim in `test/src/fixtures/`.

## License

MIT.
