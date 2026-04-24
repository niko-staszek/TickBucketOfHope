//+------------------------------------------------------------------+
//| SRZones.mqh — volume-weighted support/resistance zone detector.  |
//|                                                                   |
//| Classical technical indicator (no ML despite the original MT4    |
//| "AI" label). Combines three signals:                              |
//|   * ATR (Wilder's RMA) → adaptive zone width.                     |
//|   * Cumulative delta-volume over bars (tick volume signed by      |
//|     bar direction: close >= open → +, close < open → −).         |
//|   * Pivots (swing highs/lows on close) over `lookbackPeriod`.    |
//|                                                                   |
//| Rules:                                                            |
//|   * Support band at pivot-low where cumulative vol is HIGH.       |
//|     Band = [pLow − ATR*box_withd, pLow].                          |
//|   * Resistance band at pivot-high where cumulative vol is LOW.    |
//|     Band = [pHigh, pHigh + ATR*box_withd].                        |
//|                                                                   |
//| Writes gSupport/Resistance globals. OpenPositions reads them to   |
//| widen the TP (tpRange × tpMultiplier) when a tick fires inside    |
//| a zone.                                                           |
//|                                                                   |
//| MT5 differences vs MT4:                                           |
//|   * No bar-series globals (Close[], High[], etc.) — fetched into  |
//|     local arrays via CopyHigh/CopyLow/CopyClose/CopyOpen/         |
//|     CopyTime/CopyTickVolume with ArraySetAsSeries(true).          |
//|   * iVolume returns long — kept as long throughout.               |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_SRZONES_MQH
#define TBM_MT5_SRZONES_MQH

//==================================================================
// PURE MATH (series-indexed: i=0 current bar, i=N-1 oldest)
//==================================================================

double TR_i(const double &hi[], const double &lo[], const double &cl[], int i)
  {
   double tr1 = hi[i] - lo[i];
   double tr2 = MathAbs(hi[i] - cl[i+1]);
   double tr3 = MathAbs(lo[i] - cl[i+1]);
   return MathMax(tr1, MathMax(tr2, tr3));
  }

double rma_step(const double &ma[], const double &val[], int len, int i)
  {
   return (val[i] + (len - 1) * ma[i+1]) / len;
  }

double highest_forward(const double &series[], int length1, int i)
  {
   double mx = series[i];
   int ub = MathMin(i + length1, ArraySize(series) - 1);
   for(int k = i + 1; k < ub; ++k)
      mx = MathMax(mx, series[k]);
   return mx;
  }

double lowest_forward(const double &series[], int length1, int i)
  {
   double mn = series[i];
   int ub = MathMin(i + length1, ArraySize(series) - 1);
   for(int k = i + 1; k < ub; ++k)
      mn = MathMin(mn, series[k]);
   return mn;
  }

double pivothigh_close(const double &arr[], int left, int right, int i)
  {
   if(ArraySize(arr) <= i + right + left) return 0.0;
   double pivot = arr[i + right];
   for(int j = 1; j <= left; ++j)
      if(pivot < arr[i + right + j]) return 0.0;
   for(int j = 1; j <= right; ++j)
      if(pivot < arr[i + right - j]) return 0.0;
   return pivot;
  }

double pivotlow_close(const double &arr[], int left, int right, int i)
  {
   if(ArraySize(arr) <= i + right + left) return 0.0;
   double pivot = arr[i + right];
   for(int j = 1; j <= left; ++j)
      if(pivot > arr[i + right + j]) return 0.0;
   for(int j = 1; j <= right; ++j)
      if(pivot > arr[i + right - j]) return 0.0;
   return pivot;
  }

//==================================================================
// MAIN: detect latest support/resistance zones and update globals
//==================================================================
bool DetectSRZones()
  {
   int bars = Bars(_Symbol, _Period);
   int need = MathMax(atr_period, vol_len) + lookbackPeriod + 10;
   if(bars < need) return false;

   // Fetch bar series as time-series arrays (i=0 newest).
   double aHi[], aLo[], aCl[], aOp[];
   long   aVo[];
   datetime aTi[];
   ArraySetAsSeries(aHi, true);
   ArraySetAsSeries(aLo, true);
   ArraySetAsSeries(aCl, true);
   ArraySetAsSeries(aOp, true);
   ArraySetAsSeries(aVo, true);
   ArraySetAsSeries(aTi, true);

   int copyN = MathMin(bars, need + 50);
   if(CopyHigh(_Symbol,       _Period, 0, copyN, aHi) <= 0) return false;
   if(CopyLow(_Symbol,        _Period, 0, copyN, aLo) <= 0) return false;
   if(CopyClose(_Symbol,      _Period, 0, copyN, aCl) <= 0) return false;
   if(CopyOpen(_Symbol,       _Period, 0, copyN, aOp) <= 0) return false;
   if(CopyTickVolume(_Symbol, _Period, 0, copyN, aVo) <= 0) return false;
   if(CopyTime(_Symbol,       _Period, 0, copyN, aTi) <= 0) return false;

   int n = ArraySize(aHi);

   static double tr[], atr[], posVol[], negVol[], Vol[];
   ArrayResize(tr,     n);
   ArrayResize(atr,    n);
   ArrayResize(posVol, n);
   ArrayResize(negVol, n);
   ArrayResize(Vol,    n);

   tr[n-1]     = 0.0;
   atr[n-1]    = 0.0;
   posVol[n-1] = 0.0;
   negVol[n-1] = 0.0;
   Vol[n-1]    = 0.0;

   bool     foundSup = false, foundRes = false;
   double   supTop = 0, supBot = 0, resBot = 0, resTop = 0;
   datetime supT = 0, resT = 0;

   for(int i = n - 3; i >= 0; --i)
     {
      tr[i]  = TR_i(aHi, aLo, aCl, i);
      atr[i] = rma_step(atr, tr, atr_period, i);

      long tv = aVo[i];
      bool isBuyVolume = (aCl[i] >= aOp[i]);
      posVol[i] = 0.0;
      negVol[i] = 0.0;
      if(isBuyVolume)
         posVol[i] = posVol[i+1] + (double)tv;
      else
         negVol[i] = negVol[i+1] - (double)tv;
      Vol[i] = posVol[i] + negVol[i];

      double vol_hi = highest_forward(Vol, vol_len, i) / 2.5;
      double vol_lo = lowest_forward(Vol,  vol_len, i) / 2.5;

      double pHigh = pivothigh_close(aCl, lookbackPeriod, lookbackPeriod, i);
      double pLow  = pivotlow_close(aCl,  lookbackPeriod, lookbackPeriod, i);

      double width = atr[i] * box_withd;

      // Support: pivot low with elevated cumulative volume
      if(pLow != 0.0 && Vol[i] > vol_hi)
        {
         datetime t = aTi[i + lookbackPeriod];
         if(!foundSup || t > supT)
           {
            foundSup = true;
            supTop   = pLow;
            supBot   = pLow - width;
            supT     = t;
           }
        }
      // Resistance: pivot high with depressed cumulative volume
      if(pHigh != 0.0 && Vol[i] < vol_lo)
        {
         datetime t = aTi[i + lookbackPeriod];
         if(!foundRes || t > resT)
           {
            foundRes = true;
            resBot   = pHigh;
            resTop   = pHigh + width;
            resT     = t;
           }
        }
     }

   bool any = false;
   if(foundSup && (supT != gLastSupTime || MathAbs(supTop - gSupportTop) > 1e-12))
     {
      gSupportTop    = supTop;
      gSupportBottom = supBot;
      gLastSupTime   = supT;
      any = true;
     }
   if(foundRes && (resT != gLastResTime || MathAbs(resBot - gResistanceBottom) > 1e-12))
     {
      gResistanceBottom = resBot;
      gResistanceTop    = resTop;
      gLastResTime      = resT;
      any = true;
     }

   if(any && print_updates)
      PrintFormat("SR zones: RES[%.*f..%.*f] SUP[%.*f..%.*f]",
                  _Digits, gResistanceBottom, _Digits, gResistanceTop,
                  _Digits, gSupportTop,       _Digits, gSupportBottom);
   return any;
  }

#endif // TBM_MT5_SRZONES_MQH
