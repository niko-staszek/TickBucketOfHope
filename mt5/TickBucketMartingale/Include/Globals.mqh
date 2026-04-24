//+------------------------------------------------------------------+
//| Globals.mqh — runtime state mirrored from the MT4 baseline.      |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_GLOBALS_MQH
#define TBM_MT5_GLOBALS_MQH

//=== Session / time windows ===
datetime startHour        = 0;
datetime endHour          = 0;
datetime currentCandle    = 0;
datetime closeAllHour     = 0;
datetime m15Candle        = 0;
datetime positionBuyTime  = 0;
datetime positionSellTime = 0;

int year = 0, month = 0, day_ = 0;
int baseScenarioCSellOrder = 0;
int baseScenarioCBuyOrder  = 0;

MqlDateTime str1;
MqlDateTime dt;

bool scenarioCSellActive = false;
bool scenarioCBuyActive  = false;

double accountDailyProfit = 0.0;
double accountDailyLost   = 0.0;

int  Start[21];
int  End[21];
bool gTradingStoppedToday = false;

//=== Volume-weighted S/R zone state (TP amplifier) ===
double   gSupportTop = 0, gSupportBottom = 0, gResistanceBottom = 0, gResistanceTop = 0;
datetime gLastSupTime = 0, gLastResTime = 0;

//=== Dashboard runtime state ===
bool     g_eaStopped         = false;
int      g_statsViewMode     = 0;   // 0=today, 1=week, 2=month
datetime g_lastButtonCheck   = 0;
datetime g_lastStatsRefresh  = 0;

int      g_closedBuyToday=0, g_closedSellToday=0;
int      g_closedBuyWeek=0,  g_closedSellWeek=0;
int      g_closedBuyMonth=0, g_closedSellMonth=0;
double   g_profitBuyToday=0, g_profitSellToday=0;
double   g_profitBuyWeek=0,  g_profitSellWeek=0;
double   g_profitBuyMonth=0, g_profitSellMonth=0;

//=== Max drawdown tracking (Live Metrics panel) ===
double   g_maxDDToday      = 0.0;
double   g_maxDDEver       = 0.0;
double   g_peakEquityToday = 0.0;
double   g_peakEquityEver  = 0.0;
int      g_ddDayKey        = 0;

double margine    = 0.0;
double freeMargin = 0.0;

//=== Tick bucket engine (P4) ===
struct TickBucket
  {
   double   price_bin;
   int      count;
   datetime first_time;
   datetime last_time;
   bool     level_created;
  };
TickBucket tick_buckets[];
int        tick_bucket_cnt = 0;
int        last_bucket_day = -1;
double     g_lastTickPrice = 0.0;

//=== On-chart volume/level registry (P4) ===
struct VolumeLevel
  {
   datetime        date;
   datetime        start_time;
   datetime        end_time;
   double          price;
   string          color_name;   // "Tick","TickBuy","TickSell","Yellow","Blue","Red","Green"
   color           line_color;
   int             line_width;
   ENUM_LINE_STYLE line_style;
   bool            resolved;
   string          object_name;
   long            max_volume;
   ENUM_TIMEFRAMES source_timeframe;
  };
VolumeLevel levels[];
int      levels_count       = 0;
int      max_levels         = 40000;
datetime last_data_save     = 0;
datetime last_history_check = 0;

string data_folder   = "VolumeLevels\\";
string symbol_folder = "";
string tick_file     = "";

double symbol_point     = 0.0;
double symbol_pip_value = 0.0;

//=== MA slope handle (cached; MT5 iMA is handle-based, not on-demand like MT4) ===
int g_maHandleSlope = INVALID_HANDLE;

//=== Scenario C internal averaging state (shared with scenarios) ===
struct CAvg
  {
   ulong  tk;
   double price;
   double lot;
  };
CAvg  cAvgsBuy[];
CAvg  cAvgsSell[];
int   cAvgCountBuy = 0, cAvgCountSell = 0;
double cBasePrice = 0.0;
double cBaseLot   = 0.0;
ulong  cBaseTk    = 0;
ulong  cBaseBuyTk   = 0,   cBaseSellTk   = 0;
double cBaseBuyPrice= 0.0, cBaseSellPrice= 0.0;
double cBaseBuyLot  = 0.0, cBaseSellLot  = 0.0;

#endif // TBM_MT5_GLOBALS_MQH
