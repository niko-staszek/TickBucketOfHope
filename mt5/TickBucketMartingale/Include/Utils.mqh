//+------------------------------------------------------------------+
//| Utils.mqh — small helpers shared across modules.                 |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_UTILS_MQH
#define TBM_MT5_UTILS_MQH

// MT4 order-type compat constants. MT5's POSITION_TYPE_BUY/SELL and
// ORDER_TYPE_BUY/SELL happen to share these numeric values, which lets
// the scenario code (P5) port 1:1 using the original MT4 `dir` ints.
#define OP_BUY  0
#define OP_SELL 1

//--- Period keys for grouping closed deals (used by Dashboard + History)
int DayKey(datetime t)   { MqlDateTime m; TimeToStruct(t,m); return m.year*10000 + m.mon*100 + m.day; }
int WeekKey(datetime t)  { return (int)(t / (7*86400)); }
int MonthKey(datetime t) { MqlDateTime m; TimeToStruct(t,m); return m.year*100 + m.mon; }

//--- Tester "fast mode" detection (MT5 equivalent of MT4's IsTesting())
bool TesterFastMode()
  {
   if(MQLInfoInteger(MQL_TESTER) == 0) return false;
   // In visual mode the user expects the dashboard; treat as non-fast.
   if(MQLInfoInteger(MQL_VISUAL_MODE) != 0) return false;
   return true;
  }

//--- Normalize lot size to the symbol's volume step / min / max, with
//    the EA's `max_Lot` cap applied. Matches MT4 behavior: rounds UP to
//    the next step (so averaging lots never under-shoot and get rejected
//    at the min-lot boundary).
double NormalizeLots(double lots)
  {
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;

   double k    = MathCeil(lots/step - 1e-9);
   double norm = k * step;

   if(norm < minLot) norm = minLot;
   if(norm > maxLot) norm = maxLot;
   if(max_Lot != 0.0 && norm > max_Lot) norm = max_Lot;

   return NormalizeDouble(norm, 8);
  }

//--- Current Ask/Bid shortcuts (MT4's Ask/Bid globals don't exist in MT5).
double AskPrice() { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double BidPrice() { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }

//--- Day-of-week replacement for MT4's DayOfWeek() (0=Sunday..6=Saturday).
int DayOfWeekNow()
  {
   MqlDateTime m;
   TimeToStruct(TimeCurrent(), m);
   return m.day_of_week;
  }

//--- HHMM → minutes; returns -1 on garbage like 2399, 195. Matches MT4 ToMinutes.
int ToMinutes(int t)
  {
   int h = t / 100;
   int m = t % 100;
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
  }

//--- Price-touch tolerance for level deduplication. Matches MT4 TouchTolerance.
double TouchTolerance()
  {
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      return 0.10;
   if(_Digits == 3 || _Digits == 5)
      return _Point * 10;
   return _Point;
  }

//--- Daily candle rollover detector. Updates `currentCandle` in Globals.
bool isNewCandle()
  {
   datetime t = iTime(_Symbol, PERIOD_D1, 0);
   if(t == currentCandle) return false;
   currentCandle = t;
   return true;
  }

//--- M15 candle rollover detector. Updates `m15Candle` in Globals.
bool isNewM15Candle()
  {
   datetime t = iTime(_Symbol, PERIOD_M15, 0);
   if(t == m15Candle) return false;
   m15Candle = t;
   return true;
  }

#endif // TBM_MT5_UTILS_MQH
