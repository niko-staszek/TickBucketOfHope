//+------------------------------------------------------------------+
//|                                                Trading AI System |
//|                                                   AI Trade Maker |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "ALLinTraders"
#property link      "https://allintraders.com/"
#property version   "4.2"
#property strict

//+------------------------------------------------------------------+
//| LICENSE PROTECTION PARAMETERS                                     |
//+------------------------------------------------------------------+
input string l0 = "=======================";                   // = LICENSE PARAMETERS =
input string LicenseKey = "";                                   // License Key (Required)

// License protection variables
const string VALID_LICENSE = "aQBk1013m3k1okMdfs8a912e0artt1356";
const datetime EXPIRY_DATE = D'2026.05.10 23:59:59';
bool isLicenseValid = false;
datetime lastLicenseCheck = 0;  // Track last license verification

//=== Poziomy Tick (licznik ticków w binie ceny)
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

//=== Trwałość Tick między TF (zapisy do CSV)
bool  PersistTickAcrossTF = true;    // True - save TOF multi TF
int   PersistSaveEverySec = 60;      // Make a save TOF every X sec

//=== Strzałki kierunku Tick
bool  ShowTickArrows   = true;
color TickArrowBuyColor  = clrDodgerBlue;
color TickArrowSellColor = clrRed;
double TickArrowOffset   = 1;      // Size of marks (1.5 * bin)

//=== Pozycje
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
bool   scenerioA = false;                   // Set A
extern bool   scenerioB = false;            // Model MoE 1.5 (100k+)
extern bool   scenerioC = false;            // Model MoE RLF (Thinker)
extern bool   scenerioD = true;             // Model MOE RLHF-RAT
input int     closeTimeHour   = 23;         // Close ALL Hour (if 24 turn off)
input int     closeTimeMinute = 45;         // Close Minutes
input int timeFilter = 30;                  // Time Filter
input bool autoCloseTrigger = true;         // Auto Close Trigger

datetime startHour, endHour, currentCandle, closeAllHour,m15Candle, positionBuyTime, positionSellTime;
int year, month, day_, basceScenerioCSellorder, baseScenerioCBuyOrder;
MqlDateTime str1, dt;
bool scenerioCSellActive = false;
bool scenerioCBuyActive = false;
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

//--- Dane i pliki
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
string tick_file     = "";        // plik CSV na liczniki ticków

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

//======== ORDERS DATA TABLE ============
input ENUM_BASE_CORNER TblCorner   = CORNER_RIGHT_LOWER;  // Anchor Corner
input color            TblBgColor  = clrBlack;            // Backgorund Color
input color            TblFontColor= clrGold;             // Table Text Color

enum TBL_SIZE { SIZE_NORMAL=0, SIZE_SMALL=1 };
input TBL_SIZE         TblSize     = SIZE_SMALL;         // Table Size
input color            BottomTextColor = clrDarkGreen;         // Bottom Text Color
input int              profitDaysBack = 1;                  // show Profit Days (set number)

double margine = 0.0;
double freeMargin;

//============================== TESTER FAST MODE =============================
bool gTesterFastMode = false;
bool TesterFastMode()
  {
   return (gTesterFastMode || IsTesting());
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

//============================== BROKER VALIDATION ==========================
bool CheckAllowedBroker()
  {
   if(TesterFastMode())
      return(true);

   string broker = AccountInfoString(ACCOUNT_COMPANY);

   // allow only brokers whose name contains "AxiCorp" or at least "Axi"
   if(StringFind(broker, "AxiCorp") >= 0 || StringFind(broker, "Axi") >= 0)
      return(true);

   MessageBox(
      "You are using the wrong broker for this AI trading system.\n\n"
      "Please contact our support team: support@allintraders.pl",
      "Broker restriction",
      MB_ICONERROR
   );

   Print("Broker restriction: EA disabled. Broker company = '", broker,
         "' (required substring: 'AxiCorp' or 'Axi').");

   return(false);
  }

//============================== INIT/DEINIT ==============================
int OnInit()
  {
   gTesterFastMode = IsTesting();

   ArrayResize(levels, max_levels);
   CalculateSymbolParameters();

   if(!TesterFastMode())
     {
      Print("AI SR EA ",Symbol(),",",PeriodToStr(Period()),
            " lb=",lookbackPeriod," vol_len=",vol_len," atr=",atr_period," box_withd=",box_withd);
      ReadPositionData();
     }
   else
     {
      isLicenseValid = true;
      lastLicenseCheck = TimeCurrent();
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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!TesterFastMode())
     {
      //--- Check license once per day
      static datetime lastCheckDay = 0;
      datetime currentDay = (datetime)(TimeCurrent() / 86400) * 86400;  // Start of current day

      if(currentDay != lastCheckDay)
        {
         if(!VerifyLicense())
           {
            return;  // License invalid, stop trading
           }
         lastCheckDay = currentDay;
        }

      //--- Quick check if license is valid
      if(!isLicenseValid)
        {
         return;
        }

      ShowClosedProfitBottom2TF();
      DrawClosedProfitTableGridInputs();
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

   if(basceScenerioCSellorder >0 && OrderSelect(basceScenerioCSellorder,SELECT_BY_TICKET))
     {
      if(OrderCloseTime() != 0)
        {
         scenerioCSellActive = false;
         basceScenerioCSellorder = 0;
         cAvgCountSell = 0;
         cBaseSellPrice = 0.0;
         cBaseSellLot   = 0.0;
         cBaseSellTk    = 0;
         ArrayResize(cAvgsSell, 0);
        }
     }
   if(baseScenerioCBuyOrder >0 && OrderSelect(baseScenerioCBuyOrder,SELECT_BY_TICKET))
     {
      if(OrderCloseTime() != 0)
        {
         scenerioCBuyActive = false;
         baseScenerioCBuyOrder = 0;
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

// co godzinę – sprawdź wczoraj
   static datetime last_hist = 0;
   if(now - last_hist >= 3600)
     {
      last_hist = now;
     }

   if(isNewM15Candle())
      ResetAllTickBuckets(true);

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
      ShowClosedProfitBottom2TF();
      DrawClosedProfitTableGridInputs();
     }
  }

//==================== Pomocnicze – tolerancja dotknięcia ====================
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
   int bars = CopyRates(Symbol(), PERIOD_M1, from+1, to, r); // +1s by uniknąć natychmiast
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
//============================== Parametry symbolu ========================
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

//============================== TICK CLUSTERS (trwałe) ====================
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
void ResetAllTickBuckets(bool announce)
  {
   ArrayResize(tick_buckets, 0);
   tick_bucket_cnt = 0;
   g_lastTickPrice = 0.0;
   ArrayResize(levels,0);
   ArrayResize(levels,40000);
   levels_count       = 0;
   last_data_save     = 0;
   last_history_check = 0;
   if(announce)
     {
      //   Print("Tick buckets reset. Bucket Size: ", ArraySize(tick_buckets));
      //   Print("Levels bucket reset.Bucket 0: ",levels[0].price);
     }
//if(PersistTickAcrossTF)
//   SaveTickBucketsToFile();
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
      // zabezpiecz: zapisz stan „starego dnia” i wyczyść
      if(PersistTickAcrossTF)
         SaveTickBucketsToFile();
      ResetAllTickBuckets(false);
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

// offset strzałki
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

// Strzałka kierunku
   if(dir!=0)
     {
      CreateDirectionArrow(t, price, dir);
      int marketDirection = MarketSlopeSignal(Symbol(),0,maPeriod,slopeLookbackBars,slopeThresholdPts);
      //Print("Market direction: ", marketDirection);

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

// Jeśli nie "until done" — kończ po N świecach
   if(!TickUntilDone)
     {
      int ps = PeriodSeconds(Period());
      datetime start_bar = iTime(Symbol(), Period(), 1); // ostatnia zamknięta świeca
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

   double price = Bid; // można (Bid+Ask)/2
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

// Jeżeli przekroczył próg – twórz poziom (jeśli go jeszcze nie ma)
   if(!tick_buckets[idx].level_created && tick_buckets[idx].count >= TickMinCount)
     {
      if(!LevelExistsNear(bin))
        {
         // Kierunek: obecny tick vs poprzedni tick
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

// aktualizuj „ostatni tick”
   g_lastTickPrice = price;
  }

//============================== Trwałość: zapis/odczyt CSV ===============
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

   long spread = 1;
   spread = SymbolInfoInteger(Symbol(),SYMBOL_SPREAD);

// Print("Time current: ",TimeCurrent()," time sell: ",(positionSellTime + timeFilter), " time buy: ",(positionBuyTime + timeFilter));
// Print("Is time cur > time sell: ",TimeCurrent() > (positionSellTime + timeFilter));
// Print("Is time cur > time buy: ", TimeCurrent() > (positionBuyTime + timeFilter));
// Print("Spread: ",spread, " Orders sell :",amountOfOrders(1), " Orders Buy: ",amountOfOrders(0), " Direcion: ", direction);

   if(spread < maxSpread)
     {
      if(TimeCurrent() > (positionSellTime + timeFilter))
        {
         if(scenerioC == true && scenerioCSellActive == true)
           {
            if(direction < 0)
              {
               CallScenerioC(1);
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
               if(scenerioA == true)
                  CallScenerioA(1); //Buy = 0 , Sell = 1
               if(scenerioB == true)
                  CallScenerioB(1);
               if(scenerioC == true && scenerioCSellActive == false)
                  CallScenerioC(1);
               if(scenerioD == true)
                  CallScenerioD(1);
              }
           }
        }
      if(TimeCurrent() > (positionBuyTime + timeFilter))
        {
         if(scenerioC == true && scenerioCBuyActive == true)
           {
            if(direction > 0)
              {
               CallScenerioC(0);
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
               if(scenerioA == true)
                  CallScenerioA(0);
               if(scenerioB == true)
                  CallScenerioB(0);
               if(scenerioC == true && scenerioCBuyActive == false)
                  CallScenerioC(0);
               if(scenerioD == true)
                  CallScenerioD(0);
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
double RequiredLotForBEPlusX(int direction, double p1, double l1, double p2, double tpPrice, int xPoints) // Only for Scenerio A
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
void CallScenerioA(int buyORsell)
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
      //bool modify = OrderModify(orderTicket,posPrice,0,Bid-(tpRange*Point()),0,clrOrange);
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
      //bool modify = OrderModify(orderTicket,posPrice,0,Ask+(tpRange*Point()),0,clrAqua);
      AddOrUpdateLocalTP(orderTicket, Ask+(tpRange*Point()), OP_BUY);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CallScenerioB(int dir)  // OP_BUY (=0) lub OP_SELL (=1)
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
void CallScenerioC(int dir)  // OP_BUY (=0) lub OP_SELL (=1)
  {
   RefreshRates();

// 1) Zidentyfikuj / zapamiętaj bazę (ticket + cena + lot)
   int basePos = FindOldestOpenOrder(dir);
   if(basePos < 0 || !OrderSelect(basePos, SELECT_BY_POS, MODE_TRADES))
      return;

   cBaseTk    = OrderTicket();
   cBasePrice = OrderOpenPrice();
   cBaseLot   = OrderLots();

   if(basceScenerioCSellorder == 0 && scenerioCSellActive == false)
     {
      if(dir == 1)
        {
         basceScenerioCSellorder = cBaseTk;   // zachowujemy zgodność z dotychczasowym polem
         scenerioCSellActive = true;
         cBaseSellPrice = cBasePrice;
         cBaseSellLot   = cBaseLot;
         cBaseSellTk    = cBaseTk;

        }
     }
   if(baseScenerioCBuyOrder == 0 && scenerioCBuyActive == false)
     {
      if(dir == 0)
        {
         baseScenerioCBuyOrder = cBaseTk;   // zachowujemy zgodność z dotychczasowym polem
         scenerioCBuyActive = true;
         cBaseBuyPrice = cBasePrice;
         cBaseBuyLot   = cBaseLot;
         cBaseBuyTk    = cBaseTk;
        }

     }

   double px_now = (dir==OP_BUY ? Ask : Bid);

// --- referencja „ostatniego uśrednienia” z własnej tablicy
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
// jeśli mamy jakieś uśrednienie, weź ostatni lot jako referencję do 1.5x
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
      // dodaj do własnej tablicy uśrednień
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
      // grupowy BE+X: baza + własne uśrednienia (tej strony)
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
      // NEAR: własny TP (nie wchodzi do koszyka)
      if(OrderSelect(tk, SELECT_BY_TICKET))
        {
         double rawTP = (dir==OP_BUY ? OrderOpenPrice()+tpRange*Point
                         : OrderOpenPrice()-tpRange*Point);
         double tp    = ClampTPToStops(dir, rawTP);
         //bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), 0, tp, 0, clrNONE);
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
void CallScenerioD(int dir)  // OP_BUY (=0) lub OP_SELL (=1)
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
      double groupTP = GroupTP_BEPlusX_All(dir, tickets, bePoints); // ma clamp na stop/freeze
      if(groupTP > 0)
         for(int i=0; i<n; ++i)
            SetTP(tickets[i], groupTP);
     }
  }
//+------------------------------------------------------------------+
// Zbiera WSZYSTKIE pozycje (symbol + magic + kierunek)              |
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
//| Najdalsza pozycja od bazy (po dystansie); zwraca ticket i d_max   |
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
//| Ostatnia nie-bazowa (najświeższa poza bazą) – referencja dla 1.5×|
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
//| PROG kwalifikacji dla Scen C – Global Variables (no-comment     )|
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
// Reset progu, jeśli koszyk domknięty (brak pozycji >= thr)
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
double NextLotByMultiplier(double baseLot) // Only Scenerio B
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
bool SetTP(int ticket, double newTP) // Scenerio B only
  {
   if(ticket<=0)
      return false;
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return false;
// OrderModify(OrderTicket(), OrderOpenPrice(), OrderStopLoss(), newTP, 0, clrNONE);
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
void ClearTickFile()
  {
   if(TesterFastMode())
      return;
   int fh = FileOpen(tick_file, FILE_WRITE | FILE_COMMON); // bez FILE_CSV — bo nic nie piszemy
   if(fh != INVALID_HANDLE)
     {
      // Plik otwarty w trybie FILE_WRITE automatycznie nadpisuje zawartość
      FileClose(fh); // Zapisujemy "nic", więc po prostu zamykamy
      Print("ClearTickFile");
     }
   else
     {
      Print("ClearTickFile error: ", GetLastError());
     }
  }
//+------------------------------------------------------------------+


// ============== LOGIKA i FUNKCJE STREF ============================
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

// === FUNKCJE 1:1 z Twojego pliku ===
double TR_i(int i)
  {
   double tr1=High[i]-Low[i];
   double tr2=MathAbs(High[i]-Close[i+1]);
   double tr3=MathAbs(Low[i]-Close[i+1]);
   return MathMax(tr1,MathMax(tr2,tr3));
  }                                     // :contentReference[oaicite:5]{index=5}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double rma_step(const double &ma[],const double &val[],int len,int i)
  {
   return (val[i] + (len-1)*ma[i+1]) / len;
  }                                   // :contentReference[oaicite:6]{index=6}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double highest_forward(const double &series[],int length1,int i)
  {
   double max = series[i];
   int ub = MathMin(i+length1, ArraySize(series)-1);                             // UWAGA: ArraySize-1
   for(int k=i+1; k<ub; k++)
      max = MathMax(max, series[k]);                      // ścisłe '<'
   return max;
  }                                                                 // :contentReference[oaicite:7]{index=7}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double lowest_forward(const double &series[],int length1,int i)
  {
   double min = series[i];
   int ub = MathMin(i+length1, ArraySize(series)-1);
   for(int k=i+1; k<ub; k++)
      min = MathMin(min, series[k]);                      // ścisłe '<'
   return min;
  }                                                                 // :contentReference[oaicite:8]{index=8}

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
         return 0.0;            // tylko '<'
   for(int j=1; j<=right; j++)
      if(pivot < arr[i+right-j])
         return 0.0;            // tylko '<'
   return pivot;
  }                                                               // :contentReference[oaicite:9]{index=9}

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
         return 0.0;            // tylko '>'
   for(int j=1; j<=right; j++)
      if(pivot > arr[i+right-j])
         return 0.0;            // tylko '>'
   return pivot;
  }                                                               // :contentReference[oaicite:10]{index=10}

// === GŁÓWNA LOGIKA — co tick, 1:1, bez rysowania ===
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
      bool isBuyVolume = (Close[i] >= Open[i]);   // wskaźnik ustawia true poza przypadkiem Close<Open
      posVol[i]=0.0;
      negVol[i]=0.0;
      if(isBuyVolume)
         posVol[i]=posVol[i+1] + tv;
      else
         negVol[i]=negVol[i+1] - tv;
      Vol[i]=posVol[i] + negVol[i];

      // progi (okno w prawo z '<' i limitem ArraySize-1)
      double vol_hi = highest_forward(Vol, vol_len, i) / 2.5;
      double vol_lo = lowest_forward(Vol, vol_len, i) / 2.5;

      // pivoty na CLOSE z pivotem w i+right
      double pHigh = pivothigh_close(Close, lookbackPeriod, lookbackPeriod, i);
      double pLow  = pivotlow_close(Close, lookbackPeriod, lookbackPeriod, i);

      // szerokość
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
      // opór
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
// Ustalenie zakresu czasu dla danego dnia w czasie serwera
   datetime start = StringToTime(TimeToString(day, TIME_DATE)); // północ tego dnia
   datetime end   = start + 86400;                              // następny dzień

   double sum = 0.0;
   int total = OrdersHistoryTotal();

   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      // bierzemy tylko faktycznie zamknięte transakcje z tego dnia
      datetime ct = OrderCloseTime();
      if(ct >= start && ct < end)
        {
         if((magic == -1 || OrderMagicNumber() == magic) &&
            (symbol == "" || OrderSymbol() == symbol))
           {
            sum += OrderProfit() + OrderSwap() + OrderCommission();
           }
        }
     }
   return sum;
  }

//=================================================
// Funkcja: Pokazuje profit z zamkniętych pozycji |
//   między dwiema ostatnimi zamkniętymi świecami |
//=================================================
void ShowClosedProfitBottom2TF()
  {
   if(TesterFastMode())
      return;
// --- wyznacz TF o dwa stopnie wyżej ---
   int tf;
   switch(Period())
     {
      case PERIOD_M1:
         tf = PERIOD_M15;
         break; // M1 -> M15
      case PERIOD_M5:
         tf = PERIOD_M30;
         break; // M5 -> M30
      case PERIOD_M15:
         tf = PERIOD_H1;
         break; // M15 -> H1
      case PERIOD_M30:
         tf = PERIOD_H4;
         break; // M30 -> H4
      case PERIOD_H1:
         tf = PERIOD_D1;
         break; // H1 -> D1
      case PERIOD_H4:
         tf = PERIOD_W1;
         break; // H4 -> W1
      case PERIOD_D1:
         tf = PERIOD_MN1;
         break; // D1 -> MN1
      case PERIOD_W1:
         tf = PERIOD_MN1;
         break; // W1 -> MN1 (brak wyżej)
      case PERIOD_MN1:
         tf = PERIOD_MN1;
         break; // już najwyższy
      default:
         tf = PERIOD_H1;
         break;
     }

   int bars = iBars(_Symbol, tf);
   if(bars <= 0)
      return;

// --- tablica sum profitów dla świec tf ---
   double profitByBar[];
   ArrayResize(profitByBar, bars);
   ArrayInitialize(profitByBar, 0.0);

// --- zlicz zamknięte zlecenia bieżącego symbolu ---
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != _Symbol)
         continue;

      double p = OrderProfit() + OrderSwap() + OrderCommission();
      datetime ct = OrderCloseTime();

      int sh = iBarShift(_Symbol, tf, ct, true);
      if(sh < 0 || sh >= bars)
         continue;

      profitByBar[sh] += p;
     }

// --- usuń stare etykiety z tej funkcji ---
   int tot = ObjectsTotal(0,0,-1);
   for(int o = tot-1; o >= 0; o--)
     {
      string nm = ObjectName(0, o);
      if(StringFind(nm, "ProfitLbl2TF_") == 0)
         ObjectDelete(0, nm);
     }

// --- pozycja pionowa (stabilnie przy dole okna) ---
   double pMin = WindowPriceMin();
   double pMax = WindowPriceMax();
   if(pMax <= pMin)
      return;
   double y = pMin + (pMax - pMin) * 0.04; // ~2% nad dołem

// --- sekundy TF do wyznaczenia środka świecy ---
   int tfSec;
   switch(tf)
     {
      case PERIOD_M1:
         tfSec=60;
         break;
      case PERIOD_M5:
         tfSec=300;
         break;
      case PERIOD_M15:
         tfSec=900;
         break;
      case PERIOD_M30:
         tfSec=1800;
         break;
      case PERIOD_H1:
         tfSec=3600;
         break;
      case PERIOD_H4:
         tfSec=14400;
         break;
      case PERIOD_D1:
         tfSec=86400;
         break;
      case PERIOD_W1:
         tfSec=604800;
         break;
      case PERIOD_MN1:
         tfSec=2592000;
         break;
      default:
         tfSec=3600;
         break;
     }

// --- rysuj wartości tylko tam, gdzie suma != 0 ---
   for(int sh = 0; sh < bars; sh++)
     {
      if(MathAbs(profitByBar[sh]) < 0.00001)
         continue;

      datetime t0  = iTime(_Symbol, tf, sh);
      datetime tMid= (tfSec>0 ? t0 + tfSec/2 : t0);

      string name = "ProfitLbl2TF_" + IntegerToString(sh);
      string txt  = DoubleToString(profitByBar[sh], 2);
      color  clr  = (profitByBar[sh] >= 0 ? BottomTextColor : clrTomato);

      ObjectCreate(0, name, OBJ_TEXT, 0, tMid, y);
      ObjectSetText(name, txt, 9, "Arial", clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// ==== STAŁE NAZW ====
#define TBL_BG   "Tbl_BG"
#define TBL_PFX  "Tbl_"

// ==== POMOCNICZE ====
bool IsRight(int corner) { return (corner==CORNER_RIGHT_UPPER || corner==CORNER_RIGHT_LOWER); }
bool IsLower(int corner) { return (corner==CORNER_LEFT_LOWER  || corner==CORNER_RIGHT_LOWER); }

// Uniwersalne ustawienie OBJ_LABEL w panelu (zawsze ANCHOR_LEFT_UPPER)
void PlaceLabelInPanel(const string name, int corner, int panelW, int panelH,
                       int edgeX, int edgeY, int xIn, int yIn,
                       const string text, color clr, int fontSize)
  {
   int x = IsRight(corner) ? (edgeX + panelW - xIn) : (edgeX + xIn);
   int y = IsLower(corner) ? (edgeY + panelH - yIn) : (edgeY + yIn);

   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  fontSize);
   ObjectSetString(0,name,OBJPROP_FONT,      "Consolas");
   ObjectSetString(0,name,OBJPROP_TEXT,      text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,    true);
#ifdef OBJPROP_ANCHOR
   ObjectSetInteger(0,name,OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
#endif
  }

// Tło panelu (OBJ_RECTANGLE_LABEL) – pozycjonowane jak wyżej
void DrawTableBackground(int corner, int panelW, int panelH, int edgeX, int edgeY, color bg)
  {
   int x = IsRight(corner) ? (edgeX + panelW) : edgeX;
   int y = IsLower(corner) ? (edgeY + panelH) : edgeY;

   if(ObjectFind(0,TBL_BG) < 0)
      ObjectCreate(0, TBL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0,TBL_BG,OBJPROP_CORNER,    corner);
   ObjectSetInteger(0,TBL_BG,OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,TBL_BG,OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0,TBL_BG,OBJPROP_XSIZE,     panelW);
   ObjectSetInteger(0,TBL_BG,OBJPROP_YSIZE,     panelH);
   ObjectSetInteger(0,TBL_BG,OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0,TBL_BG,OBJPROP_COLOR,     clrDimGray);
   ObjectSetInteger(0,TBL_BG,OBJPROP_WIDTH,     1);
   ObjectSetInteger(0,TBL_BG,OBJPROP_BACK,      false);
   ObjectSetInteger(0,TBL_BG,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,TBL_BG,OBJPROP_HIDDEN,    true);
#ifdef OBJPROP_ANCHOR
   ObjectSetInteger(0,TBL_BG,OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
#endif
  }

// ================== GŁÓWNA FUNKCJA ==================
void DrawClosedProfitTableGridInputs()
  {
   if(TesterFastMode())
      return;
// --- rozmiary zależne od trybu (normal/small)
   double scale = (TblSize==SIZE_SMALL ? 0.5 : 1.0);

   int panelW   = (int)MathRound(360 * scale);
   int panelH   = (int)MathRound(208 * scale);
   int fontSz   = (int)MathMax(8, MathRound(12 * scale));
   int padInX   = (int)MathRound(10 * scale);
   int padInY   = (int)MathRound(10 * scale);

// margines od krawędzi okna (Y większy na dole, by nie nachodzić na oś czasu)
   int edgeX = 14;
   int edgeY = IsLower(TblCorner) ? 50 : 14;

// --- policz zamknięcia (bieżący symbol)
   int buyCnt=0, sellCnt=0;
   double buySum=0.0, sellSum=0.0;

   datetime from = iTime(Symbol(), PERIOD_D1, profitDaysBack);
   datetime to   = TimeCurrent();

   for(int i=OrdersHistoryTotal()-1; i>=0; --i)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
         continue;
      if(OrderSymbol()!=_Symbol)
         continue;
      double p = OrderProfit()+OrderSwap()+OrderCommission();
      int tp = OrderType();
      datetime tclose = OrderCloseTime();

      if(tclose <= 0)
         continue;
      if(tclose < from)
         break;
      if(tclose > to)
         continue;

      if(tp==OP_BUY)
        {
         buyCnt++;
         buySum  += p;
        }
      if(tp==OP_SELL)
        {
         sellCnt++;
         sellSum += p;
        }
     }
   int totalCnt = buyCnt + sellCnt;
   double totalSum = buySum + sellSum;

   if(OrdersTotal() > 0)
     {
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < freeMargin)
        {
         margine = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),2);
         freeMargin = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2);
        }
     }

// --- usuń stare obiekty panelu
   for(int k=ObjectsTotal(0,0,-1)-1; k>=0; --k)
     {
      string nm=ObjectName(0,k);
      if(nm==TBL_BG || StringFind(nm,TBL_PFX)==0)
         ObjectDelete(0,nm);
     }

// --- tło
   DrawTableBackground(TblCorner, panelW, panelH, edgeX, edgeY, TblBgColor);

// --- pozycje komórek (od LEWEJ/GÓRY panelu)
   int c1 = padInX;                       // Label
   int c2 = padInX + (int)MathRound(120*scale); // Count
   int c3 = padInX + (int)MathRound(220*scale); // Amount

   int r0 = padInY + (int)MathRound(4*scale);;
   int r1 = padInY + (int)MathRound(38*scale);
   int r2 = r1 + (int)MathRound(28*scale);
   int r3 = r2 + (int)MathRound(28*scale);
   int r4 = r3 + (int)MathRound(40*scale);
   int r5 = r4 + (int)MathRound(28*scale);

   color fontClr = TblFontColor;  // jeden kolor dla całej tabeli

// --- komórki
   PlaceLabelInPanel(TBL_PFX+"r0c1",TblCorner,panelW,panelH,edgeX,edgeY,c1,r0,"ALLin-MoE-LLM",   fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r0c3",TblCorner,panelW,panelH,edgeX,edgeY,c3,r0,"connected",fontClr,fontSz);

   PlaceLabelInPanel(TBL_PFX+"r1c1",TblCorner,panelW,panelH,edgeX,edgeY,c1,r1,"BUY",   fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r1c2",TblCorner,panelW,panelH,edgeX,edgeY,c2,r1,IntegerToString(buyCnt),fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r1c3",TblCorner,panelW,panelH,edgeX,edgeY,c3,r1,DoubleToString(buySum,2),fontClr,fontSz);

   PlaceLabelInPanel(TBL_PFX+"r2c1",TblCorner,panelW,panelH,edgeX,edgeY,c1,r2,"SELL",  fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r2c2",TblCorner,panelW,panelH,edgeX,edgeY,c2,r2,IntegerToString(sellCnt),fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r2c3",TblCorner,panelW,panelH,edgeX,edgeY,c3,r2,DoubleToString(sellSum,2),fontClr,fontSz);

   PlaceLabelInPanel(TBL_PFX+"r3c1",TblCorner,panelW,panelH,edgeX,edgeY,c1,r3,"TOTAL", fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r3c2",TblCorner,panelW,panelH,edgeX,edgeY,c2,r3,IntegerToString(totalCnt),fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r3c3",TblCorner,panelW,panelH,edgeX,edgeY,c3,r3,DoubleToString(totalSum,2),fontClr,fontSz);

   PlaceLabelInPanel(TBL_PFX+"r4c1",TblCorner,panelW,panelH,edgeX,edgeY,c1,r4,"MARGIN FREE", fontClr,fontSz);
//PlaceLabelInPanel(TBL_PFX+"r4c2",TblCorner,panelW,panelH,edgeX,edgeY,c2,r4,IntegerToString(totalCnt),fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r4c3",TblCorner,panelW,panelH,edgeX,edgeY,c3,r4,DoubleToString(freeMargin,2),fontClr,fontSz);

   PlaceLabelInPanel(TBL_PFX+"r5c1",TblCorner,panelW,panelH,edgeX,edgeY,c1,r5,"MARGIN %", fontClr,fontSz);
//PlaceLabelInPanel(TBL_PFX+"r5c2",TblCorner,panelW,panelH,edgeX,edgeY,c2,r4,IntegerToString(totalCnt),fontClr,fontSz);
   PlaceLabelInPanel(TBL_PFX+"r5c3",TblCorner,panelW,panelH,edgeX,edgeY,c3,r5,DoubleToString(margine,2),fontClr,fontSz);

  }

//+------------------------------------------------------------------+
//--- Struktura do przechowywania danych o pozycji i lokalnym TP
struct LocalOrders
  {
   int               ticket;         // Numer ticketa pozycji
   double            localTP;        // Cena Take Profit zarządzana lokalnie
   int               order_type;     // Typ pozycji (OP_BUY/OP_SELL)
  };

LocalOrders localOrders[]; // Globalna tablica do przechowywania lokalnych TP

//+------------------------------------------------------------------+
//| Dodaje lub aktualizuje pozycję w tablicy lokalnych TP           |
//+------------------------------------------------------------------+
void AddOrUpdateLocalTP(int ticket, double tp_price, int type)
  {

   if(ArraySize(localOrders) < 0)
      ArrayResize(localOrders, 0);

   for(int i = 0; i < ArraySize(localOrders); i++)
     {
      if(localOrders[i].ticket == ticket)
        {
         localOrders[i].localTP = tp_price;
         //Print("Lokalny TP dla ticketa ", ticket, " zaktualizowany do ", DoubleToStr(tp_price, Digits));
         return;
        }
     }

   int new_size = ArraySize(localOrders);
   ArrayResize(localOrders, new_size + 1);
   localOrders[new_size].ticket = ticket;
   localOrders[new_size].localTP = tp_price;
   localOrders[new_size].order_type = type;
//Print("Lokalny TP dla ticketa ", ticket, " dodany: ", DoubleToStr(tp_price, Digits));
  }

//+------------------------------------------------------------------+
//| Usuwa pozycję z tablicy lokalnych TP                             |
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
         //  Print("Lokalny TP dla ticketa ", ticket, " usunięty.");
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Sprawdza i zamyka pozycje na podstawie lokalnych TP.             |
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
            // Print("Pozycja ", ticket, " zamknięta lokalnie przez TP.");
           }
         else
           {
            Print("Błąd zamykania pozycji ", ticket, ": ", GetLastError());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Usuwa zamknięte pozycje z lokalnej listy.                        |
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
      Print("Błąd zapisu pliku: ", GetLastError());
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
            continue;  // Pomijamy puste linie

         // Podziel linię na części (mfaOrder, mt4Ticket, lot, price, comment)
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
      Print("Błąd odczytu pliku: ", GetLastError());
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
      FileWrite(h, TimeCurrent()-86400, DoubleToString(ml,2), DoubleToString(fm,2));
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

// minuty od północy
int mm(int h,int m)
  {
   return(h*60+m);
  }

// sprawdza 3 sesje jednego dnia,
// pilnuje też: start<end, brak nachodzenia i prawidłowa kolejność
bool DayOK(int cur,
           int sh1,int sm1,int eh1,int em1,
           int sh2,int sm2,int eh2,int em2,
           int sh3,int sm3,int eh3,int em3)
  {
   int s[3],e[3];
   s[0]=mm(sh1,sm1);
   e[0]=mm(eh1,em1);
   s[1]=mm(sh2,sm2);
   e[1]=mm(eh2,em2);
   s[2]=mm(sh3,sm3);
   e[2]=mm(eh3,em3);

   int lastEnd=-1;
   for(int i=0; i<3; i++)
     {
      if(s[i]==e[i])
         continue;          // sesja wyłączona
      if(s[i]>e[i])
         return(false);     // nie pozwalamy na nocne okno
      if(lastEnd!=-1 && s[i]<lastEnd)   // wymusza: start2 >= end1 itd.
         return(false);
      if(cur>=s[i] && cur<e[i])         // w środku okna
         return(true);
      lastEnd=e[i];
     }
   return(false);
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

      if(Start[idx] == End[idx])   // set wyłączony?
         continue;

      int s = ToMinutes(Start[idx]);
      int e = ToMinutes(End[idx]);

      if(s < 0 || e < 0)           // śmieci typu 195, 2399, 2400 → pomijamy ten set
         continue;

      if(s >= e)                   // nie pozwalamy na nocne okno
         return(false);

      if(last != -1 && s < last)   // set2 >= end1, set3 >= end2
         return(false);

      last = e;
      any  = true;
     }

   return(any);                    // true = w tym dniu są poprawne sety
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateStartEndFromSets()
  {
// jeśli dzień już zatrzymany przez dailyProfit/dailyLost – nie ruszamy okna
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

      if(curMin >= s && curMin < e)   // jesteśmy w środku tego seta
        {
         curS = s;
         curE = e;
         break;                       // dalsze nas nie interesują
        }

      if(curMin < s && nextS == -1)   // pierwszy set w przyszłości
        {
         nextS = s;
         nextE = e;
        }

      last = e;
     }

   int useS=-1, useE=-1;

   if(curS != -1)          // aktualne okno
     {
      useS = curS;
      useE = curE;
     }
   else
      if(nextS != -1)    // przed kolejnym oknem
        {
         useS = nextS;
         useE = nextE;
        }
      else
         if(lastS != -1)    // po wszystkich – trzymaj ostatnie okno (dla autoCloseTrigger)
           {
            useS = lastS;
            useE = lastE;
           }
         else                    // brak poprawnych setów (teoretycznie IsTradingTime() zwróci wtedy false)
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
//+------------------------------------------------------------------+
//| LICENSE VERIFICATION FUNCTIONS                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Verify License Key and Expiry Date                               |
//+------------------------------------------------------------------+
bool VerifyLicense()
  {
   if(TesterFastMode())
     {
      isLicenseValid = true;
      lastLicenseCheck = TimeCurrent();
      return true;
     }
   datetime currentTime = TimeCurrent();
   
   //--- Check if already verified today
   if(isLicenseValid && lastLicenseCheck > 0)
     {
      int daysSinceCheck = (int)((currentTime - lastLicenseCheck) / 86400);
      if(daysSinceCheck < 1)
        {
         // Already checked today, skip verification
         return(true);
        }
     }
   
   //--- Check expiry date first
   if(currentTime > EXPIRY_DATE)
     {
      Alert("LICENSE EXPIRED!");
      Alert("This EA expired on: ", TimeToString(EXPIRY_DATE, TIME_DATE));
      Alert("Current date: ", TimeToString(currentTime, TIME_DATE));
      Alert("Please contact support for license renewal.");
      isLicenseValid = false;
      return(false);
     }
   
   //--- Check license key
   if(LicenseKey != VALID_LICENSE)
     {
      Alert("INVALID LICENSE KEY!");
      Alert("Please enter valid license key in EA settings.");
      Alert("Go to: Expert Properties -> Inputs -> License Key");
      isLicenseValid = false;
      return(false);
     }
   
   //--- License is valid
   isLicenseValid = true;
   lastLicenseCheck = currentTime;  // Save verification time
   Print("License verified successfully. Valid until: ", TimeToString(EXPIRY_DATE, TIME_DATE));
   
   //--- Calculate days remaining
   int daysRemaining = (int)((EXPIRY_DATE - currentTime) / 86400);
   if(daysRemaining <= 30)
     {
      Alert("LICENSE WARNING: Only ", daysRemaining, " days remaining!");
     }
   
   return(true);
  }

//+------------------------------------------------------------------+
