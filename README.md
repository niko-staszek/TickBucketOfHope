# tickBucketOfHope

Tick-density entry EA for **MT4 and MT5** with four selectable martingale/averaging scenarios, a basket TP, a per-day-of-week session filter, and an on-chart dashboard for Positions + Controls.

The mechanism: **count ticks in price bins, enter when a bin's count crosses a threshold, manage the resulting basket with one of four martingale/averaging strategies.**

- **MT4 version**: `TickBucketMartingale.mq4` + `TickBucketMartingale.set` at repo root.
- **MT5 version**: `mt5/TickBucketMartingale/` — see [`mt5/TickBucketMartingale/README.md`](mt5/TickBucketMartingale/README.md) for MT5-specific notes and install path.

Both versions are behaviorally 1:1 aside from platform-forced differences (listed below). This repo is the **bare port**; experimental work (dynamic lot sizing, scenario combos, extra safeties) lives in the sibling `TickBucketOfWisdom` repo.

---

## How it works

- **Entry: tick-bucket threshold.** Every tick's price is rounded to a bin (1 pip FX, 10c XAU, or a custom `TickBinSize`). When any bin's tick count crosses `TickMinCount`, a level is stamped there. If the current tick direction agrees with the MA-slope filter, a trade opens at that level.
- **Adverse move: one of four scenarios.** Only one scenario should be enabled at a time (A/B/C/D). Each uses a different rule for sizing the next add and re-leveling the basket TP.
- **Exit: local basket TP.** Positions carry TP = 0 at the broker. The EA re-levels an in-memory TP to the basket's weighted break-even + `bePoints`; when price touches it, the EA closes the whole side manually.
- **Time filter.** Per-day, up to 3 session windows (HHMM format). Outside windows entries are blocked; `autoCloseTrigger` optionally flushes positions when leaving the last window.
- **Daily risk.** Optional daily-profit and daily-loss caps (% of balance). Either tripped → close-all + flag trading stopped for the day.
- **Support/Resistance zones (optional).** A volume-weighted pivot detector (`aiZone`) computes support/resistance bands; inside them, the basic TP is multiplied by `tpMultiplier`.
- **Dashboard.** Two panels (MoneyDancer-inspired visual style): **Positions** (closed buy/sell/total P&L per period, open basket counts, floating P&L, margin%) and **Controls** (close-profit-side, close-all-side, close-all, stop/start EA).

---

## What it is (detail)

The EA's entry signal is intentionally simple. Every tick, the current price is binned, the bin's tick count is incremented, and once any bin's count clears `TickMinCount` the EA treats that bin as a "significant level" and stamps it. If the last tick's price is higher than the previous tick's, it's a buy signal; lower is a sell signal. The MA slope filter (`MarketSlopeSignal`) then gates whether a trade actually opens — a buy signal in a down-sloping market is dropped.

Once a position is open, basket management takes over. All four scenarios (A/B/C/D) share the same exit mechanism: re-level every position's TP to the **weighted break-even of the basket + `bePoints`**. Where they differ is in **how the next add is sized** and **when it's allowed**:

- **Scenario A** (BE-lot on oldest position) — solves for the exact lot that would bring the oldest position to break-even + `bePoints` if the new trade hits its TP. Not a multiplier; it's a pure math lot.
- **Scenario B** (multiplier) — each new add uses `lastAdd.lots × lotMultiplier`. Classic martingale.
- **Scenario C** (near/far split) — if price is moving further from the last add (by more than a hysteresis band), uses the multiplier; if close, uses the base lot. Avoids stacking big lots on a recovering basket.
- **Scenario D** (farthest-position multiplier) — finds the farthest-from-base position and uses *its* lot as the reference for the multiplier. Default-on.

Unlike broker-side TPs, the EA's local TP mechanism survives partial broker fills, reconnects, and re-attachments. TPs are written to a per-symbol/account .txt in `MQL4\Files\` on deinit and reloaded on init.

The dashboard is cosmetic for the core trading logic but exposes a **STOP EA** button that flips a global flag gating `OpenPositions()` — so STOP genuinely pauses new entries (it does not close existing ones unless the user also clicks CLOSE ALL).

---

## Tick-loop order

What happens each `OnTick()`, in sequence:

1. **Dashboard + stats** — refresh period stats (throttled to 10s), redraw the panels, poll button click states (cooldown ≥ 1s).
2. **Time-filter gate** — `IsTradingTime()` returns the active session; if none is active, exit the tick.
3. **Daily candle check** — on new D1 bar, reset `gTradingStoppedToday`, compute `closeAllHour`, log margin snapshots.
4. **Daily risk check** — if `AccountProfit()` ≥ target or ≤ stop-loss, `CloseAllOrders` + flag `gTradingStoppedToday`.
5. **End-of-window trigger** — if `autoCloseTrigger = true` and past `endHour`, and current floating loss is within 10% of realized day-profit, close all.
6. **Close-all-hour** — at `closeTimeHour:closeTimeMinute` (if < 24), close everything.
7. **Local TP scan** — `CheckAndCloseLocalTPs` walks the in-memory TP table and closes any position whose price is through its local TP.
8. **Scenario C bookkeeping** — if the tracked "base" sell/buy ticket has closed, reset the per-side averaging arrays.
9. **Tick bucket processing** — `ProcessTickBuckets` bins the current Bid, increments count, and if threshold crossed creates a new level (and routes the signal through `OpenPositions`).
10. **Periodic save** — every `PersistSaveEverySec` seconds, flush tick buckets to CSV.
11. **M15 reset** — on new M15 candle, clear all tick buckets and levels (daily-reset option also refires here).
12. **AI zone refresh** — `AISupportResistance` recomputes support/resistance bands (every tick in live, every M15 bar in tester).

---

## Subsystems

**Tick bucket detector.** Rolling `TickBucket[]` array; each entry is `{price_bin, count, first_time, last_time, level_created}`. On every tick, `ProcessTickBuckets` rounds the Bid to `DefaultBinSize()`, increments the bin, and when `count >= TickMinCount` stamps a level (deduped against `LevelExistsNear`). Direction is inferred from last-vs-current tick price. Buckets reset daily (`TickResetDaily`) and on new M15 bar. Optionally persisted across timeframe switches via CSV (`PersistTickAcrossTF`, `PersistSaveEverySec`).

**MA slope filter.** Single EMA of `maPeriod`. Slope measured as `(MA[0] - MA[slopeLookbackBars]) / Point / slopeLookbackBars`. If slope > `+slopeThresholdPts` → bullish (+1), < `-slopeThresholdPts` → bearish (−1), otherwise neutral (0). Buy signals require slope ≥ 0; sell signals require slope ≤ 0.

**Basket management.** `GroupTP_BEPlusX_All` computes the weighted-average open price across all tickets on a side, offsets by `bePoints` in the favorable direction, clamps against broker stop/freeze levels (`ClampTPToStops`), then each position's TP is updated via the local TP table (`AddOrUpdateLocalTP`). No broker-side `OrderModify` is used — all TPs are local.

**Scenario A (BE-lot math).** `RequiredLotForBEPlusX(dir, p1, l1, p2, tp, x)` algebraically solves `(l1 × (p1 − tp) + l2 × (p2 − tp)) = 0` with a `bePoints` offset. Uses the oldest open position as `p1,l1` and the current price as `p2`. Only used when enabled via `scenarioA`.

**Scenario B (multiplier).** `NextLotByMultiplier(baseLot) = baseLot × lotMultiplier`, normalized to the broker's lotstep. Reference lot is the last-opened non-base ticket.

**Scenario C (near/far).** Tracks its own averaging arrays (`cAvgsSell[]`, `cAvgsBuy[]`) plus a "base" ticket. Hysteresis = `max(2 × Point, DefaultBinSize()/5)`. If price is further from last-avg by more than the hysteresis → uses multiplier lot (stores the add in the array, updates basket TP). Otherwise uses base lot with its own TP (not part of basket). `GVKeyC_Threshold` stored via MT4 Global Variables.

**Scenario D (farthest-reference multiplier).** Default-enabled. `FindFarthestTicket_NoComments` picks the ticket with the largest `|openPrice − basePrice|`; its lot is the reference. If current price is further than that ticket's distance, uses multiplier lot; otherwise uses base lot.

**Local TP table.** `localOrders[]` array of `{ticket, localTP, order_type}`. Persisted to `positions_backup_<symbol>_<login>.txt` on `OnDeinit`, reloaded on `OnInit`. `CheckAndCloseLocalTPs` runs every tick: BUY closes if `Bid >= localTP`, SELL closes if `Ask <= localTP`. `CleanUpClosedPositions` prunes entries whose tickets moved to history.

**AI zones (support/resistance).** Volume-weighted pivot algorithm. Walks bars backward, maintains RMA(TR) for ATR, accumulates signed tick volume (`posVol` — `negVol`), detects pivot highs/lows on close, and stamps a zone when the pivot price agrees with a cumulative-volume threshold. Bands are `pivot ± ATR × box_withd`. Inside a support (for buys) or resistance (for sells) band, basic-entry TP is widened to `tpRange × tpMultiplier`.

**Time filter.** 7 days × 3 session windows × (start HHMM + end HHMM) = 42 integer inputs. `ToMinutes(HHMM)` converts to minutes-of-day. `IsTradingTime()` picks today's 3 slots, validates (start < end, no overlap) and checks if current minute is within any active window. `UpdateStartEndFromSets()` computes `startHour` / `endHour` for the EA's entry gate.

**Daily risk layer.** Two independent limits: `dailyProfit` (close-all on hitting +X% of balance) and `dailyLost` (close-all on −X%). Snapshotted at the start of each D1 candle. `autoCloseTrigger` also closes if past end-of-window and current floating loss eats more than 10% of the realized day profit.

**Dashboard.** Two panels, MoneyDancer color palette (`C'24,28,36'` etc.):
- **Positions panel** — TODAY/WEEK/MONTH toggle, Buy/Sell/Total counts + net P/L (color-coded), open basket counts, floating P/L, margin %.
- **Controls panel** — `+ PROFIT SELL/BUY` (close only winners on that side), `X ALL SELL/BUY`, `!! CLOSE ALL !!`, `STOP EA / START EA` toggle.

Button clicks route through both `OnChartEvent` (instant) and `OnTick` polling (fallback, 1s cooldown). Stats are recomputed every 10s in `RefreshPeriodStats` which walks `OrdersHistoryTotal()` once.

---

## MT4 vs MT5 — what's different

Same algorithm, same scenarios, same dashboard. Forced platform deltas:

| | MT4 | MT5 |
|---|---|---|
| Account type | Any | **Hedging only** (EA refuses netting accounts in `OnInit`). |
| Take-profit mechanism | Local TP table (`positions_backup_<symbol>_<login>.txt`) | Real broker-side position TPs via `TRADE_ACTION_SLTP`. |
| `magic` input name | `magic` | `MagicNumber` (MT5 standard library uses `magic` internally). |
| `aiZone` input name | `aiZone` | `useSRZones` (renamed — it's not AI, it's a volume-weighted pivot detector). |
| `AISupportResistance()` | same name | Renamed to `DetectSRZones()` for accuracy. |
| Tick bucket file | `tick_file` globally set (empty in original) | Named `tickbuckets_<symbol>_<magic>.csv` on init. |

Trading behavior and all scenario logic match 1:1. Parameter defaults are identical for parameters that exist on both.

---

## Parameters

### Tick-Bucket Detector

Core entry-signal threshold.

| Parameter | Default | Purpose |
|---|---|---|
| `TickMinCount` | `100` | Min tick count per bin before stamping a level and opening a trade |

### Positions / Lots / TP

| Parameter | Default | Purpose |
|---|---|---|
| `magic` *(MT5: `MagicNumber`)* | `1` | Magic number for order filtering (change per asset when running multi-chart) |
| `maxSpread` | `45` | Reject entries when spread exceeds this |
| `lotSize` | `0.01` | Base lot size |
| `max_Lot` | `0.0` | Hard lot cap (0 = unlimited) |
| `lotMultiplier` | `1.5` | Multiplier for Scenario B/C/D averaging lots |
| `tpRange` | `50` | TP distance in points for basic (non-basket) entries |
| `startBe` | `5` | Number of open positions on a side before scenarios kick in |
| `bePoints` | `10` | Basket TP offset: `TP = weighted-BE + bePoints` in favorable direction |
| `timeFilter` | `30` | Min seconds between same-direction entries |
| `autoCloseTrigger` | `true` | Close all when past end-of-window and loss > 10% of day profit |
| `closeTimeHour` | `23` | Hour to force-close everything (24 = disabled) |
| `closeTimeMinute` | `45` | Minute for the close-all hour |

### Daily Risk

| Parameter | Default | Purpose |
|---|---|---|
| `dailyProfit` | `0.0` | Daily profit target in % of balance (0 = off). Close-all + pause on hit. |
| `dailyLost` | `0.0` | Daily loss stop in % of balance (0 = off). Close-all + pause on hit. |

### Scenarios

Enable exactly one (scenarioD is the default-on).

| Parameter | Default | Purpose |
|---|---|---|
| `scenarioA` | `false` | BE-lot math: sizes the next add to break even the oldest position |
| `scenarioB` | `false` | Classic multiplier: each add = last add × `lotMultiplier` |
| `scenarioC` | `false` | Near/far split: multiplier only when price is further than hysteresis |
| `scenarioD` | `true` | Farthest-position multiplier: reference lot is the farthest-open ticket's lot |

### MA Slope Filter

| Parameter | Default | Purpose |
|---|---|---|
| `maPeriod` | `21` | EMA period |
| `slopeLookbackBars` | `3` | Bars to measure slope across |
| `slopeThresholdPts` | `15.0` | Min slope strength (points/bar) to confirm a direction |

### Volume-Weighted S/R Zones

*(Historically called "AI zones". Not ML — a classic pivot + volume + ATR bander.)*

| Parameter | Default | Purpose |
|---|---|---|
| `aiZone` *(MT5: `useSRZones`)* | `false` | Enable volume-weighted pivot zones |
| `lookbackPeriod` | `20` | Pivot left/right window size |
| `vol_len` | `2` | Window for highest/lowest cumulative volume |
| `atr_period` | `200` | ATR (Wilder) period for band width |
| `box_withd` | `1.0` | Band half-width = `ATR × box_withd` |
| `tpMultiplier` | `5.0` | TP multiplier when entry price is inside a zone |
| `print_updates` | `true` | Log pivot/zone updates to Experts tab |

### Dashboard

| Parameter | Default | Purpose |
|---|---|---|
| `ShowDashboard` | `true` | Show on-chart Positions + Controls panels |
| `DashX` | `20` | Dashboard X offset in pixels (from top-left corner) |
| `DashY` | `30` | Dashboard Y offset in pixels |

### Trading Hours (42 integers, 3 sessions × 7 days)

`_MON` … `_SUN` are display-only divider inputs (strings like `"=== MONDAY (HHMM) ==="`).

For each day, three `{Start, End}` session pairs in **HHMM** integer format. `Start == End` means that session is **disabled**. `End > Start` required within a session; sessions within a day must be non-overlapping and ordered.

| Parameter (example) | Default | Purpose |
|---|---|---|
| `MonSet1Start` / `MonSet1End` | `0` / `0` | Monday session 1 window |
| `MonSet2Start` / `MonSet2End` | `0` / `0` | Monday session 2 |
| `MonSet3Start` / `MonSet3End` | `0` / `0` | Monday session 3 |
| …repeats for Tue–Sun | | |

Example: `MonSet1Start=400, MonSet1End=1300` = Monday 04:00–13:00.

---

## Dashboard

```
┌─ >> POSITIONS ─────────────────────────[TODAY][WEEK][MONTH]─┐
│ BUY:   12  +42.10           OPEN:    3 B   2 S              │
│ SELL:   8   -8.30           FLOAT:   +$1.40                 │
│ TOTAL: 20  +$33.80          MARGIN %: 2148.00               │
└──────────────────────────────────────────────────────────────┘
┌─ >> CONTROLS ────────────────────────────────────────────────┐
│ [+ PROFIT SELL] [+ PROFIT BUY] [X ALL SELL] [X ALL BUY]      │
│ [!! CLOSE ALL !!]                              [[] STOP EA]  │
└──────────────────────────────────────────────────────────────┘
```

- **TODAY / WEEK / MONTH** — switches which period's closed-trade stats are shown in the BUY/SELL/TOTAL rows.
- **+ PROFIT SELL / + PROFIT BUY** — closes only the currently-profitable positions on that side. Losing positions stay open.
- **X ALL SELL / X ALL BUY** — closes every position on that side, regardless of P/L.
- **!! CLOSE ALL !!** — closes everything AND flips the EA to stopped.
- **STOP EA / START EA** — toggle. When stopped, `OpenPositions()` returns early; existing positions are untouched.

All buttons respect symbol + magic — other EAs on the chart are unaffected.

---

## Gotchas

- **Only one scenario should be enabled at a time.** The code allows multiple flags to be true, but the call order in `OpenPositions` means enabling both B and D will run both on every averaging event — each appending a new position. This is almost certainly not what you want.
- **[MT4 only] Local TPs die if the EA is removed without `OnDeinit` firing.** `SavePositionData` writes the TP table only on clean deinit. A crash or forced detach leaves open positions with no TP anywhere. Re-attaching the EA on the same symbol+account reloads from `positions_backup_<symbol>_<login>.txt` — so don't delete that file. *(Does not apply to MT5 — positions carry real broker TPs.)*
- **`closeTimeHour = 24` disables the close-all-hour.** Any value 0–23 enables it. There's no separate on/off switch.
- **`autoCloseTrigger` is a passive flush.** It waits until the current tick's floating loss exceeds 10% of the day's realized profit AND the time is past `endHour`. If losses never hit that ratio, positions ride through the close.
- **Session `Start == End` means OFF, not 24h.** Unlike some EAs, there's no "all zeros = trade all day" convention — zero-zero means the session is simply skipped. You need at least one non-zero session per day to trade.
- **Tick buckets reset on new M15 candle.** Even if `TickResetDaily = true` and it's the same day, every M15 rollover wipes the bucket array. Long-duration clustering cannot accumulate across bars.
- **`aiZone` zones update every tick in live mode.** If you see the EA eating CPU on slow machines, this is why. In the tester it's throttled to new-M15-candle refresh.
- **Scenario C threshold persists across restarts.** `SC_C_THRESHOLD_<symbol>_<magic>_<dir>` lives in MT4 Global Variables. If you delete the basket manually but the Global Variable isn't reset, the next tick may re-trigger at the old threshold. Check the Global Variables panel (`F3`) if behavior looks stale.
- **Button clicks need both `OnChartEvent` AND `OnTick`.** `OnChartEvent` catches the click immediately; the `OnTick` polling path is a 1-second-cooldown fallback. If you disable tick events (unlikely), buttons still work.
- **STOP EA does NOT close positions.** It gates new entries only. Use CLOSE ALL to flatten and stop together.
- **Slope filter is directional-gate only.** It doesn't size anything. A weak slope just blocks entry; it doesn't shrink the lot.

---

## Installation

### MT4

1. Copy `TickBucketMartingale.mq4` to `<MT4 data folder>\MQL4\Experts\`.
   - Find your data folder via **File → Open Data Folder** in MT4.
2. Open MetaEditor (F4 in MT4), load the file, compile (F7). Should produce `TickBucketMartingale.ex4` with no errors.
3. Refresh Navigator (right-click → Refresh) and drag the EA onto a chart.
4. Copy `TickBucketMartingale.set` to `<MT4 data folder>\MQL4\Presets\`. Click **Load** in the Inputs tab when attaching.
5. Verify: dashboard appears at `DashX,DashY`; Experts log shows `Tick Bucket Martingale EA …`; Auto-Trading is enabled.

### MT5

1. Copy the whole `mt5/TickBucketMartingale/` folder to `<MT5 data folder>\MQL5\Experts\TickBucketMartingale\`.
   - The folder structure with `TickBucketMartingale.mq5` + `Include/*.mqh` must be preserved.
   - Find your data folder via **File → Open Data Folder** in MT5.
2. Open MetaEditor (F4), load `TickBucketMartingale.mq5`, compile (F7). Produces `TickBucketMartingale.ex5`.
3. **Hedging account required** — the EA refuses to initialize on netting accounts. For MT5 brokers that offer both modes, create a dedicated hedging demo/live account.
4. Copy `mt5/TickBucketMartingale/TickBucketMartingale.set` to `<MT5 data folder>\MQL5\Presets\`.
5. Drag the EA onto a chart; **Load** the preset in the Inputs tab.
6. Verify: dashboard appears; Experts log shows `TickBucketMartingale MT5 v1.00 — init OK`.

See [`mt5/TickBucketMartingale/README.md`](mt5/TickBucketMartingale/README.md) for the MT5-specific quick-start.

---

## Conventions

- **Risk thresholds are % of balance**, not dollars (matches `dailyProfit` / `dailyLost`).
- **Direction integers** follow MT4: `OP_BUY = 0`, `OP_SELL = 1`. Scenario helper parameters named `buyORsell` use `0 = buy, 1 = sell`; those named `dir` use the MT4 constants directly.
- **All trades filter by `Symbol()` + `magic`.** Other EAs on the same chart are ignored.
- **Tick buckets are symbol-local.** Running multi-symbol multi-chart requires a unique `magic` per chart and each chart maintains its own bucket state.
- **No broker-side TP/SL.** Every TP the EA cares about lives in the local table. Do not manually set SL/TP on EA-owned tickets — they'll be ignored.
