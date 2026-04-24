//+------------------------------------------------------------------+
//| Scenarios.mqh — A/B/C/D averaging modes + OpenPositions entry.   |
//|                                                                   |
//| Port of MT4 CallScenarioA/B/C/D + OpenPositions. Scenarios are   |
//| independent `if` checks (not else-if) so multiple may fire per    |
//| trigger tick — preserved verbatim.                                |
//|                                                                   |
//| Ticket type: ulong throughout. Tickets are POSITION tickets in   |
//| MT5 (via DEAL_POSITION_ID lookup in OpenMarket).                  |
//|                                                                   |
//| TP: real MT5 position TPs via SetTP (TRADE_ACTION_SLTP).          |
//| MT4's AddOrUpdateLocalTP shim is gone — positions carry real TPs. |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_SCENARIOS_MQH
#define TBM_MT5_SCENARIOS_MQH

//==================================================================
// SCENARIO A — BE lot on oldest position (same-direction)
//   Compute a lot that, paired with the oldest losing position,
//   brings the pair to break-even + bePoints. Open new same-dir
//   order with that lot. Both legs share the same TP.
//==================================================================
void CallScenarioA(int buyORsell)
  {
   if(buyORsell == OP_SELL)
     {
      ulong oldTk = FindOldestOpenOrder(OP_SELL);
      double posPrice = 0.0, posLot = 0.0;
      if(oldTk != 0 && PositionSelectByTicket(oldTk) && PositionIsOurs())
        {
         posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         posLot   = PositionGetDouble(POSITION_VOLUME);
        }

      double bid     = BidPrice();
      double tpPrice = bid - tpRange * _Point;
      double newLot  = RequiredLotForBEPlusX(OP_SELL, posPrice, posLot, bid, tpPrice, bePoints);

      ulong newTk = OpenMarket(OP_SELL, newLot, tpPrice, "VESellSA/AVG");
      if(newTk == 0) return;
      positionSellTime = TimeCurrent();
      SetTP(oldTk, tpPrice);  // pair old leg onto same TP
     }

   if(buyORsell == OP_BUY)
     {
      ulong oldTk = FindOldestOpenOrder(OP_BUY);
      double posPrice = 0.0, posLot = 0.0;
      if(oldTk != 0 && PositionSelectByTicket(oldTk) && PositionIsOurs())
        {
         posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         posLot   = PositionGetDouble(POSITION_VOLUME);
        }

      double ask     = AskPrice();
      double tpPrice = ask + tpRange * _Point;
      double newLot  = RequiredLotForBEPlusX(OP_BUY, posPrice, posLot, ask, tpPrice, bePoints);

      ulong newTk = OpenMarket(OP_BUY, newLot, tpPrice, "VEBuySA/AVG");
      if(newTk == 0) return;
      positionBuyTime = TimeCurrent();
      SetTP(oldTk, tpPrice);
     }
  }

//==================================================================
// SCENARIO B — Multiplier averaging (same-direction)
//   refLot = last-non-base lot (fallback to base lot) × lotMultiplier.
//   Whole basket gets a fresh BE+X shared TP.
//==================================================================
void CallScenarioB(int dir)
  {
   ulong baseTk = FindOldestOpenOrder(dir);
   if(baseTk == 0 || !PositionSelectByTicket(baseTk) || !PositionIsOurs())
      return;
   double baseLot = PositionGetDouble(POSITION_VOLUME);

   double refLot = baseLot;
   ulong  lastTk = FindLastNonBaseTicket(dir);
   if(lastTk != 0 && PositionSelectByTicket(lastTk) && PositionIsOurs())
      refLot = PositionGetDouble(POSITION_VOLUME);

   double newLot = NextLotByMultiplier(refLot);
   if(newLot <= 0.0 || !HasFreeMargin(dir, newLot))
      return;

   string comment = (dir == OP_BUY) ? "AVGBuy" : "AVGSell";
   ulong tk = OpenMarket(dir, newLot, 0.0, comment);
   if(tk == 0) return;

   if(dir == OP_BUY)  positionBuyTime  = TimeCurrent();
   if(dir == OP_SELL) positionSellTime = TimeCurrent();

   ulong tickets[];
   int n = CollectGroupAll_NoComments(dir, tickets);
   if(n >= 2)
     {
      double groupTP = GroupTP_BEPlusX_All(dir, tickets, bePoints);
      if(groupTP > 0)
         for(int i = 0; i < n; ++i)
            SetTP(tickets[i], groupTP);
     }
  }

//==================================================================
// SCENARIO C — Near/far distance averaging with internal state
//   Tracks own base + averages array. FAR hit = multiplied lot joins
//   the basket with shared TP. NEAR hit = base-lot auxiliary with
//   its own standalone TP.
//==================================================================
void CallScenarioC(int dir)
  {
   ulong baseTk = FindOldestOpenOrder(dir);
   if(baseTk == 0 || !PositionSelectByTicket(baseTk) || !PositionIsOurs())
      return;

   cBaseTk    = baseTk;
   cBasePrice = PositionGetDouble(POSITION_PRICE_OPEN);
   cBaseLot   = PositionGetDouble(POSITION_VOLUME);

   if(baseScenarioCSellOrder == 0 && scenarioCSellActive == false && dir == OP_SELL)
     {
      baseScenarioCSellOrder = (int)cBaseTk;  // kept as int-cast for field-type parity
      scenarioCSellActive    = true;
      cBaseSellPrice         = cBasePrice;
      cBaseSellLot           = cBaseLot;
      cBaseSellTk            = cBaseTk;
     }
   if(baseScenarioCBuyOrder == 0 && scenarioCBuyActive == false && dir == OP_BUY)
     {
      baseScenarioCBuyOrder = (int)cBaseTk;
      scenarioCBuyActive    = true;
      cBaseBuyPrice         = cBasePrice;
      cBaseBuyLot           = cBaseLot;
      cBaseBuyTk            = cBaseTk;
     }

   double px_now = (dir == OP_BUY) ? AskPrice() : BidPrice();

   // Reference is the last own-averaging point (fallback: base).
   double lastRef = cBasePrice;
   if(dir == OP_BUY  && cAvgCountBuy  > 0) lastRef = cAvgsBuy[cAvgCountBuy - 1].price;
   if(dir == OP_SELL && cAvgCountSell > 0) lastRef = cAvgsSell[cAvgCountSell - 1].price;

   double hyst    = MathMax(2 * _Point, DefaultBinSize() / 5.0);
   bool   farther = (dir == OP_BUY) ? (px_now < lastRef - hyst) : (px_now > lastRef + hyst);

   double lotBase = NormalizeLots(cBaseLot);
   double lotQual = lotBase;
   if(dir == OP_BUY  && cAvgCountBuy  > 0) lotQual = NextLotByMultiplier(cAvgsBuy[cAvgCountBuy - 1].lot);
   if(dir == OP_SELL && cAvgCountSell > 0) lotQual = NextLotByMultiplier(cAvgsSell[cAvgCountSell - 1].lot);

   double useLot = farther ? lotQual : lotBase;
   if(!HasFreeMargin(dir, useLot))
      return;

   string comment = farther ? "AVGC_FAR" : "AUXC_NEAR";
   ulong tk = OpenMarket(dir, useLot, 0.0, comment);
   if(tk == 0) return;

   if(farther)
     {
      // Record into own averaging array
      if(PositionSelectByTicket(tk) && PositionIsOurs())
        {
         double openP = PositionGetDouble(POSITION_PRICE_OPEN);
         double openL = PositionGetDouble(POSITION_VOLUME);
         if(dir == OP_BUY)
           {
            int n = cAvgCountBuy;
            ArrayResize(cAvgsBuy, n + 1);
            cAvgsBuy[n].tk    = tk;
            cAvgsBuy[n].price = openP;
            cAvgsBuy[n].lot   = openL;
            cAvgCountBuy      = n + 1;
           }
         else
           {
            int n = cAvgCountSell;
            ArrayResize(cAvgsSell, n + 1);
            cAvgsSell[n].tk    = tk;
            cAvgsSell[n].price = openP;
            cAvgsSell[n].lot   = openL;
            cAvgCountSell      = n + 1;
           }
        }

      // Group BE+X: base + own averages (this side)
      ulong tks[];
      ArrayResize(tks, 1);
      tks[0] = cBaseTk;
      int n = 1;
      if(dir == OP_BUY)
        {
         ArrayResize(tks, 1 + cAvgCountBuy);
         for(int i = 0; i < cAvgCountBuy; ++i) tks[n++] = cAvgsBuy[i].tk;
        }
      else
        {
         ArrayResize(tks, 1 + cAvgCountSell);
         for(int i = 0; i < cAvgCountSell; ++i) tks[n++] = cAvgsSell[i].tk;
        }
      if(n >= 2)
        {
         double tpGroup = GroupTP_BEPlusX_All(dir, tks, bePoints);
         if(tpGroup > 0)
            for(int i = 0; i < n; ++i)
               SetTP(tks[i], tpGroup);
        }
     }
   else
     {
      // NEAR: own TP (standalone, not part of basket)
      if(PositionSelectByTicket(tk) && PositionIsOurs())
        {
         double openP = PositionGetDouble(POSITION_PRICE_OPEN);
         double rawTP = (dir == OP_BUY) ? (openP + tpRange * _Point)
                                        : (openP - tpRange * _Point);
         double tp    = ClampTPToStops(dir, rawTP);
         SetTP(tk, tp);
        }
     }

   if(dir == OP_BUY)  positionBuyTime  = TimeCurrent();
   if(dir == OP_SELL) positionSellTime = TimeCurrent();
  }

//==================================================================
// SCENARIO D — Farthest-position multiplier (same-direction)
//   refLot = farthest-from-base position's lot × multiplier, but only
//   if the new entry would itself be farther from base than the
//   current farthest. Otherwise adds a base-lot order. Shared basket TP.
//==================================================================
void CallScenarioD(int dir)
  {
   ulong baseTk = FindOldestOpenOrder(dir);
   if(baseTk == 0 || !PositionSelectByTicket(baseTk) || !PositionIsOurs())
      return;

   double basePrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double baseLot   = PositionGetDouble(POSITION_VOLUME);

   double px_now = (dir == OP_BUY) ? AskPrice() : BidPrice();

   double d_max = 0.0;
   ulong  farTk = FindFarthestTicket_NoComments(dir, basePrice, d_max);

   double d_new   = MathAbs(px_now - basePrice);
   bool   farther = (d_new > d_max + (_Point * 1e-6));

   double refLot = baseLot;
   if(farTk != 0 && PositionSelectByTicket(farTk) && PositionIsOurs())
      refLot = PositionGetDouble(POSITION_VOLUME);

   double lotQual = NextLotByMultiplier(refLot);
   double lotBase = NormalizeLots(baseLot);

   double useLot = lotBase;
   string cmt    = (dir == OP_BUY) ? "VEBuyAVGDB" : "VESellAVGDB";

   if(farther)
     {
      if(lotQual > 0.0 && HasFreeMargin(dir, lotQual))
        {
         useLot = lotQual;
         cmt    = (dir == OP_BUY) ? "VEBuyAVGDQ" : "VESellAVGDQ";
        }
      else if(!HasFreeMargin(dir, lotBase))
         return;
     }
   else
     {
      if(!HasFreeMargin(dir, lotBase))
         return;
     }

   ulong tk = OpenMarket(dir, useLot, 0.0, cmt);
   if(tk == 0) return;

   if(dir == OP_BUY)  positionBuyTime  = TimeCurrent();
   if(dir == OP_SELL) positionSellTime = TimeCurrent();

   ulong tickets[];
   int n = CollectGroupAll_NoComments(dir, tickets);
   if(n >= 2)
     {
      double groupTP = GroupTP_BEPlusX_All(dir, tickets, bePoints);
      if(groupTP > 0)
         for(int i = 0; i < n; ++i)
            SetTP(tickets[i], groupTP);
     }
  }

//==================================================================
// ENTRY DISPATCHER — called by the tick engine when a level fires.
//==================================================================
void OpenPositions(double price, int direction)
  {
   if(g_eaStopped) return;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread >= maxSpread) return;

   //============ SELL branch ============
   if(TimeCurrent() > (positionSellTime + timeFilter))
     {
      if(scenarioC && scenarioCSellActive && direction < 0)
         CallScenarioC(OP_SELL);

      if(amountOfOrders(OP_SELL) < startBe)
        {
         if(direction < 0)
           {
            double bid = BidPrice();
            double tp  = bid - tpRange * _Point;
            // AI zone: resistance-bracket → widen TP by tpMultiplier
            if(AskPrice() > gResistanceBottom && AskPrice() < gResistanceTop)
               tp = bid - tpRange * tpMultiplier * _Point;

            ulong tk = OpenMarket(OP_SELL, lotSize, tp, "VESell");
            if(tk != 0)
               positionSellTime = TimeCurrent();
           }
        }
      else
        {
         if(direction < 0)
           {
            if(scenarioA) CallScenarioA(OP_SELL);
            if(scenarioB) CallScenarioB(OP_SELL);
            if(scenarioC && !scenarioCSellActive) CallScenarioC(OP_SELL);
            if(scenarioD) CallScenarioD(OP_SELL);
           }
        }
     }

   //============ BUY branch ============
   if(TimeCurrent() > (positionBuyTime + timeFilter))
     {
      if(scenarioC && scenarioCBuyActive && direction > 0)
         CallScenarioC(OP_BUY);

      if(amountOfOrders(OP_BUY) < startBe)
        {
         if(direction > 0)
           {
            double ask = AskPrice();
            double tp  = ask + tpRange * _Point;
            if(BidPrice() > gSupportBottom && BidPrice() < gSupportTop)
               tp = ask + tpRange * tpMultiplier * _Point;

            ulong tk = OpenMarket(OP_BUY, lotSize, tp, "VEBuy");
            if(tk != 0)
               positionBuyTime = TimeCurrent();
           }
        }
      else
        {
         if(direction > 0)
           {
            if(scenarioA) CallScenarioA(OP_BUY);
            if(scenarioB) CallScenarioB(OP_BUY);
            if(scenarioC && !scenarioCBuyActive) CallScenarioC(OP_BUY);
            if(scenarioD) CallScenarioD(OP_BUY);
           }
        }
     }
  }

//==================================================================
// HOUSEKEEPING — reset Scenario-C state when its base position closes.
// Called from OnTick every tick (cheap: two PositionSelectByTicket calls).
//==================================================================
void CheckScenarioCBasketClosed()
  {
   if(baseScenarioCSellOrder > 0)
     {
      ulong tk = (ulong)baseScenarioCSellOrder;
      if(!PositionSelectByTicket(tk))  // position gone → basket closed
        {
         scenarioCSellActive    = false;
         baseScenarioCSellOrder = 0;
         cAvgCountSell          = 0;
         cBaseSellPrice         = 0.0;
         cBaseSellLot           = 0.0;
         cBaseSellTk            = 0;
         ArrayResize(cAvgsSell, 0);
        }
     }
   if(baseScenarioCBuyOrder > 0)
     {
      ulong tk = (ulong)baseScenarioCBuyOrder;
      if(!PositionSelectByTicket(tk))
        {
         scenarioCBuyActive    = false;
         baseScenarioCBuyOrder = 0;
         cAvgCountBuy          = 0;
         cBaseBuyPrice         = 0.0;
         cBaseBuyLot           = 0.0;
         cBaseBuyTk            = 0;
         ArrayResize(cAvgsBuy, 0);
        }
     }
  }

#endif // TBM_MT5_SCENARIOS_MQH
