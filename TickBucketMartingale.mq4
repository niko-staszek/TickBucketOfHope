//+------------------------------------------------------------------+
//|                                        Tick Bucket Martingale EA |
//|                              Tick density entry + averaging exits |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "4.2"
#property strict


//=== Tick Levels (tick counter per price bin)
bool ShowTickLevels    = true;       // Turn ON/OFF Tick Order Flow (TOF)
color TickColor        = clrBlack;
int   TickWidth        = 2;          // Don't Change
ENUM_LINE_STYLE TickStyle = STYLE_SOLID;
input int   TickMinCount     = 100;        // SCAN TOF - Min Volume
int   TickExtendBars   = 3;          // Draw TOF line by X Candles
bool  TickUntilDone    = true;       // true => Draw TOF till RETEST
double TickBinSize     = 0.0;        // 0=auto (1 pip FX, 0.1 XAU)
bool  TickResetDaily   = true;       // Reset Scan TOF every day
bool  TickManualResetNow = false;    // True - reset now and make a save

//=== Tick persistence across timeframes (CSV writes)
bool  PersistTickAcrossTF = true;    // True - save TOF multi TF
int   PersistSaveEverySec = 60;      // Make a save TOF every X sec

//=== Tick direction arrows
bool  ShowTickArrows   = true;
color TickArrowBuyColor  = clrDodgerBlue;
color TickArrowSellColor = clrRed;
double TickArrowOffset   = 1;      // Size of marks (1.5 * bin)

//=== Positions
input int    magic   = 1;                   // Magic Number {change for multi asset)
input int    maxSpread = 45;                // Max Spread
input double lotSize = 0.01;                // Starting Lot Size
input double max_Lot = 0.00;                // Max Lot
input double lotMultiplier = 1.5;           // Lot Multiplier
input int    tpRange = 50;                  // Take Profits
input int    startBe = 5;                   // Find Exit after x Losing Trades
input int    bePoints = 10;                 // Breakeven + Take Profit (points)
input double dailyProfit   = 0.0;           // Daily Profit in % if 0 off
input double dailyLost     = 0.0;           // Daily Lost in % if 0 off
input bool   scenarioA = false;             // Scenario A: BE lot on oldest position
input bool   scenarioB = false;             // Scenario B: Multiplier averaging (1.5x)
input bool   scenarioC = false;             // Scenario C: Near/far distance averaging
input bool   scenarioD = true;              // Scenario D: Farthest-position multiplier
input int     closeTimeHour   = 23;         // Close ALL Hour (if 24 turn off)
input int     closeTimeMinute = 45;         // Close Minutes
input int timeFilter = 30;                  // Time Filter
input bool autoCloseTrigger = true;         // Auto Close Trigger

datetime startHour, endHour, currentCandle, closeAllHour,m15Candle, positionBuyTime, positionSellTime;
int year, month, day_, baseScenarioCSellOrder, baseScenarioCBuyOrder;
MqlDateTime str1, dt;
bool scenarioCSellActive = false;
bool scenarioCBuyActive = false;
double accountDailyProfit, accountDailyLost;

struct CAvg
  {
   int               tk;
   double            price;
   double            lot;
  };
CAvg   cAvgsSell[];
CAvg   cAvgsBuy[];

int    cAvgCountBuy = 0, cAvgCountSell = 0;
double cBasePrice = 0.0;
double cBaseLot   = 0.0;
int    cBaseTk    = 0;

int    cBaseBuyTk   = 0,   cBaseSellTk   = 0;
double cBaseBuyPrice= 0.0, cBaseSellPrice= 0.0;
double cBaseBuyLot  = 0.0, cBaseSellLot  = 0.0;

//--- Data and files
struct VolumeLevel
  {
   datetime          date;
   datetime          start_time;
   datetime          end_time;
   double            price;
   string            color_name;           // "Yellow","Blue","Red","Green","Tick","TickBuy","TickSell"
   color             line_color;
   int               line_width;
   ENUM_LINE_STYLE   line_style;
   bool              resolved;
   string            object_name;
   long              max_volume;
   ENUM_TIMEFRAMES   source_timeframe;
  };
VolumeLevel levels[];
int      levels_count       = 0;
int      max_levels         = 40000;
datetime last_data_save     = 0;
datetime last_history_check = 0;

string data_folder   = "VolumeLevels\\";
string symbol_folder = "";
string tick_file     = "";        // CSV file for tick counters

double symbol_point = 0;
double symbol_pip_value = 0;

//======= SUPPORT RESISTANCE ===========
input bool   aiZone         = false; // Ai Magic Zones
input int    lookbackPeriod = 20;    // Scan left&right
input int    vol_len        = 2;     // Lenght Window for higest/lowest Vol
input int    atr_period     = 200;   // ATR Wilder (back)
input double box_withd      = 1.0;   // Range on ATR Zone
input bool   print_updates  = true;  // Logs
input double tpMultiplier   = 5.0;   // Change TP - multipler of Starting Lot
double   gSupportTop=0, gSupportBottom=0, gResistanceBottom=0, gResistanceTop=0;
datetime gLastSupTime=0, gLastResTime=0;

//======== DASHBOARD ============
input bool ShowDashboard = true;               // Show on-chart dashboard
input int  DashX         = 20;                 // Dashboard X offset (pixels)
input int  DashY         = 30;                 // Dashboard Y offset (pixels)

// Dashboard runtime state
bool     g_eaStopped          = false;
int      g_statsViewMode      = 0;             // 0=today, 1=week, 2=month
datetime g_lastButtonCheck    = 0;
datetime g_lastStatsRefresh   = 0;
int      g_closedBuyToday=0,  g_closedSellToday=0;
int      g_closedBuyWeek=0,   g_closedSellWeek=0;
int      g_closedBuyMonth=0,  g_closedSellMonth=0;
double   g_profitBuyToday=0,  g_profitSellToday=0;
double   g_profitBuyWeek=0,   g_profitSellWeek=0;
double   g_profitBuyMonth=0,  g_profitSellMonth=0;

// Max drawdown tracking (MoneyDancer-style Live Metrics)
double   g_maxDDToday       = 0.0;
double   g_maxDDEver        = 0.0;
double   g_peakEquityToday  = 0.0;
double   g_peakEquityEver   = 0.0;
int      g_ddDayKey         = 0;

double margine = 0.0;
double freeMargin;

//============================== TESTER FAST MODE =============================
bool TesterFastMode()
  {
   return IsTesting();
  }


//======== MARKET DIRECTION ==============
input int    maPeriod          = 21;   // Flow Line (low = agressive, high = neutral)
input int    slopeLookbackBars = 3;    // Bars to Calculate
input double slopeThresholdPts = 15.0; // Edge (low = agressive, high = neutral)

// ---------- MONDAY ----------
input string _MON = "=== MONDAY (HHMM) ===";
input int MonSet1Start = 0;
input int MonSet1End   = 0;
input int MonSet2Start = 0;
input int MonSet2End   = 0;
input int MonSet3Start = 0;
input int MonSet3End   = 0;

// ---------- TUESDAY ----------
input string _TUE = "=== TUESDAY (HHMM) ===";
input int TueSet1Start = 0;
input int TueSet1End   = 0;
input int TueSet2Start = 0;
input int TueSet2End   = 0;
input int TueSet3Start = 0;
input int TueSet3End   = 0;

// ---------- WEDNESDAY ----------
input string _WED = "=== WEDNESDAY (HHMM) ===";
input int WedSet1Start = 0;
input int WedSet1End   = 0;
input int WedSet2Start = 0;
input int WedSet2End   = 0;
input int WedSet3Start = 0;
input int WedSet3End   = 0;

// ---------- THURSDAY ----------
input string _THU = "=== THURSDAY (HHMM) ===";
input int ThuSet1Start = 0;
input int ThuSet1End   = 0;
input int ThuSet2Start = 0;
input int ThuSet2End   = 0;
input int ThuSet3Start = 0;
input int ThuSet3End   = 0;

// ---------- FRIDAY ----------
input string _FRI = "=== FRIDAY (HHMM) ===";
input int FriSet1Start = 0;
input int FriSet1End   = 0;
input int FriSet2Start = 0;
input int FriSet2End   = 0;
input int FriSet3Start = 0;
input int FriSet3End   = 0;

// ---------- SATURDAY ----------
input string _SAT = "=== SATURDAY (HHMM) ===";
input int SatSet1Start = 0;
input int SatSet1End   = 0;
input int SatSet2Start = 0;
input int SatSet2End   = 0;
input int SatSet3Start = 0;
input int SatSet3End   = 0;

// ---------- SUNDAY ----------
input string _SUN = "=== SUNDAY (HHMM) ===";
input int SunSet1Start = 0;
input int SunSet1End   = 0;
input int SunSet2Start = 0;
input int SunSet2End   = 0;
input int SunSet3Start = 0;
input int SunSet3End   = 0;

int Start[21], End[21];
bool gTradingStoppedToday = false;

//============================== INIT/DEINIT ==============================
int OnInit()
  {
   ArrayResize(levels, max_levels);
   CalculateSymbolParameters();

   if(!TesterFastMode())
     {
      Print("Tick Bucket Martingale EA ",Symbol(),",",PeriodToStr(Period()),
            " lb=",lookbackPeriod," vol_len=",vol_len," atr=",atr_period," box_withd=",box_withd);
      ReadPositionData();
     }

   freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   Start[0] = SunSet1Start;
   Start[1] = SunSet2Start;
   Start[2] = SunSet3Start;

   Start[3] = MonSet1Start;
   Start[4] = MonSet2Start;
   Start[5] = MonSet3Start;

   Start[6] = TueSet1Start;
   Start[7] = TueSet2Start;
   Start[8] = TueSet3Start;

   Start[9]  = WedSet1Start;
   Start[10] = WedSet2Start;
   Start[11] = WedSet3Start;

   Start[12] = ThuSet1Start;
   Start[13] = ThuSet2Start;
   Start[14] = ThuSet3Start;

   Start[15] = FriSet1Start;
   Start[16] = FriSet2Start;
   Start[17] = FriSet3Start;

   Start[18] = SatSet1Start;
   Start[19] = SatSet2Start;
   Start[20] = SatSet3Start;


// ==== END TIMES ====

   End[0] = SunSet1End;
   End[1] = SunSet2End;
   End[2] = SunSet3End;

   End[3] = MonSet1End;
   End[4] = MonSet2End;
   End[5] = MonSet3End;

   End[6] = TueSet1End;
   End[7] = TueSet2End;
   End[8] = TueSet3End;

   End[9]  = WedSet1End;
   End[10] = WedSet2End;
   End[11] = WedSet3End;

   End[12] = ThuSet1End;
   End[13] = ThuSet2End;
   End[14] = ThuSet3End;

   End[15] = FriSet1End;
   End[16] = FriSet2End;
   End[17] = FriSet3End;

   End[18] = SatSet1End;
   End[19] = SatSet2End;
   End[20] = SatSet3End;

   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(!TesterFastMode())
      SavePositionData();
   CleanupAllObjects();
  }
//+------------------------------------------------------------------+
//| Chart event: route button clicks to the dashboard handler        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
      CheckButtonClicks();
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!TesterFastMode())
     {
      datetime tNow = TimeCurrent();
      if(tNow - g_lastStatsRefresh >= 10)
        {
         RefreshPeriodStats();
         g_lastStatsRefresh = tNow;
        }
      UpdateMaxDD();
      DrawDashboard();
      CheckButtonClicks();
     }

   if(!IsTradingTime())
      return;

   if(isNewCandle() == true)
     {
      TimeToStruct(TimeCurrent(),str1);
      year = str1.year;
      month = str1.mon;
      day_ = str1.day;
      accountDailyProfit = AccountBalance()*(dailyProfit/100);
      accountDailyLost = AccountBalance()*(-dailyLost/100);

      gTradingStoppedToday = false;

      closeAllHour = StringToTime(IntegerToString(year)+"."+IntegerToString(month)+"."+IntegerToString(day_)+" "+IntegerToString(closeTimeHour)+":"+IntegerToString(closeTimeMinute));

      if(!TesterFastMode())
        {
         LogDailyMargins(margine, freeMargin);
         CleanupAllObjects();
        }
     }

   static datetime last_min = 0;
   static datetime last_tick_save = 0;
   datetime now = TimeCurrent();
   int allOrders = CountAllOrders();

   UpdateStartEndFromSets();

   if(AccountProfit() >= accountDailyProfit && dailyProfit != 0.0)
     {
      CloseAllOrders();
      endHour = now;
      gTradingStoppedToday = true;
     }

   if(AccountProfit() <= accountDailyLost && dailyLost != 0.0)
     {
      CloseAllOrders();
      endHour = now;
      gTradingStoppedToday = true;
     }

   if(now >= endHour && allOrders > 0 && autoCloseTrigger == true)
     {
      double profit = ProfitForDay(TimeCurrent(),magic,Symbol());
      double profitTrigger = profit * (-0.1);
      double currentProfit = AccountProfit();

      if(currentProfit < 0 && profitTrigger < currentProfit)
        {
         Print("Profit Triger: ", profitTrigger, " current profit: ",currentProfit, " Total Profit: ",profit);
         CloseAllOrders();
        }
     }

   if(now >= closeAllHour && allOrders > 0 && closeTimeHour < 24)
     {
      CloseAllOrders();
     }

   CheckAndCloseLocalTPs();
   CleanUpClosedPositions();

   if(baseScenarioCSellOrder >0 && OrderSelect(baseScenarioCSellOrder,SELECT_BY_TICKET))
     {
      if(OrderCloseTime() != 0)
        {
         scenarioCSellActive = false;
         baseScenarioCSellOrder = 0;
         cAvgCountSell = 0;
         cBaseSellPrice = 0.0;
         cBaseSellLot   = 0.0;
         cBaseSellTk    = 0;
         ArrayResize(cAvgsSell, 0);
        }
     }
   if(baseScenarioCBuyOrder >0 && OrderSelect(baseScenarioCBuyOrder,SELECT_BY_TICKET))
     {
      if(OrderCloseTime() != 0)
        {
         scenarioCBuyActive = false;
         baseScenarioCBuyOrder = 0;
         cAvgCountBuy = 0;
         cBaseBuyPrice = 0.0;
         cBaseBuyLot   = 0.0;
         cBaseBuyTk    = 0;
         ArrayResize(cAvgsBuy, 0);
        }
     }

   ProcessTickBuckets();

   if(now - last_min >= 60)
     {
      last_min = now;
     }

   if(PersistTickAcrossTF && !TesterFastMode() && now - last_tick_save >= PersistSaveEverySec)
     {
      last_tick_save = now;
      SaveTickBucketsToFile();
     }

// every hour – check yesterday
   static datetime last_hist = 0;
   if(now - last_hist >= 3600)
     {
      last_hist = now;
     }

   if(isNewM15Candle())
      ResetAllTickBuckets();

   if(aiZone == true)
     {
      if(TesterFastMode())
        {
         if(isNewM15Candle())
            AISupportResistance();
        }
      else
        {
         AISupportResistance();
        }
     }

   if(!TesterFastMode())
     {
      DrawDashboard();
      CheckButtonClicks();
     }
  }

//==================== Helpers – touch tolerance =============================
double TouchTolerance()
  {
   string s = Symbol();
   if(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0)
      return 0.10; // 10c
   if(Digits == 3 || Digits == 5)
      return Point*10;                    // 1 pip
   return Point;                                                      // 1 pip
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool BarTouchesPrice(const MqlRates &b, double price, double tol)
  {
   return (price >= (b.low - tol) && price <= (b.high + tol))
          || MathAbs(b.open  - price) <= tol
          || MathAbs(b.close - price) <= tol;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool FindFirstTouch(datetime from, datetime to, double price, datetime &touch_out)
  {
   if(to <= from)
      to = from + 60;
   MqlRates r[];
   int bars = CopyRates(Symbol(), PERIOD_M1, from+1, to, r); // +1s to avoid instant match
   if(bars <= 0)
      return false;
   ArraySetAsSeries(r,false);
   double tol = TouchTolerance();
   for(int i=0; i<bars; i++)
     {
      if(BarTouchesPrice(r[i], price, tol))
        {
         touch_out = r[i].time;
         return true;
        }
     }
   return false;
  }
//============================== Symbol parameters ========================
void CalculateSymbolParameters()
  {
   symbol_point = Point;
   if(StringFind(Symbol(),"XAU")>=0 || StringFind(Symbol(),"GOLD")>=0)
      symbol_pip_value = 0.1;
   else
      if(StringFind(Symbol(),"BTC")>=0 || StringFind(Symbol(),"BITCOIN")>=0)
         symbol_pip_value = 1.0;
      else
         if(Digits==5 || Digits==3)
            symbol_pip_value = Point*10;
         else
            symbol_pip_value = Point;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddLevel(datetime start_time, double price, string color_name, color line_color, int width, ENUM_LINE_STYLE style, ENUM_TIMEFRAMES tf)
  {
   if(levels_count >= max_levels)
      return;

   TimeToStruct(start_time, dt);
   dt.hour=0;
   dt.min=0;
   dt.sec=0;
   datetime date = StructToTime(dt);

   VolumeLevel L;
   L.date=date;
   L.start_time=start_time;
   L.end_time=0;
   L.price=price;
   L.color_name=color_name;
   L.line_color=line_color;
   L.line_width=width;
   L.line_style=style;
   L.resolved=false;
   L.max_volume=0;
   L.source_timeframe=tf;
   L.object_name = color_name+"_"+Symbol()+"_"+TimeToString(start_time, TIME_DATE|TIME_MINUTES|TIME_SECONDS)+"_"+DoubleToString(price,Digits);

   levels[levels_count]=L;
   levels_count++;
  }

//============================== TICK CLUSTERS (persistent) ================
struct TickBucket
  {
   double            price_bin;
   int               count;
   datetime          first_time;
   datetime          last_time;
   bool              level_created;
  };
TickBucket tick_buckets[];
int        tick_bucket_cnt = 0;
int        last_bucket_day = -1;
double     g_lastTickPrice = 0.0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double DefaultBinSize()
  {
   if(TickBinSize>0.0)
      return TickBinSize;
   string s=Symbol();
   if(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0)
      return 0.10;     // 10c
   if(Digits==5 || Digits==3)
      return Point*10;                            // 1 pip
   return Point;                                                          // 1 pip
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double BinPrice(double price)
  {
   double step = DefaultBinSize();
   if(step <= 0.0)
      step = Point;
   double k = MathRound(price/step);
   return k*step;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int FindBucket(double price_bin)
  {
   for(int i=tick_bucket_cnt-1; i>=0 && i>=tick_bucket_cnt-4000; i--) // O(4000) ostatnich
      if(MathAbs(tick_buckets[i].price_bin - price_bin) <= (DefaultBinSize()/2.0))
         return i;
   return -1;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ResetAllTickBuckets()
  {
   ArrayResize(tick_buckets, 0);
   tick_bucket_cnt = 0;
   g_lastTickPrice = 0.0;
   ArrayResize(levels,0);
   ArrayResize(levels,40000);
   levels_count       = 0;
   last_data_save     = 0;
   last_history_check = 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ResetTickBucketsIfNeeded()
  {
   if(!TickResetDaily)
      return;

   TimeToStruct(TimeCurrent(), dt);
   if(last_bucket_day == -1)
      last_bucket_day = dt.day;
   if(dt.day != last_bucket_day)
     {
      // safeguard: save "old day" state and clear
      if(PersistTickAcrossTF)
         SaveTickBucketsToFile();
      ResetAllTickBuckets();
      last_bucket_day = dt.day;
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool LevelExistsNear(double price)
  {
   double tol = TouchTolerance();
   for(int i=levels_count-1; i>=0 && i>=levels_count-2000; i--)
      if(MathAbs(levels[i].price - price) <= tol)
         return true;
   return false;
  }

void CreateDirectionArrow(datetime t, double price, int dir /*1=buy,-1=sell*/)
  {
   if(TesterFastMode())
      return;
   if(!ShowTickArrows)
      return;
   string name = StringFormat("TickDir_%s_%s_%d",
                              Symbol(),
                              TimeToString(t, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                              (int)(price*10000));

// arrow offset
   double offset = TickArrowOffset * DefaultBinSize();
   double y = price;
   int arrowCode = 0;
   color c = clrWhite;

   if(dir > 0)
     {
      arrowCode = 233;   // ▲
      c = TickArrowBuyColor;
      y = price - offset;
     }
   else
     {
      arrowCode = 234;   // ▼
      c = TickArrowSellColor;
      y = price + offset;
     }

   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, t, y);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

void CreateTickLevel(datetime t, double price, int dir /*1 buy, -1 sell, 0 neutral*/)
  {
   string tag = (dir>0 ? "TickBuy" : (dir<0 ? "TickSell" : "Tick"));
   AddLevel(t, price, tag, TickColor, TickWidth, TickStyle, (ENUM_TIMEFRAMES)Period());

// Direction arrow
   if(dir!=0)
     {
      CreateDirectionArrow(t, price, dir);
      int marketDirection = MarketSlopeSignal(Symbol(),0,maPeriod,slopeLookbackBars,slopeThresholdPts);

      if(TimeCurrent() > startHour && TimeCurrent() < endHour)
        {
         if(dir < 0 && marketDirection <= 0)
           {
            OpenPositions(price, dir);
           }
         if(dir > 0 && marketDirection >= 0)
           {
            OpenPositions(price, dir);
           }
        }
     }

// If not "until done" — end after N candles
   if(!TickUntilDone)
     {
      int ps = PeriodSeconds(Period());
      datetime start_bar = iTime(Symbol(), Period(), 1); // last closed candle
      datetime end_t = start_bar + (ps * TickExtendBars);
      int idx = levels_count - 1;
      if(idx >= 0)
        {
         levels[idx].resolved = true;
         levels[idx].end_time = end_t;
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ProcessTickBuckets()
  {
   if(!ShowTickLevels)
     {
      g_lastTickPrice = Bid;
      return;
     }

   double price = Bid; // could also use (Bid+Ask)/2
   double bin   = BinPrice(price);
   datetime now = TimeCurrent();

   int idx = FindBucket(bin);
   if(idx < 0)
     {
      TickBucket tb;
      tb.price_bin = bin;
      tb.count = 1;
      tb.first_time = now;
      tb.last_time  = now;
      tb.level_created = false;
      ArrayResize(tick_buckets, tick_bucket_cnt+1);
      tick_buckets[tick_bucket_cnt] = tb;
      idx = tick_bucket_cnt;
      tick_bucket_cnt++;
     }
   else
     {
      tick_buckets[idx].count++;
      tick_buckets[idx].last_time = now;
     }

// If threshold exceeded – create level (unless one exists)
   if(!tick_buckets[idx].level_created && tick_buckets[idx].count >= TickMinCount)
     {
      if(!LevelExistsNear(bin))
        {
         // Direction: current tick vs previous tick
         int dir = 0;
         if(g_lastTickPrice > 0.0)
           {
            if(price > g_lastTickPrice)
               dir = 1;
            else
               if(price < g_lastTickPrice)
                  dir = -1;
           }

         CreateTickLevel(now, bin, dir);
         tick_buckets[idx].level_created = true;
        }
     }

// update "last tick"
   g_lastTickPrice = price;
  }

//============================== Persistence: CSV read/write =============
void SaveTickBucketsToFile()
  {
   if(TesterFastMode())
      return;
   if(!PersistTickAcrossTF)
      return;
   int fh = FileOpen(tick_file, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
     {
      Print("SaveTickBuckets error: ",GetLastError());
      return;
     }

// header
   FileWrite(fh, "PriceBin","Count","FirstTime","LastTime","LevelCreated","Day");

   TimeToStruct(TimeCurrent(), dt);
   for(int i=0; i<tick_bucket_cnt; i++)
     {
      FileWrite(fh,
                DoubleToString(tick_buckets[i].price_bin, Digits),
                IntegerToString(tick_buckets[i].count),
                TimeToString(tick_buckets[i].first_time, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                TimeToString(tick_buckets[i].last_time,  TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                (tick_buckets[i].level_created ? "1":"0"),
                IntegerToString(dt.day)
               );
     }
   FileClose(fh);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CleanupAllObjects()
  {
   if(TesterFastMode())
     {
      Comment("");
      return;
     }
   ObjectsDeleteAll();
   Comment("");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OpenPositions(double price, int direction)
  {
   if(g_eaStopped)
      return;

   long spread = 1;
   spread = SymbolInfoInteger(Symbol(),SYMBOL_SPREAD);

   if(spread < maxSpread)
     {
      if(TimeCurrent() > (positionSellTime + timeFilter))
        {
         if(scenarioC == true && scenarioCSellActive == true)
           {
            if(direction < 0)
              {
               CallScenarioC(1);
              }
           }

         if(amountOfOrders(1) < startBe) // sell
           {
            if(direction < 0)
              {
               double tp = Bid-(tpRange*Point());

               if(Ask > gResistanceBottom && Ask < gResistanceTop)
                 {
                  tp = Bid-(tpRange*tpMultiplier*Point());
                 }
               int sell = OrderSend(Symbol(),OP_SELL,lotSize,Bid,3,0,0,"VESell",magic,0,clrRed);
               if(sell < 0)
                 {
                  Print("Position open failed: ", GetLastError());
                  ResetLastError();
                 }
               else
                 {
                  AddOrUpdateLocalTP(sell, tp, OP_SELL);
                  positionSellTime = TimeCurrent();
                 }

              }
           }
         else
           {
            if(direction < 0)
              {
               if(scenarioA == true)
                  CallScenarioA(1); //Buy = 0 , Sell = 1
               if(scenarioB == true)
                  CallScenarioB(1);
               if(scenarioC == true && scenarioCSellActive == false)
                  CallScenarioC(1);
               if(scenarioD == true)
                  CallScenarioD(1);
              }
           }
        }
      if(TimeCurrent() > (positionBuyTime + timeFilter))
        {
         if(scenarioC == true && scenarioCBuyActive == true)
           {
            if(direction > 0)
              {
               CallScenarioC(0);
              }
           }

         if(amountOfOrders(0) < startBe) // buy
           {
            if(direction > 0)
              {
               double tp = Ask+(tpRange*Point());
               if(Bid > gSupportBottom && Bid < gSupportTop)
                 {
                  tp = Ask+(tpRange*tpMultiplier*Point());
                 }
               int buy = OrderSend(Symbol(),OP_BUY,lotSize,Ask,3,0,0,"VEBuy",magic,0,clrBlue);
               if(buy < 0)
                 {
                  Print("Position open failed: ", GetLastError());
                  ResetLastError();
                 }
               else
                 {
                  AddOrUpdateLocalTP(buy, tp, OP_BUY);
                  positionBuyTime = TimeCurrent();
                 }
              }
           }
         else
           {
            if(direction > 0)
              {
               if(scenarioA == true)
                  CallScenarioA(0);
               if(scenarioB == true)
                  CallScenarioB(0);
               if(scenarioC == true && scenarioCBuyActive == false)
                  CallScenarioC(0);
               if(scenarioD == true)
                  CallScenarioD(0);
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CountAllOrders()
  {
   int counter = 0;
   int total = OrdersTotal();
   for(int i=0; i<total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS,MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != magic)
         continue;
      counter++;
     }
   return counter;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int amountOfOrders(int orderType) //Buy = 0, Sell = 1
  {
   int counter = 0;
   int total = OrdersTotal();
   for(int i=0; i<total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS,MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != magic)
         continue;
      if(OrderType() != orderType)
         continue;
      counter++;
     }
   return counter;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseAllOrders()
  {
   int activeOrders = CountAllOrders();

   if(activeOrders > 0)
     {
      Print("Active Orders: ", activeOrders);
      for(int i=OrdersTotal()-1; i>=0; --i)
        {
         if(!OrderSelect(i, SELECT_BY_POS,MODE_TRADES))
            continue;
         if(OrderSymbol() != Symbol())
            continue;
         if(OrderMagicNumber() != magic)
            continue;
         bool deleted = OrderClose(OrderTicket(),OrderLots(),OrderClosePrice(),0,clrYellowGreen);
         //Print("Order: ",OrderTicket(), " Closed: ",deleted);
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int FindOldestOpenOrder(int orderType) // OP_BUY lub OP_SELL
  {
   datetime oldest = INT_MAX;
   int oldestPos = -1;
   for(int i=OrdersTotal()-1; i>=0; --i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol()!=Symbol())
         continue;
      if(OrderType()!=orderType)
         continue;
      if(OrderMagicNumber() != magic)
         continue;
      if(OrderOpenTime() < oldest)
        {
         oldest    = OrderOpenTime();
         oldestPos = i;
        }
     }
   return oldestPos;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   if(step <= 0)
      step = 0.01;


   double k    = MathCeil(lots/step - 1e-9);
   double norm = k * step;


   if(norm < minLot)
      norm = minLot;

   if(norm > maxLot)
      norm = maxLot;

   if(norm > max_Lot && max_Lot != 0.0)
      norm = max_Lot;

   return NormalizeDouble(norm, 8);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double RequiredLotForBEPlusX(int direction, double p1, double l1, double p2, double tpPrice, int xPoints) // Only for Scenario A
  {

   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   if(l1 <= 0)
      return -1;

   double tpAdj = (direction==OP_BUY)
                  ? (tpPrice - xPoints*Point)
                  : (tpPrice + xPoints*Point);

   double denom = (tpAdj - p2);
   double numer = l1 * (p1 - tpAdj);

   if(MathAbs(denom) < 1e-10)
      return -1;
   double l2 = numer / denom;
   if(l2 <= 0)
      return minLot;

   return NormalizeLots(l2);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CallScenarioA(int buyORsell)
  {
   if(buyORsell == 1)
     {
      int orderPos = FindOldestOpenOrder(1);
      double posPrice = 0.0;
      double posLot = 0.0;
      int orderTicket = 0;
      if(OrderSelect(orderPos,SELECT_BY_POS,MODE_TRADES))
        {
         posPrice = OrderOpenPrice();
         posLot = OrderLots();
         orderTicket = OrderTicket();
        }
      double newLot = RequiredLotForBEPlusX(1,posPrice,posLot,Bid,Bid-(tpRange*Point()),bePoints);
      int newTicket = OrderSend(Symbol(),OP_SELL,newLot,Bid,3,0,0,"VESellSA/AVG",magic,0,clrRed);
      if(newTicket > 0)
        {
         AddOrUpdateLocalTP(newTicket, Bid-(tpRange*Point()), OP_SELL);
         positionSellTime = TimeCurrent();
        }
      else
        {
         Print("Position open failed: ", GetLastError());
         ResetLastError();
        }
      AddOrUpdateLocalTP(orderTicket, Bid-(tpRange*Point()), OP_SELL);
     }

   if(buyORsell == 0)
     {
      int orderPos = FindOldestOpenOrder(0);
      double posPrice = 0.0;
      double posLot = 0.0;
      int orderTicket = 0;
      if(OrderSelect(orderPos,SELECT_BY_POS,MODE_TRADES))
        {
         posPrice = OrderOpenPrice();
         posLot = OrderLots();
         orderTicket = OrderTicket();
        }
      double newLot = RequiredLotForBEPlusX(0,posPrice,posLot,Ask,Ask+(tpRange*Point()),bePoints);
      int newTicket = OrderSend(Symbol(),OP_BUY,newLot,Ask,3,0,0,"VEBuySA/AVG",magic,0,clrBlue);
      if(newTicket > 0)
        {
         AddOrUpdateLocalTP(newTicket, Ask+(tpRange*Point()), OP_BUY);
         positionBuyTime = TimeCurrent();
        }
      else
        {
         Print("Position open failed: ", GetLastError());
         ResetLastError();
        }
      AddOrUpdateLocalTP(orderTicket, Ask+(tpRange*Point()), OP_BUY);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CallScenarioB(int dir)  // OP_BUY (=0) lub OP_SELL (=1)
  {
   RefreshRates();

   int basePos = FindOldestOpenOrder(dir);
   if(basePos < 0 || !OrderSelect(basePos, SELECT_BY_POS, MODE_TRADES))
      return;

   double baseLot = OrderLots();
   double px  = (dir==OP_BUY ? Ask : Bid);

   double refLot = baseLot;
   int lastTk = FindLastNonBaseTicket(dir);
   if(lastTk > 0 && OrderSelect(lastTk, SELECT_BY_TICKET))
      refLot = OrderLots();

   double newLot = NextLotByMultiplier(refLot);
   if(newLot <= 0.0 || AccountFreeMarginCheck(Symbol(), dir, newLot) <= 0)
      return;

   int tk = OrderSend(Symbol(), dir, newLot, px, 3, 0, 0, (dir==OP_BUY ? "AVGBuy" : "AVGSell"), magic, 0, (dir==OP_BUY?clrBlue:clrRed));
   if(tk < 0)
     {
      Print("ScenB OS fail err=", GetLastError());
      ResetLastError();
      return;
     }

   if(dir==OP_BUY)
      positionBuyTime  = TimeCurrent();
   if(dir==OP_SELL)
      positionSellTime = TimeCurrent();

   int tickets[];
   int n = CollectGroupAll_NoComments(dir, tickets);
   if(n >= 2)
     {
      double groupTP = GroupTP_BEPlusX_All(dir, tickets, bePoints);
      if(groupTP > 0)
         for(int i=0; i<n; ++i)
            SetTP(tickets[i], groupTP);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CallScenarioC(int dir)  // OP_BUY (=0) lub OP_SELL (=1)
  {
   RefreshRates();

// 1) Identify / remember base (ticket + price + lot)
   int basePos = FindOldestOpenOrder(dir);
   if(basePos < 0 || !OrderSelect(basePos, SELECT_BY_POS, MODE_TRADES))
      return;

   cBaseTk    = OrderTicket();
   cBasePrice = OrderOpenPrice();
   cBaseLot   = OrderLots();

   if(baseScenarioCSellOrder == 0 && scenarioCSellActive == false)
     {
      if(dir == 1)
        {
         baseScenarioCSellOrder = cBaseTk;   // keep compat with existing field
         scenarioCSellActive = true;
         cBaseSellPrice = cBasePrice;
         cBaseSellLot   = cBaseLot;
         cBaseSellTk    = cBaseTk;

        }
     }
   if(baseScenarioCBuyOrder == 0 && scenarioCBuyActive == false)
     {
      if(dir == 0)
        {
         baseScenarioCBuyOrder = cBaseTk;   // keep compat with existing field
         scenarioCBuyActive = true;
         cBaseBuyPrice = cBasePrice;
         cBaseBuyLot   = cBaseLot;
         cBaseBuyTk    = cBaseTk;
        }

     }

   double px_now = (dir==OP_BUY ? Ask : Bid);

// --- reference to "last averaging" from own array
   double lastRef = cBasePrice;
   if(dir==OP_BUY)
     {
      if(cAvgCountBuy>0)
         lastRef = cAvgsBuy[cAvgCountBuy-1].price;
     }
   else
     {
      if(cAvgCountSell>0)
         lastRef = cAvgsSell[cAvgCountSell-1].price;
     }

   double hyst = MathMax(2*Point, DefaultBinSize()/5.0);
   bool farther = (dir==OP_BUY) ? (px_now <  lastRef - hyst)
                  : (px_now >  lastRef + hyst);

   double lotBase = NormalizeLots(cBaseLot);
   double lotQual = lotBase;
// if any averaging exists, use last lot as reference for 1.5x
   if(dir==OP_BUY && cAvgCountBuy>0)
      lotQual = NextLotByMultiplier(cAvgsBuy[cAvgCountBuy-1].lot);
   if(dir==OP_SELL && cAvgCountSell>0)
      lotQual = NextLotByMultiplier(cAvgsSell[cAvgCountSell-1].lot);

   if(AccountFreeMarginCheck(Symbol(), dir, (farther?lotQual:lotBase)) <= 0)
      return;

   double useLot = farther ? lotQual : lotBase;
   int tk = OrderSend(Symbol(), dir, useLot, px_now, 3, 0, 0,
                      farther ? (dir==OP_BUY?"AVGC_FAR":"AVGC_FAR")
                      : (dir==OP_BUY?"AUXC_NEAR":"AUXC_NEAR"),
                      magic, 0, (dir==OP_BUY?clrBlue:clrRed));
   if(tk<0)
     {
      Print("ScenC OS err=",GetLastError());
      ResetLastError();
      return;
     }
// --- TP
   if(farther)
     {
      // add to own averaging array
      if(OrderSelect(tk, SELECT_BY_TICKET))
        {
         if(dir==OP_BUY)
           {
            int n=cAvgCountBuy;
            ArrayResize(cAvgsBuy,n+1);
            cAvgsBuy[n].tk=tk;
            cAvgsBuy[n].price=OrderOpenPrice();
            cAvgsBuy[n].lot=OrderLots();
            cAvgCountBuy=n+1;
           }
         else
           {
            int n=cAvgCountSell;
            ArrayResize(cAvgsSell,n+1);
            cAvgsSell[n].tk=tk;
            cAvgsSell[n].price=OrderOpenPrice();
            cAvgsSell[n].lot=OrderLots();
            cAvgCountSell=n+1;
           }
        }
      // group BE+X: base + own averages (this side)
      int tks[];
      int n=0;
      ArrayResize(tks, 1);
      tks[0]=cBaseTk;
      n=1;
      if(dir==OP_BUY)
        {
         ArrayResize(tks, 1+cAvgCountBuy);
         for(int i=0; i<cAvgCountBuy; i++)
            tks[n++]=cAvgsBuy[i].tk;
        }
      else
        {
         ArrayResize(tks, 1+cAvgCountSell);
         for(int i=0; i<cAvgCountSell; i++)
            tks[n++]=cAvgsSell[i].tk;
        }
      if(n>=2)
        {
         double tpGroup = GroupTP_BEPlusX_All(dir, tks, bePoints);
         if(tpGroup>0)
            for(int i=0; i<n; ++i)
               SetTP(tks[i], tpGroup);
        }
     }
   else
     {
      // NEAR: own TP (not part of basket)
      if(OrderSelect(tk, SELECT_BY_TICKET))
        {
         double rawTP = (dir==OP_BUY ? OrderOpenPrice()+tpRange*Point
                         : OrderOpenPrice()-tpRange*Point);
         double tp    = ClampTPToStops(dir, rawTP);
         AddOrUpdateLocalTP(OrderTicket(), tp, dir);
        }
     }

   if(dir==OP_BUY)
      positionBuyTime  = TimeCurrent();
   if(dir==OP_SELL)
      positionSellTime = TimeCurrent();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CallScenarioD(int dir)  // OP_BUY (=0) lub OP_SELL (=1)
  {

   int basePos = FindOldestOpenOrder(dir);
   if(basePos < 0 || !OrderSelect(basePos, SELECT_BY_POS, MODE_TRADES))
      return;

   double basePrice = OrderOpenPrice();
   double baseLot   = OrderLots();

   RefreshRates();
   double px_now = (dir==OP_BUY ? Ask : Bid);

   double d_max = 0.0;
   int farTk = FindFarthestTicket_NoComments(dir, basePrice, d_max);

   double d_new   = MathAbs(px_now - basePrice);
   bool   farther = (d_new > d_max + (Point*1e-6));

   double refLot = baseLot;

   if(farTk > 0 && OrderSelect(farTk, SELECT_BY_TICKET))
      refLot = OrderLots();

   double lotQual = NextLotByMultiplier(refLot);
   double lotBase = NormalizeLots(baseLot);


   double useLot = lotBase;
   string cmt    = (dir==OP_BUY ? "VEBuyAVGDB" : "VESellAVGDB");

   if(farther)
     {
      if(lotQual > 0.0 && AccountFreeMarginCheck(Symbol(), dir, lotQual) > 0)
        {
         useLot = lotQual;
         cmt    = (dir==OP_BUY ? "VEBuyAVGDQ" : "VESellAVGDQ");
        }
      else
        {
         if(AccountFreeMarginCheck(Symbol(), dir, lotBase) <= 0)
            return;
        }
     }
   else
     {
      if(AccountFreeMarginCheck(Symbol(), dir, lotBase) <= 0)
         return;
     }

   int tk = OrderSend(Symbol(), dir, useLot, px_now, 3, 0, 0, cmt, magic, 0, (dir==OP_BUY?clrBlue:clrRed));

   if(tk < 0)
     {
      Print("ScenD OrderSend fail err=", GetLastError());
      ResetLastError();
      return;
     }

   if(dir==OP_BUY)
      positionBuyTime  = TimeCurrent();
   if(dir==OP_SELL)
      positionSellTime = TimeCurrent();

   int tickets[];
   int n = CollectGroupAll_NoComments(dir, tickets);
   if(n >= 2)
     {
      double groupTP = GroupTP_BEPlusX_All(dir, tickets, bePoints); // clamped against stop/freeze
      if(groupTP > 0)
         for(int i=0; i<n; ++i)
            SetTP(tickets[i], groupTP);
     }
  }
//+------------------------------------------------------------------+
// Collects ALL positions (symbol + magic + direction)               |
//+------------------------------------------------------------------+
int CollectGroupAll_NoComments(int dir, int &tickets[])
  {
   ArrayResize(tickets, 0);
   for(int i=OrdersTotal()-1; i>=0; --i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic || OrderType()!=dir)
         continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n+1);
      tickets[n] = OrderTicket();
     }
   return ArraySize(tickets);
  }
//+------------------------------------------------------------------+
//| Farthest position from base (by distance); returns ticket + d_max |
//+------------------------------------------------------------------+
int FindFarthestTicket_NoComments(int dir, double basePrice, double &dmax_out)
  {
   dmax_out = 0.0;
   int farTk = -1;
   datetime farTime = 0;
   for(int i=OrdersTotal()-1; i>=0; --i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic || OrderType()!=dir)
         continue;
      double d = MathAbs(OrderOpenPrice() - basePrice);
      if(d > dmax_out + 1e-12 || (MathAbs(d - dmax_out) <= 1e-12 && OrderOpenTime() > farTime))
        { dmax_out = d; farTk = OrderTicket(); farTime = OrderOpenTime(); }
     }
   return farTk;
  }

//+------------------------------------------------------------------+
//| Last non-base (newest beyond base) – reference for 1.5x          |
//+------------------------------------------------------------------+
int FindLastNonBaseTicket(int dir)
  {
   int basePos = FindOldestOpenOrder(dir);
   int baseTk = -1;
   if(basePos >= 0 && OrderSelect(basePos, SELECT_BY_POS, MODE_TRADES))
      baseTk = OrderTicket();

   int lastTk = -1;
   datetime lastTime = 0;
   for(int i=OrdersTotal()-1; i>=0; --i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic || OrderType()!=dir)
         continue;
      if(OrderTicket()==baseTk)
         continue;
      if(OrderOpenTime() > lastTime)
        {
         lastTime = OrderOpenTime();
         lastTk = OrderTicket();
        }
     }
   return lastTk;
  }


//+------------------------------------------------------------------+
//| Qualification THRESHOLD for Scenario C – Global Variables        |
//+------------------------------------------------------------------+
string GVKeyC_Threshold(int dir)
  {
   return StringFormat("SC_C_THRESHOLD_%s_%d_%d", Symbol(), magic, dir);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetC_Threshold(int dir)
  {
   string k = GVKeyC_Threshold(dir);
   if(!GlobalVariableCheck(k))
      return 0.0;
   return GlobalVariableGet(k);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetC_Threshold(int dir, double thr)
  {
   GlobalVariableSet(GVKeyC_Threshold(dir), thr);
  }
// Reset threshold if basket closed (no position >= thr)
void ResetC_ThresholdIfNeeded(int dir, double basePrice)
  {
   double thr = GetC_Threshold(dir);
   if(thr <= 0.0)
      return;

   bool anyQual=false;
   for(int i=OrdersTotal()-1; i>=0; --i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic || OrderType()!=dir)
         continue;
      double d = MathAbs(OrderOpenPrice() - basePrice);
      if(d + 1e-12 >= thr)
        {
         anyQual = true;
         break;
        }
     }
   if(!anyQual)
      SetC_Threshold(dir, 0.0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double NextLotByMultiplier(double baseLot) // Only Scenario B
  {
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);

   if(step<=0)
      step=0.01;

   double raw = baseLot * lotMultiplier;
   double k   = MathCeil(raw/step - 1e-9);
   double out = k * step;

   if(out < minLot)
      out = minLot;
   if(out > maxLot)
      out = maxLot;
   if(max_Lot != 0.0 && out > max_Lot)
     {
      out = max_Lot;
     }
   return NormalizeDouble(out, 8);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SetTP(int ticket, double newTP) // Scenario B only
  {
   if(ticket<=0)
      return false;
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return false;
   AddOrUpdateLocalTP(OrderTicket(), newTP, OrderType());
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double ClampTPToStops(int dir, double rawTP)
  {
   int stopLevel = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   int freeze    = (int)MarketInfo(Symbol(), MODE_FREEZELEVEL);
   double mind   = (stopLevel + freeze) * Point;

   double tp = rawTP;
   if(dir==OP_BUY  && tp < Ask + mind)
      tp = Ask + mind;
   if(dir==OP_SELL && tp > Bid - mind)
      tp = Bid - mind;
   return NormalizeDouble(tp, Digits);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GroupTP_BEPlusX_All(int dir, const int &tickets[], int xPoints)
  {
   double sumL=0.0, sumLP=0.0;
   for(int k=0; k<ArraySize(tickets); ++k)
     {
      if(!OrderSelect(tickets[k], SELECT_BY_TICKET))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic || OrderType()!=dir)
         continue;
      double l = OrderLots();
      double p = OrderOpenPrice();
      sumL  += l;
      sumLP += l*p;
     }
   if(sumL <= 0.0)
      return 0.0;

   double wavg  = sumLP / sumL;                                       // BE grupy
   double rawTP = (dir==OP_BUY) ? (wavg + xPoints*Point) : (wavg - xPoints*Point);
   return ClampTPToStops(dir, rawTP);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool isNewCandle()
  {
   if(iTime(Symbol(),PERIOD_D1,0) == currentCandle)
     {
      return false;
     }
   else
     {
      currentCandle = iTime(Symbol(),PERIOD_D1,0);
      return true;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool isNewM15Candle()
  {
   if(iTime(Symbol(),PERIOD_M15,0) == m15Candle)
     {
      return false;
     }
   else
     {
      m15Candle = iTime(Symbol(),PERIOD_M15,0);
      return true;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+


// ============== ZONES: LOGIC AND FUNCTIONS ========================
string PeriodToStr(int p)
  {
   if(p==PERIOD_M1)
      return"M1";
   if(p==PERIOD_M5)
      return"M5";
   if(p==PERIOD_M15)
      return"M15";
   if(p==PERIOD_M30)
      return"M30";
   if(p==PERIOD_H1)
      return"H1";
   if(p==PERIOD_H4)
      return"H4";
   if(p==PERIOD_D1)
      return"D1";
   if(p==PERIOD_W1)
      return"W1";
   if(p==PERIOD_MN1)
      return"MN1";
   return IntegerToString(p);
  }

// === FUNCTIONS 1:1 from source file ===
double TR_i(int i)
  {
   double tr1=High[i]-Low[i];
   double tr2=MathAbs(High[i]-Close[i+1]);
   double tr3=MathAbs(Low[i]-Close[i+1]);
   return MathMax(tr1,MathMax(tr2,tr3));
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double rma_step(const double &ma[],const double &val[],int len,int i)
  {
   return (val[i] + (len-1)*ma[i+1]) / len;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double highest_forward(const double &series[],int length1,int i)
  {
   double max = series[i];
   int ub = MathMin(i+length1, ArraySize(series)-1);                             // UWAGA: ArraySize-1
   for(int k=i+1; k<ub; k++)
      max = MathMax(max, series[k]);                      // strict '<'
   return max;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double lowest_forward(const double &series[],int length1,int i)
  {
   double min = series[i];
   int ub = MathMin(i+length1, ArraySize(series)-1);
   for(int k=i+1; k<ub; k++)
      min = MathMin(min, series[k]);                      // strict '<'
   return min;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double pivothigh_close(const double &arr[],int left,int right,int i)
  {
   if(ArraySize(arr) <= i+right+left)
      return 0.0;
   double pivot = arr[i+right];
   for(int j=1; j<=left; j++)
      if(pivot < arr[i+right+j])
         return 0.0;            // strict '<'
   for(int j=1; j<=right; j++)
      if(pivot < arr[i+right-j])
         return 0.0;            // strict '<'
   return pivot;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double pivotlow_close(const double &arr[],int left,int right,int i)
  {
   if(ArraySize(arr) <= i+right+left)
      return 0.0;
   double pivot = arr[i+right];
   for(int j=1; j<=left; j++)
      if(pivot > arr[i+right+j])
         return 0.0;            // strict '>'
   for(int j=1; j<=right; j++)
      if(pivot > arr[i+right-j])
         return 0.0;            // strict '>'
   return pivot;
  }
// === MAIN LOGIC — every tick, 1:1, no drawing ===
bool AISupportResistance()
  {
   int bars=Bars;
   if(bars < MathMax(atr_period,vol_len)+lookbackPeriod+5)
      return false;

   static double tr[], atr[], posVol[], negVol[], Vol[];
   ArrayResize(tr,bars);
   ArrayResize(atr,bars);
   ArrayResize(posVol,bars);
   ArrayResize(negVol,bars);
   ArrayResize(Vol,bars);

   tr[bars-1]=0.0;
   atr[bars-1]=0.0;
   posVol[bars-1]=0.0;
   negVol[bars-1]=0.0;
   Vol[bars-1]=0.0;

   bool     foundSup=false, foundRes=false;
   double   supTop=0,supBot=0,resBot=0,resTop=0,supATR=0,resATR=0,supW=0,resW=0;
   datetime supT=0,resT=0;

   for(int i=bars-3; i>=0; i--)
     {
      // ATR 1:1
      tr[i]  = TR_i(i);
      atr[i] = rma_step(atr,tr,atr_period,i);

      // skumulowany delta-wolumen — tick_volume (doji i wzrost = buy)
      long tv = iVolume(NULL, 0, i);
      bool isBuyVolume = (Close[i] >= Open[i]);   // indicator sets true except when Close<Open
      posVol[i]=0.0;
      negVol[i]=0.0;
      if(isBuyVolume)
         posVol[i]=posVol[i+1] + tv;
      else
         negVol[i]=negVol[i+1] - tv;
      Vol[i]=posVol[i] + negVol[i];

      // thresholds (right window with '<' and ArraySize-1 limit)
      double vol_hi = highest_forward(Vol, vol_len, i) / 2.5;
      double vol_lo = lowest_forward(Vol, vol_len, i) / 2.5;

      // pivoty na CLOSE z pivotem w i+right
      double pHigh = pivothigh_close(Close, lookbackPeriod, lookbackPeriod, i);
      double pLow  = pivotlow_close(Close, lookbackPeriod, lookbackPeriod, i);

      // width
      double width = atr[i] * box_withd;

      // wsparcie
      if(pLow!=0.0 && Vol[i] > vol_hi)
        {
         datetime t = Time[i+lookbackPeriod];
         if(!foundSup || t > supT)
           {
            foundSup=true;
            supTop=pLow;
            supBot=pLow - width;
            supT=t;
            supATR=atr[i];
            supW=width;
           }
        }
      // resistance
      if(pHigh!=0.0 && Vol[i] < vol_lo)
        {
         datetime t = Time[i+lookbackPeriod];
         if(!foundRes || t > resT)
           {
            foundRes=true;
            resBot=pHigh;
            resTop=pHigh + width;
            resT=t;
            resATR=atr[i];
            resW=width;
           }
        }
     }

   bool any=false;
   if(foundSup && (supT!=gLastSupTime || MathAbs(supTop-gSupportTop)>1e-12))
     {
      gSupportTop=supTop;
      gSupportBottom=supBot;
      gLastSupTime=supT;
      Comment("");
      Comment("RESIST (bottom/top)", gResistanceBottom," ", gResistanceTop,"\n",
              "SUPPORT (top/bottom)", gSupportTop, " ",gSupportBottom);
      any=true;
     }
   if(foundRes && (resT!=gLastResTime || MathAbs(resBot-gResistanceBottom)>1e-12))
     {
      gResistanceBottom=resBot;
      gResistanceTop=resTop;
      gLastResTime=resT;
      Comment("");
      Comment("RESIST (bottom/top)", gResistanceBottom," ", gResistanceTop,"\n",
              "SUPPORT (top/bottom)", gSupportTop, " ",gSupportBottom);
      any=true;
     }
   return any;
  }
// ----------------------------------------------------------------------------------
// =============== close if actual loss is 10% or less of day profit ================
// ----------------------------------------------------------------------------------
double ProfitForDay(datetime day, int _magic = -1, string symbol = "")
  {
// Set time range for the given day in server time
   datetime start = StringToTime(TimeToString(day, TIME_DATE)); // midnight of that day
   datetime end   = start + 86400;                              // next day

   double sum = 0.0;
   int total = OrdersHistoryTotal();

   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      // only take actually closed trades from this day
      datetime ct = OrderCloseTime();
      if(ct >= start && ct < end)
        {
         if((_magic == -1 || OrderMagicNumber() == _magic) &&
            (symbol == "" || OrderSymbol() == symbol))
           {
            sum += OrderProfit() + OrderSwap() + OrderCommission();
           }
        }
     }
   return sum;
  }

//+------------------------------------------------------------------+
//| DASHBOARD — Positions + Controls (MoneyDancer-inspired)          |
//+------------------------------------------------------------------+
string ObjName(string suffix)
  {
   return "TBM_" + IntegerToString(magic) + "_" + suffix;
  }

void DrawPanel(string name, int x, int y, int w, int h, color bgClr, color borderClr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderClr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void DrawLabel(string name, int x, int y, string text, color clr, int fontSize, string font)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void CreateButton(string name, int x, int y, int w, int h, string text, color txtClr, color bgClr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//--- Period keys for grouping closed orders
int DayKey(datetime t)   { MqlDateTime m; TimeToStruct(t,m); return m.year*10000 + m.mon*100 + m.day; }
int WeekKey(datetime t)  { return (int)(t / (7*86400)); }
int MonthKey(datetime t) { MqlDateTime m; TimeToStruct(t,m); return m.year*100 + m.mon; }

//--- Track peak equity and rolling max drawdown (today + ever)
void UpdateMaxDD()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int dayKey = DayKey(TimeCurrent());

   if(dayKey != g_ddDayKey)
     {
      g_ddDayKey        = dayKey;
      g_peakEquityToday = equity;
      g_maxDDToday      = 0;
     }

   if(equity > g_peakEquityToday) g_peakEquityToday = equity;
   if(equity > g_peakEquityEver)  g_peakEquityEver  = equity;

   if(g_peakEquityToday > 0)
     {
      double ddToday = (g_peakEquityToday - equity) / g_peakEquityToday * 100.0;
      if(ddToday > g_maxDDToday) g_maxDDToday = ddToday;
     }

   if(g_peakEquityEver > 0)
     {
      double ddEver = (g_peakEquityEver - equity) / g_peakEquityEver * 100.0;
      if(ddEver > g_maxDDEver) g_maxDDEver = ddEver;
     }
  }

//--- Floating P/L for currently open positions of one side
double BasketFloatingPL(int dir)
  {
   double pl = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; --i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;
      if(OrderType() != dir) continue;
      pl += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return pl;
  }

//--- Close all profitable positions of one side
void CloseProfitOrders(int orderType)
  {
   for(int i = OrdersTotal()-1; i >= 0; --i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;
      if(OrderType() != orderType) continue;
      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit <= 0) continue;
      double px = (orderType == OP_BUY ? Bid : Ask);
      if(!OrderClose(OrderTicket(), OrderLots(), px, 3, clrYellowGreen))
         ResetLastError();
     }
  }

//--- Close all positions of one side
void CloseAllOrdersType(int orderType)
  {
   for(int i = OrdersTotal()-1; i >= 0; --i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;
      if(OrderType() != orderType) continue;
      double px = (orderType == OP_BUY ? Bid : Ask);
      if(!OrderClose(OrderTicket(), OrderLots(), px, 3, clrYellowGreen))
         ResetLastError();
     }
  }

//--- Refresh stats for closed positions by period (today/week/month)
void RefreshPeriodStats()
  {
   datetime now = TimeCurrent();
   int dk = DayKey(now), wk = WeekKey(now), mk = MonthKey(now);

   g_closedBuyToday = 0; g_closedSellToday = 0;
   g_profitBuyToday = 0; g_profitSellToday = 0;
   g_closedBuyWeek  = 0; g_closedSellWeek  = 0;
   g_profitBuyWeek  = 0; g_profitSellWeek  = 0;
   g_closedBuyMonth = 0; g_closedSellMonth = 0;
   g_profitBuyMonth = 0; g_profitSellMonth = 0;

   int ht = OrdersHistoryTotal();
   for(int i = 0; i < ht; ++i)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;
      datetime ct = OrderCloseTime();
      if(ct <= 0) continue;
      double p = OrderProfit() + OrderSwap() + OrderCommission();
      bool isBuy = (OrderType() == OP_BUY);
      if(DayKey(ct) == dk)
        { if(isBuy) { g_closedBuyToday++; g_profitBuyToday += p; } else { g_closedSellToday++; g_profitSellToday += p; } }
      if(WeekKey(ct) == wk)
        { if(isBuy) { g_closedBuyWeek++;  g_profitBuyWeek  += p; } else { g_closedSellWeek++;  g_profitSellWeek  += p; } }
      if(MonthKey(ct) == mk)
        { if(isBuy) { g_closedBuyMonth++; g_profitBuyMonth += p; } else { g_closedSellMonth++; g_profitSellMonth += p; } }
     }
  }

//--- Draw Positions + Controls dashboard
void DrawDashboard()
  {
   if(!ShowDashboard || TesterFastMode()) return;

   // Theme (MoneyDancer palette)
   color bgPanel     = C'24,28,36';
   color borderMain  = C'45,52,65';
   color textBright  = C'220,225,230';
   color textMuted   = C'130,140,155';
   color accentBlue  = C'70,130,200';
   color profitGreen = C'50,205,100';
   color lossRed     = C'220,70,70';

   int x = DashX;
   int y = DashY;
   int w = 410;

   // ============ POSITIONS PANEL ============
   DrawPanel(ObjName("D_StatsPanel"), x, y, w, 105, bgPanel, borderMain);
   DrawLabel(ObjName("D_StatsTitle"), x + 12, y + 6, ">> POSITIONS", accentBlue, 8, "Arial Bold");

   // Period buttons
   int btnW = 60, btnH = 16;
   int btnX = x + w - 195;
   color btnT = (g_statsViewMode == 0 ? accentBlue : C'40,45,55');
   color btnWc= (g_statsViewMode == 1 ? accentBlue : C'40,45,55');
   color btnM = (g_statsViewMode == 2 ? accentBlue : C'40,45,55');
   CreateButton(ObjName("D_BtnToday"), btnX, y + 5, btnW, btnH, "TODAY", textBright, btnT);
   CreateButton(ObjName("D_BtnWeek"),  btnX + btnW + 3, y + 5, btnW, btnH, "WEEK",  textBright, btnWc);
   CreateButton(ObjName("D_BtnMonth"), btnX + 2*(btnW + 3), y + 5, btnW, btnH, "MONTH", textBright, btnM);

   int cB, cS; double pB, pS;
   if(g_statsViewMode == 0)      { cB = g_closedBuyToday; cS = g_closedSellToday; pB = g_profitBuyToday; pS = g_profitSellToday; }
   else if(g_statsViewMode == 1) { cB = g_closedBuyWeek;  cS = g_closedSellWeek;  pB = g_profitBuyWeek;  pS = g_profitSellWeek;  }
   else                          { cB = g_closedBuyMonth; cS = g_closedSellMonth; pB = g_profitBuyMonth; pS = g_profitSellMonth; }

   // BUY row (closed)
   DrawLabel(ObjName("D_BL"), x + 15, y + 30, "BUY:", textMuted, 8, "Arial");
   DrawLabel(ObjName("D_BC"), x + 60, y + 30, IntegerToString(cB), textBright, 9, "Consolas");
   color pBClr = (pB >= 0 ? profitGreen : lossRed);
   DrawLabel(ObjName("D_BP"), x + 100, y + 30, (pB >= 0 ? "+" : "") + DoubleToString(pB, 2), pBClr, 9, "Consolas");

   // SELL row (closed)
   DrawLabel(ObjName("D_SL"), x + 15, y + 48, "SELL:", textMuted, 8, "Arial");
   DrawLabel(ObjName("D_SC"), x + 60, y + 48, IntegerToString(cS), textBright, 9, "Consolas");
   color pSClr = (pS >= 0 ? profitGreen : lossRed);
   DrawLabel(ObjName("D_SP"), x + 100, y + 48, (pS >= 0 ? "+" : "") + DoubleToString(pS, 2), pSClr, 9, "Consolas");

   // TOTAL row
   double totP = pB + pS;
   int totC = cB + cS;
   DrawLabel(ObjName("D_TL"), x + 15, y + 70, "TOTAL:", textMuted, 9, "Arial Bold");
   DrawLabel(ObjName("D_TC"), x + 60, y + 70, IntegerToString(totC), textBright, 9, "Consolas");
   color totClr = (totP >= 0 ? profitGreen : lossRed);
   DrawLabel(ObjName("D_TP"), x + 100, y + 70, (totP >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(totP), 2), totClr, 11, "Arial Bold");

   // Open positions (right column)
   int oB = amountOfOrders(OP_BUY);
   int oS = amountOfOrders(OP_SELL);
   double fB = BasketFloatingPL(OP_BUY);
   double fS = BasketFloatingPL(OP_SELL);
   double fT = fB + fS;

   DrawLabel(ObjName("D_OL"), x + w/2 + 15, y + 30, "OPEN:", textMuted, 8, "Arial");
   DrawLabel(ObjName("D_OB"), x + w/2 + 60, y + 30, IntegerToString(oB) + " B", accentBlue, 9, "Consolas");
   DrawLabel(ObjName("D_OS"), x + w/2 + 100, y + 30, IntegerToString(oS) + " S", lossRed, 9, "Consolas");

   DrawLabel(ObjName("D_FL"), x + w/2 + 15, y + 48, "FLOAT:", textMuted, 8, "Arial");
   color fClr = (fT >= 0 ? profitGreen : lossRed);
   DrawLabel(ObjName("D_FV"), x + w/2 + 60, y + 48, (fT >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(fT), 2), fClr, 10, "Consolas");

   y += 110;

   // ============ LIVE METRICS PANEL ============
   // Margin snapshot (was previously on POSITIONS panel)
   if(OrdersTotal() > 0 && AccountInfoDouble(ACCOUNT_MARGIN_FREE) < freeMargin)
     {
      margine    = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2);
      freeMargin = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE),  2);
     }

   DrawPanel(ObjName("D_MetricsPanel"), x, y, w, 70, bgPanel, borderMain);
   DrawLabel(ObjName("D_MetricsTitle"), x + 12, y + 6, ">> LIVE METRICS", accentBlue, 8, "Arial Bold");

   // Left column: Max DD Today / Max DD Ever
   DrawLabel(ObjName("D_L4"), x + 15,  y + 25, "MAX DD TODAY:", textMuted, 8, "Arial");
   color ddTClr = (g_maxDDToday > 10.0 ? lossRed : textBright);
   DrawLabel(ObjName("D_V4"), x + 115, y + 25, DoubleToString(g_maxDDToday, 2) + "%", ddTClr, 9, "Consolas");

   DrawLabel(ObjName("D_L5"), x + 15,  y + 45, "MAX DD EVER:", textMuted, 8, "Arial");
   color ddEClr = (g_maxDDEver > 20.0 ? lossRed : textBright);
   DrawLabel(ObjName("D_V5"), x + 115, y + 45, DoubleToString(g_maxDDEver, 2) + "%", ddEClr, 9, "Consolas");

   // Right column: Margin %
   DrawLabel(ObjName("D_ML"), x + w/2 + 15, y + 25, "MARGIN %:", textMuted, 8, "Arial");
   DrawLabel(ObjName("D_MV"), x + w/2 + 90, y + 25, DoubleToString(margine, 2), textBright, 9, "Consolas");

   y += 75;

   // ============ CONTROLS PANEL ============
   DrawPanel(ObjName("D_CtrlPanel"), x, y, w, 80, bgPanel, borderMain);
   DrawLabel(ObjName("D_CtrlTitle"), x + 12, y + 6, ">> CONTROLS", accentBlue, 8, "Arial Bold");

   int cBtnW = 95, cBtnH = 20;
   int cY1 = y + 26, cY2 = y + 52;

   CreateButton(ObjName("D_BtnProfitSell"),   x + 8,   cY1, cBtnW, cBtnH, "+ PROFIT SELL", textBright, C'70,45,45');
   CreateButton(ObjName("D_BtnProfitBuy"),    x + 108, cY1, cBtnW, cBtnH, "+ PROFIT BUY",  textBright, C'45,70,45');
   CreateButton(ObjName("D_BtnCloseAllSell"), x + 208, cY1, cBtnW, cBtnH, "X ALL SELL",    textBright, C'100,45,45');
   CreateButton(ObjName("D_BtnCloseAllBuy"),  x + 308, cY1, cBtnW, cBtnH, "X ALL BUY",     textBright, C'45,80,45');

   CreateButton(ObjName("D_BtnCloseAll"), x + 8, cY2, 195, cBtnH, "!! CLOSE ALL !!", textBright, C'130,50,50');
   string stopTxt = (g_eaStopped ? "> START EA" : "[] STOP EA");
   color  stopBg  = (g_eaStopped ? C'45,90,45'  : C'90,45,45');
   CreateButton(ObjName("D_BtnStopEA"), x + 208, cY2, 195, cBtnH, stopTxt, textBright, stopBg);
  }

//--- Process dashboard button clicks (called from OnTick and OnChartEvent)
void CheckButtonClicks()
  {
   if(!ShowDashboard) return;
   datetime now = TimeCurrent();
   if(now - g_lastButtonCheck < 1) return;
   g_lastButtonCheck = now;

   if(ObjectGetInteger(0, ObjName("D_BtnToday"), OBJPROP_STATE))
     { g_statsViewMode = 0; ObjectSetInteger(0, ObjName("D_BtnToday"), OBJPROP_STATE, false); }
   if(ObjectGetInteger(0, ObjName("D_BtnWeek"),  OBJPROP_STATE))
     { g_statsViewMode = 1; ObjectSetInteger(0, ObjName("D_BtnWeek"),  OBJPROP_STATE, false); }
   if(ObjectGetInteger(0, ObjName("D_BtnMonth"), OBJPROP_STATE))
     { g_statsViewMode = 2; ObjectSetInteger(0, ObjName("D_BtnMonth"), OBJPROP_STATE, false); }

   if(ObjectGetInteger(0, ObjName("D_BtnProfitSell"), OBJPROP_STATE))
     { CloseProfitOrders(OP_SELL); ObjectSetInteger(0, ObjName("D_BtnProfitSell"), OBJPROP_STATE, false); }
   if(ObjectGetInteger(0, ObjName("D_BtnProfitBuy"),  OBJPROP_STATE))
     { CloseProfitOrders(OP_BUY);  ObjectSetInteger(0, ObjName("D_BtnProfitBuy"),  OBJPROP_STATE, false); }
   if(ObjectGetInteger(0, ObjName("D_BtnCloseAllSell"), OBJPROP_STATE))
     { CloseAllOrdersType(OP_SELL); ObjectSetInteger(0, ObjName("D_BtnCloseAllSell"), OBJPROP_STATE, false); }
   if(ObjectGetInteger(0, ObjName("D_BtnCloseAllBuy"),  OBJPROP_STATE))
     { CloseAllOrdersType(OP_BUY);  ObjectSetInteger(0, ObjName("D_BtnCloseAllBuy"),  OBJPROP_STATE, false); }

   if(ObjectGetInteger(0, ObjName("D_BtnCloseAll"), OBJPROP_STATE))
     { CloseAllOrders(); g_eaStopped = true; ObjectSetInteger(0, ObjName("D_BtnCloseAll"), OBJPROP_STATE, false); }
   if(ObjectGetInteger(0, ObjName("D_BtnStopEA"), OBJPROP_STATE))
     { g_eaStopped = !g_eaStopped; ObjectSetInteger(0, ObjName("D_BtnStopEA"), OBJPROP_STATE, false); }
  }

//+------------------------------------------------------------------+
//--- Struct for holding position data and local TP
struct LocalOrders
  {
   int               ticket;         // Position ticket number
   double            localTP;        // Locally managed Take Profit price
   int               order_type;     // Position type (OP_BUY/OP_SELL)
  };

LocalOrders localOrders[]; // Global array for storing local TPs

//+------------------------------------------------------------------+
//| Adds or updates a position in the local TP array                |
//+------------------------------------------------------------------+
void AddOrUpdateLocalTP(int ticket, double tp_price, int type)
  {

   for(int i = 0; i < ArraySize(localOrders); i++)
     {
      if(localOrders[i].ticket == ticket)
        {
         localOrders[i].localTP = tp_price;
         return;
        }
     }

   int new_size = ArraySize(localOrders);
   ArrayResize(localOrders, new_size + 1);
   localOrders[new_size].ticket = ticket;
   localOrders[new_size].localTP = tp_price;
   localOrders[new_size].order_type = type;
  }

//+------------------------------------------------------------------+
//| Removes a position from the local TP array                       |
//+------------------------------------------------------------------+
void RemoveLocalTP(int ticket)
  {
   for(int i = 0; i < ArraySize(localOrders); i++)
     {
      if(localOrders[i].ticket == ticket)
        {
         for(int j = i; j < ArraySize(localOrders) - 1; j++)
           {
            localOrders[j] = localOrders[j+1];
           }
         ArrayResize(localOrders, ArraySize(localOrders) - 1);
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Checks and closes positions based on local TPs.                  |
//+------------------------------------------------------------------+
void CheckAndCloseLocalTPs()
  {
   RefreshRates();

   for(int i = ArraySize(localOrders) - 1; i >= 0; i--)
     {
      int ticket = localOrders[i].ticket;

      if(OrderSelect(ticket, SELECT_BY_TICKET) == false)
        {
         continue;
        }

      double local_tp = localOrders[i].localTP;
      int type = localOrders[i].order_type;
      bool should_close = false;

      if(type == OP_BUY && Bid >= local_tp)
        {
         should_close = true;
        }
      else
         if(type == OP_SELL && Ask <= local_tp)
           {
            should_close = true;
           }

      if(should_close)
        {
         if(OrderClose(ticket, OrderLots(), (type == OP_BUY ? Bid : Ask), 3, clrRed))
           {
           }
         else
           {
            Print("Error closing position ", ticket, ": ", GetLastError());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Removes closed positions from the local list.                    |
//+------------------------------------------------------------------+
void CleanUpClosedPositions()
  {
   for(int i = ArraySize(localOrders) - 1; i >= 0; i--)
     {
      int ticket = localOrders[i].ticket;
      if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
        {
         if(OrderCloseTime() > 0)
           {
            RemoveLocalTP(ticket);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|Function for saving data about position when EA failed            |
//+------------------------------------------------------------------+
void SavePositionData()
  {
   if(TesterFastMode())
      return;
   string fileName = "positions_backup_"+Symbol()+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+".txt";
   ResetLastError();

   int fileHandle = FileOpen(fileName, FILE_TXT | FILE_WRITE);

   if(fileHandle != INVALID_HANDLE)
     {
      int total = ArraySize(localOrders);
      for(int i = 0; i < total; i++)
        {
         int posTicket = localOrders[i].ticket;
         double posTP = localOrders[i].localTP;
         int posType = localOrders[i].order_type;

         string line = StringFormat("%d %.5f %d", posTicket, posTP,posType);

         FileWrite(fileHandle, line);
        }
      FileClose(fileHandle);
     }
   else
     {
      Print("File write error: ", GetLastError());
     }
  }
//+------------------------------------------------------------------+
//|Function for checked saved position after EA failed               |
//+------------------------------------------------------------------+
void ReadPositionData()
  {
   if(TesterFastMode())
      return;
   string fileName = "positions_backup_"+Symbol()+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+".txt";
   ResetLastError();

   int fileHandle = FileOpen(fileName, FILE_TXT | FILE_READ);

   if(fileHandle != INVALID_HANDLE)
     {
      while(!FileIsEnding(fileHandle))
        {
         string line = FileReadString(fileHandle);
         if(line == "")
            continue;  // skip empty lines

         // split line into parts (ticket, tp, type)
         string parts[];
         int count = StringSplit(line, ' ', parts);

         if(count >= 3)
           {
            int positionTicket = (int)StringToInteger(parts[0]);
            double posTp = StrToDouble(parts[1]);
            int posType = (int)StringToInteger(parts[2]);

            AddOrUpdateLocalTP(positionTicket,posTp,posType);
           }
        }
      FileClose(fileHandle);
     }
   else
     {
      Print("File read error: ", GetLastError());
     }
  }
//+------------------------------------------------------------------+
void LogDailyMargins(double ml, double fm)
  {
   if(TesterFastMode())
      return;
   int h = FileOpen("daily_margins.csv", FILE_CSV|FILE_READ|FILE_WRITE);
   if(h != INVALID_HANDLE)
     {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, TimeCurrent(), DoubleToString(ml,2), DoubleToString(fm,2));
      FileClose(h);
     }
  }
//+------------------------------------------------------------------+
//|  MarketSlope                                                     |
//+------------------------------------------------------------------+
int MarketSlopeSignal(string symbol,
                      int    timeframe,
                      int    maPeriod_,
                      int    slopeLookbackBars_,
                      double slopeThresholdPts_)
  {
   if(timeframe == 0)
      timeframe = Period();

   int bars = iBars(symbol, timeframe);
   if(bars <= maPeriod_ + slopeLookbackBars_ + 2)
      return(0);

   double ma_now  = iMA(symbol, timeframe, maPeriod_, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ma_old  = iMA(symbol, timeframe, maPeriod_, 0, MODE_EMA, PRICE_CLOSE, slopeLookbackBars_);

   double slope_pts_per_bar = (ma_now - ma_old) / _Point / slopeLookbackBars_;

   if(slope_pts_per_bar >  slopeThresholdPts_)
      return(1);
   else
      if(slope_pts_per_bar < -slopeThresholdPts_)
         return(-1);
      else
         return(0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int ToMinutes(int t)
  {
   int h = t/100;
   int m = t%100;
   if(h<0 || h>23 || m<0 || m>59)
      return(-1); // niepoprawny HHMM
   return(h*60 + m);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
   int d    = DayOfWeek();
   int last = -1;
   bool any = false;

   for(int i=0; i<3; i++)
     {
      int idx = d*3 + i;

      if(Start[idx] == End[idx])   // set disabled?
         continue;

      int s = ToMinutes(Start[idx]);
      int e = ToMinutes(End[idx]);

      if(s < 0 || e < 0)           // garbage like 195, 2399, 2400 → skip this set
         continue;

      if(s >= e)                   // don't allow overnight windows
         return(false);

      if(last != -1 && s < last)   // set2 >= end1, set3 >= end2
         return(false);

      last = e;
      any  = true;
     }

   return(any);                    // true = this day has valid sets
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateStartEndFromSets()
  {
// if day already stopped by dailyProfit/dailyLost – don't touch window
   if(gTradingStoppedToday)
      return;

   datetime now = TimeCurrent();
   MqlDateTime t;
   TimeToStruct(now, t);

   int d      = DayOfWeek();
   int curMin = TimeHour(now)*60 + TimeMinute(now);

   int firstS=-1, firstE=-1;
   int lastS=-1,  lastE=-1;
   int nextS=-1,  nextE=-1;
   int curS=-1,   curE=-1;
   int last = -1;

   for(int i=0; i<3; i++)
     {
      int idx = d*3 + i;
      if(Start[idx] == End[idx])
         continue;

      int s = ToMinutes(Start[idx]);
      int e = ToMinutes(End[idx]);

      if(s < 0 || e < 0)
         continue;
      if(s >= e)
         continue;
      if(last != -1 && s < last)
         continue;

      if(firstS == -1)
        {
         firstS = s;
         firstE = e;
        }
      lastS = s;
      lastE = e;

      if(curMin >= s && curMin < e)   // we're inside this set
        {
         curS = s;
         curE = e;
         break;                       // the rest don't matter
        }

      if(curMin < s && nextS == -1)   // first upcoming set
        {
         nextS = s;
         nextE = e;
        }

      last = e;
     }

   int useS=-1, useE=-1;

   if(curS != -1)          // current window
     {
      useS = curS;
      useE = curE;
     }
   else
      if(nextS != -1)    // before next window
        {
         useS = nextS;
         useE = nextE;
        }
      else
         if(lastS != -1)    // past all – keep last window (for autoCloseTrigger)
           {
            useS = lastS;
            useE = lastE;
           }
         else                    // no valid sets (IsTradingTime() should return false)
           {
            startHour = 0;
            endHour   = 0;
            return;
           }

   int sh = useS / 60;
   int sm = useS % 60;
   int eh = useE / 60;
   int em = useE % 60;

   string datePart = StringFormat("%d.%02d.%02d ", t.year, t.mon, t.day);

   startHour = StringToTime(datePart + StringFormat("%02d:%02d", sh, sm));
   endHour   = StringToTime(datePart + StringFormat("%02d:%02d", eh, em));
  }

//+------------------------------------------------------------------+
