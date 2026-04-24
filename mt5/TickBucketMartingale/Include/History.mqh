//+------------------------------------------------------------------+
//| History.mqh — closed-deal iteration for dashboard period stats.  |
//|                                                                   |
//| MT4 `RefreshPeriodStats` iterates `OrdersHistoryTotal()` and sums |
//| OrderProfit+Swap+Commission for each closed order, bucketed by    |
//| today/week/month. MT5 has no "closed order" concept — closures    |
//| are represented as DEALS with DEAL_ENTRY == DEAL_ENTRY_OUT.       |
//|                                                                   |
//| Port:                                                             |
//|   * HistorySelect(windowStart, now) once per refresh (from start  |
//|     of the month — widest bucket we track).                       |
//|   * For each OUT deal in the window matching symbol + magic:      |
//|       - profit = DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION        |
//|       - side   = opposite of DEAL_TYPE (SELL-type closes BUY pos) |
//|       - time   = DEAL_TIME  (the closing time)                    |
//|     Bucket by DayKey/WeekKey/MonthKey.                            |
//|                                                                   |
//| Known gap: brokers that book commission on the IN deal will have  |
//| their open-leg commission excluded here. For the dashboard this  |
//| is tolerable (the number lags reality by the IN-commission sum).  |
//| Escalate to scanning IN deals if/when that broker is in use.      |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_HISTORY_MQH
#define TBM_MT5_HISTORY_MQH

//--- Start of the current month as a datetime. Used as the HistorySelect
//    lower bound so a single scan covers today + week + month buckets.
datetime StartOfMonth(datetime t)
  {
   MqlDateTime m;
   TimeToStruct(t, m);
   m.day = 1;
   m.hour = 0;
   m.min  = 0;
   m.sec  = 0;
   return StructToTime(m);
  }

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

   datetime from = StartOfMonth(now);
   // A week can straddle the month boundary — extend the lower bound
   // a full week back so Sunday-of-last-month still gets counted into
   // the current week bucket.
   from -= 7 * 86400;

   if(!HistorySelect(from, now))
      return;

   int ht = HistoryDealsTotal();
   for(int i = 0; i < ht; ++i)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;

      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)MagicNumber) continue;

      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;  // only closing legs count

      datetime ct = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(ct <= 0) continue;

      double p = HistoryDealGetDouble(deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(deal, DEAL_SWAP)
                 + HistoryDealGetDouble(deal, DEAL_COMMISSION);

      long dealType = HistoryDealGetInteger(deal, DEAL_TYPE);
      bool isBuy = (dealType == DEAL_TYPE_SELL);  // OUT deal type is opposite of position side

      if(DayKey(ct) == dk)
        {
         if(isBuy) { g_closedBuyToday++;  g_profitBuyToday  += p; }
         else      { g_closedSellToday++; g_profitSellToday += p; }
        }
      if(WeekKey(ct) == wk)
        {
         if(isBuy) { g_closedBuyWeek++;  g_profitBuyWeek  += p; }
         else      { g_closedSellWeek++; g_profitSellWeek += p; }
        }
      if(MonthKey(ct) == mk)
        {
         if(isBuy) { g_closedBuyMonth++;  g_profitBuyMonth  += p; }
         else      { g_closedSellMonth++; g_profitSellMonth += p; }
        }
     }
  }

//--- Sum P/L (profit + swap + commission) over OUT deals closed on a given day.
//    _magic = -1  → match any magic.
//    symbol = ""  → match any symbol.
double ProfitForDay(datetime day, int _magic = -1, string symbol = "")
  {
   datetime start = StringToTime(TimeToString(day, TIME_DATE));  // midnight
   datetime end   = start + 86400;

   if(!HistorySelect(start, end)) return 0.0;

   double sum = 0.0;
   int ht = HistoryDealsTotal();
   for(int i = 0; i < ht; ++i)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      if(_magic != -1 && (long)HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)_magic) continue;
      if(symbol  != ""  && HistoryDealGetString(deal, DEAL_SYMBOL) != symbol) continue;

      sum += HistoryDealGetDouble(deal, DEAL_PROFIT)
             + HistoryDealGetDouble(deal, DEAL_SWAP)
             + HistoryDealGetDouble(deal, DEAL_COMMISSION);
     }
   return sum;
  }

#endif // TBM_MT5_HISTORY_MQH
