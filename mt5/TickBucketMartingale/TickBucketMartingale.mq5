//+------------------------------------------------------------------+
//|                                   Tick Bucket Martingale EA (MT5) |
//|               MT4 → MT5 port — scaffold only (P1).                |
//|               Logic is ported phase by phase (P2..P10).           |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"

#include <Trade/Trade.mqh>

// Dependency order:
//   Inputs → Globals → Utils → Trade → History → Session
//   → TickBuckets → Scenarios → Persistence → Dashboard
#include "Include/Inputs.mqh"
#include "Include/Globals.mqh"
#include "Include/Utils.mqh"
#include "Include/Trade.mqh"
#include "Include/History.mqh"
#include "Include/Session.mqh"
#include "Include/TickBuckets.mqh"
#include "Include/SRZones.mqh"
#include "Include/Scenarios.mqh"
#include "Include/Persistence.mqh"
#include "Include/Dashboard.mqh"

//+------------------------------------------------------------------+
//| Hedging-account guard                                             |
//|                                                                   |
//| The MT4 EA assumes independent Buy and Sell baskets on the same   |
//| symbol. MT5 netting accounts collapse opposite-direction orders   |
//| into a single position, which silently destroys the strategy.    |
//| Refuse to initialize on non-hedging accounts.                    |
//+------------------------------------------------------------------+
bool RequireHedgingAccount()
  {
   long mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      PrintFormat("TickBucketMartingale(MT5): aborting — account margin mode is %d; requires ACCOUNT_MARGIN_MODE_RETAIL_HEDGING (%d). "
                  "Buy and Sell baskets must coexist for this EA to function.",
                  (int)mode, (int)ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!RequireHedgingAccount())
      return INIT_FAILED;

   if(!Trade_Init())
      return INIT_FAILED;

   if(!TickBuckets_Init())
      return INIT_FAILED;

   Persistence_Init();
   Session_Init();

   Print("TickBucketMartingale MT5 v1.00 — init OK");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SaveTickBucketsToFile();
   TickBuckets_Deinit();
  }

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
  {
   // -- Dashboard + period stats (skipped in tester fast mode) --
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

   // -- Session gate --
   if(!IsTradingTime()) return;

   // -- Day rollover bookkeeping --
   if(isNewCandle())
     {
      TimeToStruct(TimeCurrent(), str1);
      year  = str1.year;
      month = str1.mon;
      day_  = str1.day;
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      accountDailyProfit = bal * (dailyProfit / 100.0);
      accountDailyLost   = bal * (-dailyLost  / 100.0);

      gTradingStoppedToday = false;

      closeAllHour = StringToTime(IntegerToString(year) + "."
                                  + IntegerToString(month) + "."
                                  + IntegerToString(day_) + " "
                                  + IntegerToString(closeTimeHour) + ":"
                                  + IntegerToString(closeTimeMinute));

      if(!TesterFastMode())
        {
         LogDailyMargins(margine, freeMargin);
         CleanupAllObjects();
        }
     }

   static datetime last_min       = 0;
   static datetime last_tick_save = 0;
   datetime now = TimeCurrent();
   int allOrders = CountAllOrders();

   UpdateStartEndFromSets();

   double acctProfit = AccountInfoDouble(ACCOUNT_PROFIT);

   if(acctProfit >= accountDailyProfit && dailyProfit != 0.0)
     {
      CloseAllOrders();
      endHour = now;
      gTradingStoppedToday = true;
     }

   if(acctProfit <= accountDailyLost && dailyLost != 0.0)
     {
      CloseAllOrders();
      endHour = now;
      gTradingStoppedToday = true;
     }

   if(now >= endHour && allOrders > 0 && autoCloseTrigger)
     {
      double profit        = ProfitForDay(TimeCurrent(), MagicNumber, _Symbol);
      double profitTrigger = profit * (-0.1);
      double currentProfit = acctProfit;
      if(currentProfit < 0 && profitTrigger < currentProfit)
        {
         PrintFormat("Profit Trigger: %.2f  current: %.2f  total: %.2f",
                     profitTrigger, currentProfit, profit);
         CloseAllOrders();
        }
     }

   if(now >= closeAllHour && allOrders > 0 && closeTimeHour < 24)
      CloseAllOrders();

   // -- Scenario C state cleanup (detect when the tracked base closed) --
   CheckScenarioCBasketClosed();

   // -- Tick engine --
   ProcessTickBuckets();

   if(now - last_min >= 60) last_min = now;

   if(PersistTickAcrossTF && !TesterFastMode() && now - last_tick_save >= PersistSaveEverySec)
     {
      last_tick_save = now;
      SaveTickBucketsToFile();
     }

   if(isNewM15Candle())
      ResetAllTickBuckets();

   if(useSRZones)
     {
      if(TesterFastMode())
        {
         if(isNewM15Candle()) DetectSRZones();
        }
      else
        {
         DetectSRZones();
        }
     }

   // Second dashboard refresh after the trading logic, matching MT4 behavior.
   if(!TesterFastMode())
     {
      DrawDashboard();
      CheckButtonClicks();
     }
  }

//+------------------------------------------------------------------+
//| Chart events (dashboard button clicks)                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
      CheckButtonClicks();
  }
