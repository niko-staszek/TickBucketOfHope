//+------------------------------------------------------------------+
//| TickBuckets.mqh — Tick Order Flow (TOF) entry engine.            |
//|                                                                   |
//| Counts ticks falling into price bins. When a bin reaches          |
//| TickMinCount, we publish a "level" at that price and (if inside  |
//| the active trading window and slope agrees with direction) we    |
//| hand off to OpenPositions() to fire scenarios.                   |
//|                                                                   |
//| State lives in Globals.mqh: tick_buckets[], levels[], etc.       |
//|                                                                   |
//| MT4 → MT5 notes:                                                  |
//|   * iMA returns a handle in MT5 — cached in g_maHandleSlope and  |
//|     sampled via CopyBuffer per tick.                              |
//|   * Ask/Bid/Point/Digits/Symbol/Period replaced with _Symbol /    |
//|     _Point / _Digits / _Period / AskPrice()/BidPrice().           |
//|   * ObjectCreate needs an explicit chart_id=0 arg (same as MT4    |
//|     here, kept for clarity).                                      |
//|                                                                   |
//| AI support/resistance (AISupportResistance) and the rest of the  |
//| pivot helpers are NOT ported yet — they are heavy (iMA/iATR/      |
//| pivothigh_close/etc. all need handle management) and gated behind |
//| the `aiZone` input which is false in the active preset. Stubbed  |
//| below; port when `aiZone` is ever flipped true.                   |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_TICKBUCKETS_MQH
#define TBM_MT5_TICKBUCKETS_MQH

// Forward declaration — OpenPositions lives in Scenarios.mqh (P5).
// Stubbed there so the tick engine compiles and runs in isolation.
void OpenPositions(double price, int direction);

//==================================================================
// SYMBOL PARAMETERS
//==================================================================
void CalculateSymbolParameters()
  {
   symbol_point = _Point;
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      symbol_pip_value = 0.1;
   else if(StringFind(_Symbol, "BTC") >= 0 || StringFind(_Symbol, "BITCOIN") >= 0)
      symbol_pip_value = 1.0;
   else if(_Digits == 5 || _Digits == 3)
      symbol_pip_value = _Point * 10;
   else
      symbol_pip_value = _Point;
  }

//==================================================================
// TICK BIN MATH
//==================================================================
double DefaultBinSize()
  {
   if(TickBinSize > 0.0) return TickBinSize;
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0) return 0.10;
   if(_Digits == 5 || _Digits == 3) return _Point * 10;
   return _Point;
  }

double BinPrice(double price)
  {
   double step = DefaultBinSize();
   if(step <= 0.0) step = _Point;
   double k = MathRound(price / step);
   return k * step;
  }

int FindBucket(double price_bin)
  {
   // O(4000) most recent, matches MT4 bound.
   for(int i = tick_bucket_cnt - 1; i >= 0 && i >= tick_bucket_cnt - 4000; --i)
      if(MathAbs(tick_buckets[i].price_bin - price_bin) <= (DefaultBinSize() / 2.0))
         return i;
   return -1;
  }

//==================================================================
// LEVEL REGISTRY
//==================================================================
void AddLevel(datetime start_time, double price, string color_name, color line_color, int width, ENUM_LINE_STYLE style, ENUM_TIMEFRAMES tf)
  {
   if(levels_count >= max_levels) return;

   TimeToStruct(start_time, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime date = StructToTime(dt);

   VolumeLevel L;
   L.date             = date;
   L.start_time       = start_time;
   L.end_time         = 0;
   L.price            = price;
   L.color_name       = color_name;
   L.line_color       = line_color;
   L.line_width       = width;
   L.line_style       = style;
   L.resolved         = false;
   L.max_volume       = 0;
   L.source_timeframe = tf;
   L.object_name      = color_name + "_" + _Symbol + "_"
                        + TimeToString(start_time, TIME_DATE | TIME_MINUTES | TIME_SECONDS)
                        + "_" + DoubleToString(price, _Digits);

   levels[levels_count] = L;
   levels_count++;
  }

bool LevelExistsNear(double price)
  {
   double tol = TouchTolerance();
   for(int i = levels_count - 1; i >= 0 && i >= levels_count - 2000; --i)
      if(MathAbs(levels[i].price - price) <= tol)
         return true;
   return false;
  }

//==================================================================
// MARKET SLOPE (EMA-slope direction filter)
//==================================================================

//--- Create the slope MA handle. Must be called from OnInit before the
//    first tick. Returns false if the handle can't be created.
bool Slope_Init()
  {
   g_maHandleSlope = iMA(_Symbol, PERIOD_CURRENT, maPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_maHandleSlope == INVALID_HANDLE)
     {
      PrintFormat("Slope_Init fail: iMA handle invalid (err=%d)", GetLastError());
      return false;
     }
   return true;
  }

void Slope_Deinit()
  {
   if(g_maHandleSlope != INVALID_HANDLE)
     {
      IndicatorRelease(g_maHandleSlope);
      g_maHandleSlope = INVALID_HANDLE;
     }
  }

//--- Returns +1 if slope >  thresholdPts, -1 if < -thresholdPts, else 0.
//    Matches MT4 MarketSlopeSignal. `symbol`/`timeframe` args are kept
//    for MT4 signature parity — MT5 implementation uses the cached
//    current-chart handle only.
int MarketSlopeSignal(string symbol, int timeframe, int maPeriod_, int slopeLookbackBars_, double slopeThresholdPts_)
  {
   if(g_maHandleSlope == INVALID_HANDLE) return 0;
   if(iBars(_Symbol, PERIOD_CURRENT) <= maPeriod_ + slopeLookbackBars_ + 2) return 0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_maHandleSlope, 0, 0, slopeLookbackBars_ + 1, buf) <= 0) return 0;

   double ma_now = buf[0];
   double ma_old = buf[slopeLookbackBars_];
   double slope_pts_per_bar = (ma_now - ma_old) / _Point / slopeLookbackBars_;

   if(slope_pts_per_bar >  slopeThresholdPts_) return 1;
   if(slope_pts_per_bar < -slopeThresholdPts_) return -1;
   return 0;
  }

//==================================================================
// TICK LEVEL DRAWING + TRADE TRIGGER
//==================================================================
void CreateDirectionArrow(datetime t, double price, int dir)
  {
   if(TesterFastMode()) return;
   if(!ShowTickArrows)  return;

   string name = StringFormat("TickDir_%s_%s_%d",
                              _Symbol,
                              TimeToString(t, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                              (int)(price * 10000));

   double offset    = TickArrowOffset * DefaultBinSize();
   double y         = price;
   int    arrowCode = 0;
   color  c         = clrWhite;

   if(dir > 0)
     {
      arrowCode = 233;
      c = TickArrowBuyColor;
      y = price - offset;
     }
   else
     {
      arrowCode = 234;
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

void CreateTickLevel(datetime t, double price, int dir)
  {
   string tag = (dir > 0 ? "TickBuy" : (dir < 0 ? "TickSell" : "Tick"));
   AddLevel(t, price, tag, TickColor, TickWidth, TickStyle, (ENUM_TIMEFRAMES)_Period);

   // Directional trade trigger
   if(dir != 0)
     {
      CreateDirectionArrow(t, price, dir);
      int marketDirection = MarketSlopeSignal(_Symbol, 0, maPeriod, slopeLookbackBars, slopeThresholdPts);

      if(TimeCurrent() > startHour && TimeCurrent() < endHour)
        {
         if(dir < 0 && marketDirection <= 0)
            OpenPositions(price, dir);
         if(dir > 0 && marketDirection >= 0)
            OpenPositions(price, dir);
        }
     }

   // If not "until done" — end level after N candles
   if(!TickUntilDone)
     {
      int ps = PeriodSeconds(_Period);
      datetime start_bar = iTime(_Symbol, _Period, 1);
      datetime end_t = start_bar + (ps * TickExtendBars);
      int idx = levels_count - 1;
      if(idx >= 0)
        {
         levels[idx].resolved = true;
         levels[idx].end_time = end_t;
        }
     }
  }

//==================================================================
// TICK BUCKET PROCESSING
//==================================================================
void ResetAllTickBuckets()
  {
   ArrayResize(tick_buckets, 0);
   tick_bucket_cnt = 0;
   g_lastTickPrice = 0.0;
   ArrayResize(levels, 0);
   ArrayResize(levels, max_levels);
   levels_count       = 0;
   last_data_save     = 0;
   last_history_check = 0;
  }

void ResetTickBucketsIfNeeded()
  {
   if(!TickResetDaily) return;

   TimeToStruct(TimeCurrent(), dt);
   if(last_bucket_day == -1)
      last_bucket_day = dt.day;
   if(dt.day != last_bucket_day)
     {
      // P9 will add SaveTickBucketsToFile() here.
      ResetAllTickBuckets();
      last_bucket_day = dt.day;
     }
  }

void ProcessTickBuckets()
  {
   if(!ShowTickLevels)
     {
      g_lastTickPrice = BidPrice();
      return;
     }

   double   price = BidPrice();
   double   bin   = BinPrice(price);
   datetime now   = TimeCurrent();

   int idx = FindBucket(bin);
   if(idx < 0)
     {
      TickBucket tb;
      tb.price_bin     = bin;
      tb.count         = 1;
      tb.first_time    = now;
      tb.last_time     = now;
      tb.level_created = false;
      ArrayResize(tick_buckets, tick_bucket_cnt + 1);
      tick_buckets[tick_bucket_cnt] = tb;
      idx = tick_bucket_cnt;
      tick_bucket_cnt++;
     }
   else
     {
      tick_buckets[idx].count++;
      tick_buckets[idx].last_time = now;
     }

   // Threshold hit → publish a level (once per bin).
   if(!tick_buckets[idx].level_created && tick_buckets[idx].count >= TickMinCount)
     {
      if(!LevelExistsNear(bin))
        {
         int dir = 0;
         if(g_lastTickPrice > 0.0)
           {
            if(price > g_lastTickPrice)      dir = 1;
            else if(price < g_lastTickPrice) dir = -1;
           }
         CreateTickLevel(now, bin, dir);
         tick_buckets[idx].level_created = true;
        }
     }

   g_lastTickPrice = price;
  }

//==================================================================
// INIT / DEINIT for the tick engine
//==================================================================
bool TickBuckets_Init()
  {
   CalculateSymbolParameters();
   ArrayResize(levels, max_levels);
   levels_count    = 0;
   tick_bucket_cnt = 0;
   last_bucket_day = -1;
   g_lastTickPrice = 0.0;
   if(!Slope_Init()) return false;
   return true;
  }

void TickBuckets_Deinit()
  {
   Slope_Deinit();
  }

#endif // TBM_MT5_TICKBUCKETS_MQH
