//+------------------------------------------------------------------+
//| Persistence.mqh — tick bucket CSV + daily margin log.            |
//|                                                                   |
//| MT5 port notes:                                                   |
//|   * MT4 left `tick_file` uninitialized — silently broken. Here    |
//|     we give it a per-symbol name on init.                         |
//|   * MT4's ReadPositionData restored the local-TP shim which is   |
//|     obsolete in MT5 (positions carry real TPs). It's a no-op.    |
//+------------------------------------------------------------------+
#ifndef TBM_MT5_PERSISTENCE_MQH
#define TBM_MT5_PERSISTENCE_MQH

//--- Initialise the tick-bucket file name. Called from TickBuckets_Init.
void Persistence_Init()
  {
   tick_file = StringFormat("tickbuckets_%s_%d.csv", _Symbol, MagicNumber);
  }

//--- Write current tick_buckets[] as a CSV snapshot (FILE_COMMON so the
//    user can inspect it across MT5 instances). Skipped in tester fast mode.
void SaveTickBucketsToFile()
  {
   if(TesterFastMode()) return;
   if(!PersistTickAcrossTF) return;
   if(tick_file == "") return;

   int fh = FileOpen(tick_file, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
     {
      PrintFormat("SaveTickBuckets error: %d (file=%s)", GetLastError(), tick_file);
      return;
     }

   FileWrite(fh, "PriceBin", "Count", "FirstTime", "LastTime", "LevelCreated", "Day");

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   for(int i = 0; i < tick_bucket_cnt; i++)
     {
      FileWrite(fh,
                DoubleToString(tick_buckets[i].price_bin, _Digits),
                IntegerToString(tick_buckets[i].count),
                TimeToString(tick_buckets[i].first_time, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                TimeToString(tick_buckets[i].last_time,  TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                (tick_buckets[i].level_created ? "1" : "0"),
                IntegerToString(now.day)
               );
     }
   FileClose(fh);
  }

//--- Obsolete in MT5 (positions keep real TPs). Kept as a stub so the
//    MT4 call site `ReadPositionData()` in OnInit still compiles.
void ReadPositionData() { /* no-op: MT5 positions carry real TPs */ }

//--- Append a daily margin sample to daily_margins.csv.
void LogDailyMargins(double ml, double fm)
  {
   if(TesterFastMode()) return;
   int h = FileOpen("daily_margins.csv", FILE_CSV | FILE_READ | FILE_WRITE, ',');
   if(h == INVALID_HANDLE)
     {
      PrintFormat("LogDailyMargins: open failed err=%d", GetLastError());
      return;
     }
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeCurrent(), DoubleToString(ml, 2), DoubleToString(fm, 2));
   FileClose(h);
  }

//--- Remove every chart object for a clean slate at day rollover.
//    MT5 ObjectsDeleteAll requires chart_id (0 = current chart).
void CleanupAllObjects()
  {
   if(TesterFastMode())
     {
      Comment("");
      return;
     }
   ObjectsDeleteAll(0);
   Comment("");
  }

#endif // TBM_MT5_PERSISTENCE_MQH
