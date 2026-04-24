# TickBucketMartingale — MT5 port

MT5 build of the tick-bucket EA. Behaviorally 1:1 with the MT4 original at repo root — same scenarios, same dashboard, same session filter, same preset values.

For the **full algorithm description, parameter tables, and gotchas**, see the [root README](../../README.md). This file only covers MT5-specific bits.

---

## Layout

```
mt5/TickBucketMartingale/
├── TickBucketMartingale.mq5        ← main file
├── TickBucketMartingale.set        ← preset (MT5 input names)
└── Include/
    ├── Dashboard.mqh               ← Positions + Live Metrics + Controls panels
    ├── Globals.mqh                 ← runtime state + scenario-C arrays
    ├── History.mqh                 ← period stats from deal history
    ├── Inputs.mqh                  ← all `input` declarations
    ├── Persistence.mqh             ← tick bucket CSV, daily margin log
    ├── SRZones.mqh                 ← volume-weighted S/R zone detector
    ├── Scenarios.mqh               ← scenarios A/B/C/D + OpenPositions dispatcher
    ├── Session.mqh                 ← weekday session windows
    ├── TickBuckets.mqh             ← tick counter engine + MA slope filter
    ├── Trade.mqh                   ← CTrade + CPositionInfo wrappers
    └── Utils.mqh                   ← DayKey/WeekKey, NormalizeLots, Ask/Bid helpers
```

---

## Install

1. **Open data folder in MT5**: `File → Open Data Folder`.
2. Copy the entire `mt5/TickBucketMartingale/` folder into `MQL5\Experts\`. The result should be:
   ```
   <data folder>\MQL5\Experts\TickBucketMartingale\
       TickBucketMartingale.mq5
       Include\*.mqh
   ```
3. Open MetaEditor (F4), open `TickBucketMartingale.mq5`, **Compile** (F7). Expect `0 errors, 0 warnings`.
4. Copy `TickBucketMartingale.set` into `MQL5\Presets\`.
5. In MT5, refresh the Navigator, drag the EA onto a chart, and **Load** the preset in the Inputs tab.

Enable **Algo Trading** in the toolbar.

---

## Hedging account requirement

MT5 has two margin modes: **netting** (Buy + Sell on the same symbol collapse into one net position) and **hedging** (positions coexist independently).

This EA's design assumes two independent baskets (Buy basket + Sell basket running side-by-side). Netting would silently break that. The `OnInit` guard aborts with:

```
TickBucketMartingale(MT5): aborting — account margin mode is <N>;
requires ACCOUNT_MARGIN_MODE_RETAIL_HEDGING (2).
```

Most MT5 forex brokers offer hedging accounts on request; FTMO's MT5 challenges are hedging by default.

---

## MT4 → MT5 changes

Same behavior, different plumbing:

| Concern | MT4 original | MT5 port |
|---|---|---|
| Trade API | `OrderSend` / `OrderSelect` / `OrderClose` | `CTrade` + `CPositionInfo` from `<Trade/…>` |
| Order history | `OrdersHistoryTotal` + closed orders | `HistorySelect` + `DEAL_ENTRY_OUT` filter on deals |
| Take profit | Local table (`localOrders[]`) polled every tick | Real broker-side position TPs via `PositionModify` |
| Free-margin check | `AccountFreeMarginCheck` | `OrderCalcMargin` + `ACCOUNT_MARGIN_FREE` |
| MA slope | `iMA(...)` per tick | Cached handle in `Slope_Init`, sampled via `CopyBuffer` |
| Bar series | `Close[]`, `High[]`, etc. globals | `CopyClose`/`CopyHigh`/… into `ArraySetAsSeries(true)` arrays |
| `OrderType()` constants | `OP_BUY = 0`, `OP_SELL = 1` | Redefined at top of `Utils.mqh` to keep scenario code 1:1 |
| Day-of-week | `DayOfWeek()` | `MqlDateTime.day_of_week` via `TimeToStruct` |
| Time-of-day | `TimeHour()` / `TimeMinute()` | `MqlDateTime.hour` / `.min` |

---

## Input renames (load a preset written for MT4? translate these)

| MT4 input | MT5 input |
|---|---|
| `magic` | `MagicNumber` |
| `aiZone` | `useSRZones` |

All other inputs are identical. The MT5 `.set` at this folder already uses the MT5 names.

---

## Scope

This folder is the **bare port**. Experimental features (balance-proportional lots, scenario combo harness, leverage-aware safety, debug logging, stop-loss input, etc.) live in the sibling repo `TickBucketOfWisdom`. If you want to hack on the algorithm, fork from there, not from this folder.
