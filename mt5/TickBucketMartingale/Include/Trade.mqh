//+------------------------------------------------------------------+
//| Trade.mqh — MT4-flavored wrappers over MT5's trade API.          |
//|                                                                   |
//| Mission: let the scenario ports (P5) read as close to the MT4    |
//| source as possible. Wrapper names mirror MT4 helpers.             |
//|                                                                   |
//| Ticket type: `ulong` throughout. MT5 position tickets can exceed |
//| INT_MAX so using `int` (as MT4 did) is unsafe.                   |
//|                                                                   |
//| Semantic difference flagged: FindOldestOpenOrder returns a        |
//| TICKET in MT5 (MT4 returned a position index into OrdersTotal).   |
//| P5 scenario callers are adapted accordingly.                     |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_TRADE_MQH
#define TBM_MT5_TRADE_MQH

#include <Trade/PositionInfo.mqh>

CTrade                  g_trade;
CPositionInfo           g_pos;
ENUM_ORDER_TYPE_FILLING g_fillingMode = ORDER_FILLING_FOK;

//--- Pick a filling mode supported by the current symbol.
ENUM_ORDER_TYPE_FILLING ResolveFillingMode()
  {
   long flags = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((flags & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((flags & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

bool Trade_Init()
  {
   g_fillingMode = ResolveFillingMode();
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(3);
   g_trade.SetTypeFilling(g_fillingMode);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   PrintFormat("Trade_Init: symbol=%s filling=%d MagicNumber=%d", _Symbol, (int)g_fillingMode, MagicNumber);
   return true;
  }

//==================================================================
// POSITION ITERATION (CPositionInfo-backed)
//==================================================================

//--- Is the currently-selected CPositionInfo ours? (symbol + magic)
bool PositionIsOurs()
  {
   return g_pos.Symbol() == _Symbol
          && g_pos.Magic()  == (long)MagicNumber;
  }

//--- Direction of the currently-selected position, in OP_BUY/SELL terms.
int PositionDir()
  {
   return (g_pos.PositionType() == POSITION_TYPE_BUY) ? OP_BUY : OP_SELL;
  }

//--- Total open positions on this symbol + magic (both directions).
int CountAllOrders()
  {
   int counter = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(!PositionIsOurs()) continue;
      counter++;
     }
   return counter;
  }

//--- Count of positions for one direction (MT4 amountOfOrders).
int amountOfOrders(int orderType)
  {
   int counter = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != orderType) continue;
      counter++;
     }
   return counter;
  }

//--- Find oldest open position's TICKET (MT5 semantic: ticket, not index).
ulong FindOldestOpenOrder(int orderType)
  {
   datetime oldest   = LONG_MAX;
   ulong    oldestTk = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != orderType) continue;
      if(g_pos.Time() < oldest)
        {
         oldest   = g_pos.Time();
         oldestTk = g_pos.Ticket();
        }
     }
   return oldestTk;
  }

//--- Find the farthest same-direction position from basePrice.
ulong FindFarthestTicket_NoComments(int dir, double basePrice, double &dmax_out)
  {
   dmax_out = 0.0;
   ulong    farTk   = 0;
   datetime farTime = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != dir) continue;
      double   p = g_pos.PriceOpen();
      datetime t = g_pos.Time();
      double   d = MathAbs(p - basePrice);
      if(d > dmax_out + 1e-12
         || (MathAbs(d - dmax_out) <= 1e-12 && t > farTime))
        {
         dmax_out = d;
         farTk    = g_pos.Ticket();
         farTime  = t;
        }
     }
   return farTk;
  }

//--- Find the most recent same-direction position EXCLUDING the base (oldest).
ulong FindLastNonBaseTicket(int dir)
  {
   ulong baseTk = FindOldestOpenOrder(dir);
   ulong    lastTk   = 0;
   datetime lastTime = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Ticket() == baseTk) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != dir) continue;
      if(g_pos.Time() > lastTime)
        {
         lastTime = g_pos.Time();
         lastTk   = g_pos.Ticket();
        }
     }
   return lastTk;
  }

//--- Collect every same-direction open ticket into `tickets`.
int CollectGroupAll_NoComments(int dir, ulong &tickets[])
  {
   ArrayResize(tickets, 0);
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != dir) continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = g_pos.Ticket();
     }
   return ArraySize(tickets);
  }

//--- Floating P/L (profit + swap + commission) for one direction's basket.
//    CPositionInfo::Commission() reads POSITION_COMMISSION — some brokers
//    expose it on live positions, others only on the IN deal (0 here).
double BasketFloatingPL(int dir)
  {
   double pl = 0.0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != dir) continue;
      pl += g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
     }
   return pl;
  }

//==================================================================
// LOT MATH
//==================================================================

//--- Next averaging lot by multiplier (Scenario B/C/D). Matches MT4.
double NextLotByMultiplier(double baseLot)
  {
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;

   double raw = baseLot * lotMultiplier;
   double k   = MathCeil(raw/step - 1e-9);
   double out = k * step;

   if(out < minLot) out = minLot;
   if(out > maxLot) out = maxLot;
   if(max_Lot != 0.0 && out > max_Lot) out = max_Lot;

   return NormalizeDouble(out, 8);
  }

//--- Hedge lot that would bring position (p1/l1) to BE+xPoints
//    when paired with a new entry at p2 with TP at tpPrice (Scenario A).
double RequiredLotForBEPlusX(int direction, double p1, double l1, double p2, double tpPrice, int xPoints)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(l1 <= 0) return -1;

   double tpAdj = (direction == OP_BUY)
                  ? (tpPrice - xPoints * _Point)
                  : (tpPrice + xPoints * _Point);

   double denom = (tpAdj - p2);
   double numer = l1 * (p1 - tpAdj);

   if(MathAbs(denom) < 1e-10) return -1;
   double l2 = numer / denom;
   if(l2 <= 0) return minLot;
   return NormalizeLots(l2);
  }

//==================================================================
// TP MATH
//==================================================================

//--- Clamp a raw TP to broker's stop/freeze levels. Returns the clamped
//    TP, already normalized to the symbol's digits.
double ClampTPToStops(int dir, double rawTP)
  {
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze    = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double mind   = (stopLevel + freeze) * _Point;

   double ask = AskPrice();
   double bid = BidPrice();

   double tp = rawTP;
   if(dir == OP_BUY  && tp < ask + mind) tp = ask + mind;
   if(dir == OP_SELL && tp > bid - mind) tp = bid - mind;
   return NormalizeDouble(tp, _Digits);
  }

//--- Weighted-average basket TP at BE + xPoints across all tickets of `dir`.
double GroupTP_BEPlusX_All(int dir, const ulong &tickets[], int xPoints)
  {
   double sumL = 0.0, sumLP = 0.0;
   int n = ArraySize(tickets);
   for(int k = 0; k < n; ++k)
     {
      if(!PositionSelectByTicket(tickets[k])) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != dir) continue;
      double l = PositionGetDouble(POSITION_VOLUME);
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      sumL  += l;
      sumLP += l * p;
     }
   if(sumL <= 0.0) return 0.0;

   double wavg  = sumLP / sumL;
   double rawTP = (dir == OP_BUY) ? (wavg + xPoints * _Point)
                                  : (wavg - xPoints * _Point);
   return ClampTPToStops(dir, rawTP);
  }

//--- Set TP on a single position via TRADE_ACTION_SLTP.
bool SetTP(ulong ticket, double newTP)
  {
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   if(!PositionIsOurs()) return false;

   double sl = PositionGetDouble(POSITION_SL);
   double tp = NormalizeDouble(newTP, _Digits);
   if(!g_trade.PositionModify(ticket, sl, tp))
     {
      PrintFormat("SetTP fail tk=%I64u tp=%.*f retcode=%d",
                  ticket, _Digits, tp, (int)g_trade.ResultRetcode());
      return false;
     }
   return true;
  }

//==================================================================
// MARGIN CHECK (MT5 replacement for MT4's AccountFreeMarginCheck)
//==================================================================

//--- Returns true if account free margin is enough to open `lot` in `dir`.
bool HasFreeMargin(int dir, double lot)
  {
   double price = (dir == OP_BUY) ? AskPrice() : BidPrice();
   double needed = 0.0;
   ENUM_ORDER_TYPE ot = (dir == OP_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ot, _Symbol, lot, price, needed)) return false;
   return AccountInfoDouble(ACCOUNT_MARGIN_FREE) > needed;
  }

//==================================================================
// TRADE ACTIONS
//==================================================================

//--- Open a market order in `dir` with `lot` and optional tp/comment.
//    Returns the POSITION ticket (0 on failure). Built on CTrade +
//    DEAL_POSITION_ID lookup so the caller can store the ticket for
//    later TP modifications.
ulong OpenMarket(int dir, double lot, double tp, const string comment)
  {
   double price = (dir == OP_BUY) ? AskPrice() : BidPrice();
   bool ok;
   if(dir == OP_BUY)
      ok = g_trade.Buy(lot, _Symbol, price, 0.0, tp, comment);
   else
      ok = g_trade.Sell(lot, _Symbol, price, 0.0, tp, comment);

   if(!ok)
     {
      PrintFormat("OpenMarket FAIL dir=%d lot=%.2f retcode=%d comment=%s",
                  dir, lot, (int)g_trade.ResultRetcode(), comment);
      return 0;
     }

   ulong deal = g_trade.ResultDeal();
   if(deal == 0) return 0;
   if(!HistoryDealSelect(deal)) return 0;
   return (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
  }

//--- Close one position by ticket.
bool ClosePositionByTicket(ulong ticket)
  {
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   if(!PositionIsOurs()) return false;
   return g_trade.PositionClose(ticket);
  }

//--- Close every open position for this symbol + magic (both directions).
void CloseAllOrders()
  {
   int active = CountAllOrders();
   if(active <= 0) return;
   Print("Active Orders: ", active);

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(!PositionIsOurs()) continue;
      g_trade.PositionClose(tk);
     }
  }

//--- Close every same-direction open position (for the dashboard buttons).
void CloseAllOrdersType(int orderType)
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != orderType) continue;
      g_trade.PositionClose(tk);
     }
  }

//--- Close profitable same-direction positions (for the dashboard buttons).
void CloseProfitOrders(int orderType)
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(!PositionIsOurs()) continue;
      if(PositionDir() != orderType) continue;
      double profit = PositionGetDouble(POSITION_PROFIT)
                      + PositionGetDouble(POSITION_SWAP);
      if(profit <= 0) continue;
      g_trade.PositionClose(tk);
     }
  }

#endif // TBM_MT5_TRADE_MQH
