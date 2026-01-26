# Mudlet DPS Tracker

Class-agnostic DPS tracker for Mudlet, built with Muddler. It parses damage lines, tracks critical hits, computes raw DPS (crit multipliers factored out), tallies damage by type, compares strategies, and persists sessions across restarts.

## Structure

- src/scripts/DPS: core `dps` script (auto-initializes)
- src/aliases/DPS: control aliases (`dps start|stop|report|compare`)
- src/triggers/DPS: regex triggers for damage (`Damage dealt: N (type)`) and critical-hit notifications


## Usage (in Mudlet)

- Start tracking: `dps start STRATNAME`
- Stop tracking: `dps stop`
- Help/usage: `dps` or `dps help`
- Report one or all: `dps report [STRATNAME]`
- Compare all strategies: `dps compare`
- Optional: set auto session label: `dps setname STRATNAME`
 - Rename a strategy: `dps rename OLD NEW`
 - Delete a strategy: `dps delete NAME`
 
Persistence:
- Sessions and totals persist across restarts in your Mudlet data dir under `@PKGNAME@/dps_data.json`.

Notes:
- DPS is computed from total damage divided by elapsed seconds between start/stop.
- Damage is parsed from lines like `Damage dealt: 1254 (psychic).` (and similar). If a type in parentheses is present, the tracker tallies per-type counts and totals.
 - Critical hits are tracked via lines like `You have scored a CRITICAL hit!` and `You have scored an OBLITERATING CRITICAL hit!`, and the next damage is classified as critical.
 - Critical types supported: CRITICAL, CRUSHING, OBLITERATING, ANNIHILATINGLY POWERFUL, WORLD-SHATTERING, PLANE-RAZING.
 - Raw DPS: we factor out crit multipliers (per Achaea wiki: 2x, 4x, 8x, 16x, 32x, 64x) to compute base damage DPS for fair strategy comparison.
 - Comparison view sorts by raw DPS and shows both raw and actual DPS.
 - Auto timing: session starts on first damage; timing pauses on balance/equilibrium regain when your bashing script isn't attacking (`keneanung.bashing.attacking == 0`), and resumes on the next damage. Session stops via `dps stop` or on logout ("You grow still ... out of the land."). No Mudlet events required.

## Build

From the project root, run:

```bash
muddler
```

Result: `build/dpstest.mpackage` and a `.output` file with metadata.

For help and details, see the Muddler wiki: https://github.com/demonnic/muddler/wiki/Usage

## Testing (CI & local)

- CI runs busted tests on Lua 5.1 via GitHub Actions.
- To run locally (if you have Lua 5.1 + LuaRocks):

```bash
luarocks install busted
busted -v
```

Tests use mocks for Mudlet APIs and a controllable clock to make timing deterministic.
