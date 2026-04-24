//+------------------------------------------------------------------+
//| Inputs.mqh — user-facing inputs, 1:1 with MT4 baseline.          |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_INPUTS_MQH
#define TBM_MT5_INPUTS_MQH

//=== Tick Levels (tick counter per price bin) ===
bool  ShowTickLevels     = true;       // Turn ON/OFF Tick Order Flow (TOF)
color TickColor          = clrBlack;
int   TickWidth          = 2;          // Don't Change
ENUM_LINE_STYLE TickStyle = STYLE_SOLID;
input int    TickMinCount        = 100;  // SCAN TOF - Min Volume
int   TickExtendBars     = 3;          // Draw TOF line by X Candles
bool  TickUntilDone      = true;       // true => Draw TOF till RETEST
double TickBinSize       = 0.0;        // 0=auto (1 pip FX, 0.1 XAU)
bool  TickResetDaily     = true;       // Reset Scan TOF every day
bool  TickManualResetNow = false;      // True - reset now and make a save

//=== Tick persistence across timeframes (CSV writes) ===
bool  PersistTickAcrossTF = true;      // True - save TOF multi TF
int   PersistSaveEverySec = 60;        // Make a save TOF every X sec

//=== Tick direction arrows ===
bool  ShowTickArrows     = true;
color TickArrowBuyColor  = clrDodgerBlue;
color TickArrowSellColor = clrRed;
double TickArrowOffset   = 1;          // Size of marks (1.5 * bin)

//=== Positions ===
input int    MagicNumber       = 1;     // Magic Number (change for multi asset)
input int    maxSpread         = 45;    // Max Spread (points)
input double lotSize           = 0.01;  // Starting Lot Size
input double max_Lot           = 0.00;  // Max Lot (0 = disabled)
input double lotMultiplier     = 1.5;   // Lot Multiplier
input int    tpRange           = 50;    // Take Profits (points)
input int    startBe           = 5;     // Find Exit after X Losing Trades
input int    bePoints          = 10;    // Breakeven + Take Profit (points)
input double dailyProfit       = 0.0;   // Daily Profit in % (0 = off)
input double dailyLost         = 0.0;   // Daily Loss in % (0 = off)
input bool   scenarioA         = false; // Scenario A: BE lot on oldest position
input bool   scenarioB         = false; // Scenario B: Multiplier averaging
input bool   scenarioC         = false; // Scenario C: Near/far distance averaging
input bool   scenarioD         = true;  // Scenario D: Farthest-position multiplier
input int    closeTimeHour     = 23;    // Close ALL Hour (24 = off)
input int    closeTimeMinute   = 45;    // Close Minutes
input int    timeFilter        = 30;    // Time Filter (seconds)
input bool   autoCloseTrigger  = true;  // Auto Close Trigger

//=== Volume-Weighted S/R Zones (TP amplifier) ===
input bool   useSRZones     = false;    // Enable volume-weighted S/R zone detection
input int    lookbackPeriod = 20;       // Scan left & right
input int    vol_len        = 2;        // Length window for highest/lowest vol
input int    atr_period     = 200;      // ATR Wilder (back)
input double box_withd      = 1.0;      // Range on ATR Zone
input bool   print_updates  = true;     // Logs
input double tpMultiplier   = 5.0;      // Change TP - multiplier of Starting Lot

//=== Dashboard ===
input bool ShowDashboard = true; // Show on-chart dashboard
input int  DashX         = 20;   // Dashboard X offset (pixels)
input int  DashY         = 30;   // Dashboard Y offset (pixels)

//=== Market Direction ===
input int    maPeriod          = 21;   // Flow Line (low = aggressive, high = neutral)
input int    slopeLookbackBars = 3;    // Bars to calculate
input double slopeThresholdPts = 15.0; // Edge (low = aggressive, high = neutral)

//=== Trading windows (HHMM per day) ===
input string _MON = "=== MONDAY (HHMM) ===";
input int MonSet1Start = 0;
input int MonSet1End   = 0;
input int MonSet2Start = 0;
input int MonSet2End   = 0;
input int MonSet3Start = 0;
input int MonSet3End   = 0;

input string _TUE = "=== TUESDAY (HHMM) ===";
input int TueSet1Start = 0;
input int TueSet1End   = 0;
input int TueSet2Start = 0;
input int TueSet2End   = 0;
input int TueSet3Start = 0;
input int TueSet3End   = 0;

input string _WED = "=== WEDNESDAY (HHMM) ===";
input int WedSet1Start = 0;
input int WedSet1End   = 0;
input int WedSet2Start = 0;
input int WedSet2End   = 0;
input int WedSet3Start = 0;
input int WedSet3End   = 0;

input string _THU = "=== THURSDAY (HHMM) ===";
input int ThuSet1Start = 0;
input int ThuSet1End   = 0;
input int ThuSet2Start = 0;
input int ThuSet2End   = 0;
input int ThuSet3Start = 0;
input int ThuSet3End   = 0;

input string _FRI = "=== FRIDAY (HHMM) ===";
input int FriSet1Start = 0;
input int FriSet1End   = 0;
input int FriSet2Start = 0;
input int FriSet2End   = 0;
input int FriSet3Start = 0;
input int FriSet3End   = 0;

input string _SAT = "=== SATURDAY (HHMM) ===";
input int SatSet1Start = 0;
input int SatSet1End   = 0;
input int SatSet2Start = 0;
input int SatSet2End   = 0;
input int SatSet3Start = 0;
input int SatSet3End   = 0;

input string _SUN = "=== SUNDAY (HHMM) ===";
input int SunSet1Start = 0;
input int SunSet1End   = 0;
input int SunSet2Start = 0;
input int SunSet2End   = 0;
input int SunSet3Start = 0;
input int SunSet3End   = 0;

#endif // TBM_MT5_INPUTS_MQH
