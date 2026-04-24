//+------------------------------------------------------------------+
//| Session.mqh — weekday trading windows + daily profit/loss gates. |
//|                                                                   |
//| Populates Start[]/End[] arrays (21 slots = 7 days × 3 windows)   |
//| from the Mon..Sun HHMM inputs, then offers:                       |
//|   * IsTradingTime() — true if today has at least one valid set.  |
//|   * UpdateStartEndFromSets() — picks the current / next / last   |
//|     valid window for "today" and fills startHour / endHour that  |
//|     the rest of the EA uses for gating.                           |
//|                                                                   |
//| MT5 note: MT4's DayOfWeek() / TimeHour() / TimeMinute() are gone |
//| — replaced with TimeToStruct + MqlDateTime field access.         |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_SESSION_MQH
#define TBM_MT5_SESSION_MQH

//--- Populate Start[]/End[] arrays from the Mon..Sun session inputs.
//    Called once from OnInit. Matches MT4 layout: idx = day_of_week * 3 + set_index.
void Session_Init()
  {
   Start[0] = SunSet1Start;  Start[1] = SunSet2Start;  Start[2] = SunSet3Start;
   Start[3] = MonSet1Start;  Start[4] = MonSet2Start;  Start[5] = MonSet3Start;
   Start[6] = TueSet1Start;  Start[7] = TueSet2Start;  Start[8] = TueSet3Start;
   Start[9] = WedSet1Start;  Start[10]= WedSet2Start;  Start[11]= WedSet3Start;
   Start[12]= ThuSet1Start;  Start[13]= ThuSet2Start;  Start[14]= ThuSet3Start;
   Start[15]= FriSet1Start;  Start[16]= FriSet2Start;  Start[17]= FriSet3Start;
   Start[18]= SatSet1Start;  Start[19]= SatSet2Start;  Start[20]= SatSet3Start;

   End[0] = SunSet1End;  End[1] = SunSet2End;  End[2] = SunSet3End;
   End[3] = MonSet1End;  End[4] = MonSet2End;  End[5] = MonSet3End;
   End[6] = TueSet1End;  End[7] = TueSet2End;  End[8] = TueSet3End;
   End[9] = WedSet1End;  End[10]= WedSet2End;  End[11]= WedSet3End;
   End[12]= ThuSet1End;  End[13]= ThuSet2End;  End[14]= ThuSet3End;
   End[15]= FriSet1End;  End[16]= FriSet2End;  End[17]= FriSet3End;
   End[18]= SatSet1End;  End[19]= SatSet2End;  End[20]= SatSet3End;
  }

//--- Is there at least one valid session set defined for today?
//    Also enforces monotonic non-overlapping sets and no overnight windows.
bool IsTradingTime()
  {
   int d = DayOfWeekNow();
   int last = -1;
   bool any = false;

   for(int i = 0; i < 3; i++)
     {
      int idx = d * 3 + i;
      if(Start[idx] == End[idx]) continue;  // disabled

      int s = ToMinutes(Start[idx]);
      int e = ToMinutes(End[idx]);
      if(s < 0 || e < 0) continue;          // garbage HHMM → skip this set
      if(s >= e) return false;              // no overnight
      if(last != -1 && s < last) return false; // sets must be monotonic

      last = e;
      any  = true;
     }
   return any;
  }

//--- Pick today's current / next / last valid window and fill startHour+endHour.
//    Skips if the day was already stopped by dailyProfit / dailyLost triggers.
void UpdateStartEndFromSets()
  {
   if(gTradingStoppedToday) return;

   datetime now = TimeCurrent();
   MqlDateTime t;
   TimeToStruct(now, t);

   int d      = t.day_of_week;
   int curMin = t.hour * 60 + t.min;

   int firstS = -1, firstE = -1;
   int lastS  = -1, lastE  = -1;
   int nextS  = -1, nextE  = -1;
   int curS   = -1, curE   = -1;
   int last   = -1;

   for(int i = 0; i < 3; i++)
     {
      int idx = d * 3 + i;
      if(Start[idx] == End[idx]) continue;

      int s = ToMinutes(Start[idx]);
      int e = ToMinutes(End[idx]);
      if(s < 0 || e < 0) continue;
      if(s >= e) continue;
      if(last != -1 && s < last) continue;

      if(firstS == -1) { firstS = s; firstE = e; }
      lastS = s; lastE = e;

      if(curMin >= s && curMin < e)
        {
         curS = s; curE = e;
         break;
        }

      if(curMin < s && nextS == -1)
        {
         nextS = s; nextE = e;
        }

      last = e;
     }

   int useS = -1, useE = -1;

   if(curS != -1)         { useS = curS;  useE = curE;  }
   else if(nextS != -1)   { useS = nextS; useE = nextE; }
   else if(lastS != -1)   { useS = lastS; useE = lastE; }
   else                   { startHour = 0; endHour = 0; return; }

   int sh = useS / 60, sm = useS % 60;
   int eh = useE / 60, em = useE % 60;

   string datePart = StringFormat("%d.%02d.%02d ", t.year, t.mon, t.day);
   startHour = StringToTime(datePart + StringFormat("%02d:%02d", sh, sm));
   endHour   = StringToTime(datePart + StringFormat("%02d:%02d", eh, em));
  }

#endif // TBM_MT5_SESSION_MQH
