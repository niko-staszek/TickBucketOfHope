//+------------------------------------------------------------------+
//| Dashboard.mqh — on-chart Positions / Live Metrics / Controls.    |
//|                                                                   |
//| Direct port of the MT4 MoneyDancer-inspired dashboard. Object    |
//| API is identical between MT4 and MT5 other than ObjectsDeleteAll |
//| requiring chart_id (handled in Persistence.mqh).                  |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_DASHBOARD_MQH
#define TBM_MT5_DASHBOARD_MQH

//==================================================================
// MAX DRAWDOWN TRACKING
//==================================================================
void UpdateMaxDD()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int    dayKey = DayKey(TimeCurrent());

   if(dayKey != g_ddDayKey)
     {
      g_ddDayKey        = dayKey;
      g_peakEquityToday = equity;
      g_maxDDToday      = 0.0;
     }

   if(equity > g_peakEquityToday) g_peakEquityToday = equity;
   if(equity > g_peakEquityEver)  g_peakEquityEver  = equity;

   if(g_peakEquityToday > 0)
     {
      double dd = (g_peakEquityToday - equity) / g_peakEquityToday * 100.0;
      if(dd > g_maxDDToday) g_maxDDToday = dd;
     }
   if(g_peakEquityEver > 0)
     {
      double dd = (g_peakEquityEver - equity) / g_peakEquityEver * 100.0;
      if(dd > g_maxDDEver) g_maxDDEver = dd;
     }
  }

//==================================================================
// OBJECT NAMING + DRAWING PRIMITIVES
//==================================================================
string ObjName(string suffix)
  {
   return "TBM_" + IntegerToString(MagicNumber) + "_" + suffix;
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

//==================================================================
// MAIN DRAW: POSITIONS + LIVE METRICS + CONTROLS
//==================================================================
void DrawDashboard()
  {
   if(!ShowDashboard || TesterFastMode()) return;

   // Theme (MoneyDancer palette)
   color bgPanel     = (color)C'24,28,36';
   color borderMain  = (color)C'45,52,65';
   color textBright  = (color)C'220,225,230';
   color textMuted   = (color)C'130,140,155';
   color accentBlue  = (color)C'70,130,200';
   color profitGreen = (color)C'50,205,100';
   color lossRed     = (color)C'220,70,70';

   int x = DashX;
   int y = DashY;
   int w = 410;

   //============ POSITIONS PANEL ============
   DrawPanel(ObjName("D_StatsPanel"), x, y, w, 105, bgPanel, borderMain);
   DrawLabel(ObjName("D_StatsTitle"), x + 12, y + 6, ">> POSITIONS", accentBlue, 8, "Arial Bold");

   int btnW = 60, btnH = 16;
   int btnX = x + w - 195;
   color btnT  = (g_statsViewMode == 0 ? accentBlue : (color)C'40,45,55');
   color btnWc = (g_statsViewMode == 1 ? accentBlue : (color)C'40,45,55');
   color btnM  = (g_statsViewMode == 2 ? accentBlue : (color)C'40,45,55');
   CreateButton(ObjName("D_BtnToday"), btnX,                y + 5, btnW, btnH, "TODAY", textBright, btnT);
   CreateButton(ObjName("D_BtnWeek"),  btnX + btnW + 3,     y + 5, btnW, btnH, "WEEK",  textBright, btnWc);
   CreateButton(ObjName("D_BtnMonth"), btnX + 2*(btnW + 3), y + 5, btnW, btnH, "MONTH", textBright, btnM);

   int cB, cS; double pB, pS;
   if(g_statsViewMode == 0)      { cB = g_closedBuyToday; cS = g_closedSellToday; pB = g_profitBuyToday; pS = g_profitSellToday; }
   else if(g_statsViewMode == 1) { cB = g_closedBuyWeek;  cS = g_closedSellWeek;  pB = g_profitBuyWeek;  pS = g_profitSellWeek;  }
   else                          { cB = g_closedBuyMonth; cS = g_closedSellMonth; pB = g_profitBuyMonth; pS = g_profitSellMonth; }

   // BUY row (closed)
   DrawLabel(ObjName("D_BL"), x + 15, y + 30, "BUY:",              textMuted,  8, "Arial");
   DrawLabel(ObjName("D_BC"), x + 60, y + 30, IntegerToString(cB), textBright, 9, "Consolas");
   color pBClr = (pB >= 0 ? profitGreen : lossRed);
   DrawLabel(ObjName("D_BP"), x + 100, y + 30, (pB >= 0 ? "+" : "") + DoubleToString(pB, 2), pBClr, 9, "Consolas");

   // SELL row (closed)
   DrawLabel(ObjName("D_SL"), x + 15, y + 48, "SELL:",             textMuted,  8, "Arial");
   DrawLabel(ObjName("D_SC"), x + 60, y + 48, IntegerToString(cS), textBright, 9, "Consolas");
   color pSClr = (pS >= 0 ? profitGreen : lossRed);
   DrawLabel(ObjName("D_SP"), x + 100, y + 48, (pS >= 0 ? "+" : "") + DoubleToString(pS, 2), pSClr, 9, "Consolas");

   // TOTAL row
   double totP = pB + pS;
   int    totC = cB + cS;
   DrawLabel(ObjName("D_TL"), x + 15, y + 70, "TOTAL:",              textMuted,  9, "Arial Bold");
   DrawLabel(ObjName("D_TC"), x + 60, y + 70, IntegerToString(totC), textBright, 9, "Consolas");
   color totClr = (totP >= 0 ? profitGreen : lossRed);
   DrawLabel(ObjName("D_TP"), x + 100, y + 70, (totP >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(totP), 2), totClr, 11, "Arial Bold");

   // Open positions (right column)
   int    oB = amountOfOrders(OP_BUY);
   int    oS = amountOfOrders(OP_SELL);
   double fB = BasketFloatingPL(OP_BUY);
   double fS = BasketFloatingPL(OP_SELL);
   double fT = fB + fS;

   DrawLabel(ObjName("D_OL"), x + w/2 + 15, y + 30, "OPEN:",                    textMuted,  8, "Arial");
   DrawLabel(ObjName("D_OB"), x + w/2 + 60, y + 30, IntegerToString(oB) + " B", accentBlue, 9, "Consolas");
   DrawLabel(ObjName("D_OS"), x + w/2 + 100,y + 30, IntegerToString(oS) + " S", lossRed,    9, "Consolas");

   DrawLabel(ObjName("D_FL"), x + w/2 + 15, y + 48, "FLOAT:", textMuted, 8, "Arial");
   color fClr = (fT >= 0 ? profitGreen : lossRed);
   DrawLabel(ObjName("D_FV"), x + w/2 + 60, y + 48, (fT >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(fT), 2), fClr, 10, "Consolas");

   y += 110;

   //============ LIVE METRICS PANEL ============
   // Margin snapshot (from MT4 logic — only refresh when free-margin drops)
   if(PositionsTotal() > 0 && AccountInfoDouble(ACCOUNT_MARGIN_FREE) < freeMargin)
     {
      margine    = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2);
      freeMargin = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE),  2);
     }

   DrawPanel(ObjName("D_MetricsPanel"), x, y, w, 70, bgPanel, borderMain);
   DrawLabel(ObjName("D_MetricsTitle"), x + 12, y + 6, ">> LIVE METRICS", accentBlue, 8, "Arial Bold");

   DrawLabel(ObjName("D_L4"), x + 15,  y + 25, "MAX DD TODAY:", textMuted, 8, "Arial");
   color ddTClr = (g_maxDDToday > 10.0 ? lossRed : textBright);
   DrawLabel(ObjName("D_V4"), x + 115, y + 25, DoubleToString(g_maxDDToday, 2) + "%", ddTClr, 9, "Consolas");

   DrawLabel(ObjName("D_L5"), x + 15,  y + 45, "MAX DD EVER:", textMuted, 8, "Arial");
   color ddEClr = (g_maxDDEver > 20.0 ? lossRed : textBright);
   DrawLabel(ObjName("D_V5"), x + 115, y + 45, DoubleToString(g_maxDDEver, 2) + "%", ddEClr, 9, "Consolas");

   DrawLabel(ObjName("D_ML"), x + w/2 + 15, y + 25, "MARGIN %:", textMuted,  8, "Arial");
   DrawLabel(ObjName("D_MV"), x + w/2 + 90, y + 25, DoubleToString(margine, 2), textBright, 9, "Consolas");

   y += 75;

   //============ CONTROLS PANEL ============
   DrawPanel(ObjName("D_CtrlPanel"), x, y, w, 80, bgPanel, borderMain);
   DrawLabel(ObjName("D_CtrlTitle"), x + 12, y + 6, ">> CONTROLS", accentBlue, 8, "Arial Bold");

   int cBtnW = 95, cBtnH = 20;
   int cY1 = y + 26, cY2 = y + 52;

   CreateButton(ObjName("D_BtnProfitSell"),   x + 8,   cY1, cBtnW, cBtnH, "+ PROFIT SELL", textBright, (color)C'70,45,45');
   CreateButton(ObjName("D_BtnProfitBuy"),    x + 108, cY1, cBtnW, cBtnH, "+ PROFIT BUY",  textBright, (color)C'45,70,45');
   CreateButton(ObjName("D_BtnCloseAllSell"), x + 208, cY1, cBtnW, cBtnH, "X ALL SELL",    textBright, (color)C'100,45,45');
   CreateButton(ObjName("D_BtnCloseAllBuy"),  x + 308, cY1, cBtnW, cBtnH, "X ALL BUY",     textBright, (color)C'45,80,45');

   CreateButton(ObjName("D_BtnCloseAll"), x + 8, cY2, 195, cBtnH, "!! CLOSE ALL !!", textBright, (color)C'130,50,50');
   string stopTxt = (g_eaStopped ? "> START EA" : "[] STOP EA");
   color  stopBg  = (g_eaStopped ? (color)C'45,90,45' : (color)C'90,45,45');
   CreateButton(ObjName("D_BtnStopEA"), x + 208, cY2, 195, cBtnH, stopTxt, textBright, stopBg);
  }

//==================================================================
// BUTTON-CLICK ROUTER (called from OnTick and OnChartEvent)
//==================================================================
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

#endif // TBM_MT5_DASHBOARD_MQH
