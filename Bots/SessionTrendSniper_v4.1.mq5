//+------------------------------------------------------------------+
//|          Session Trend Sniper EA                                 |
//|          استراتيجية: Multi-TF + Session + ATR Management        |
//|          الإصدار: 4.1 - BE+Trail+DayFilter+PairFilter           |
//+------------------------------------------------------------------+
#property copyright "Session Trend Sniper"
#property version   "4.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== الأزواج ==="
input bool   Use_EURUSD   = true;
input bool   Use_GBPUSD   = true;
input bool   Use_USDJPY   = true;
input bool   Use_NZDUSD   = false;  // مؤقتاً موقوف للاختبار
input bool   Use_USDCAD   = true;
input bool   Use_AUDUSD   = false;  // مؤقتاً موقوف للاختبار
input string SymbolSuffix = "m";

input group "=== إدارة الرصيد ==="
input double RiskPercent     = 1.0;
input double MaxDailyLoss    = 3.0;
input int    MaxOpenTrades   = 1;

input group "=== ATR Settings ==="
input int    ATR_Period      = 14;
input double ATR_SL_Multi    = 1.0;
input double ATR_BE_Multi    = 1.0;   // Breakeven = ATR × 1.0 (أوسع)
input double ATR_TP1_Multi   = 2.5;
input double ATR_TP2_Multi   = 4.0;
input double ATR_Trail_Multi = 1.5;   // Trailing gap = ATR × 1.5 (أوسع)
input double MinTrailPips    = 5.0;
input double ATR_MinFilter   = 0.0003;

input group "=== Spread Filter ==="
input double MaxSpreadMulti  = 2.0;

input group "=== News Filter (GMT) ==="
input bool   UseNewsFilter     = true;
input int    NewsMinutesBefore = 30;
input int    NewsMinutesAfter  = 30;

input group "=== Day Filter ==="
input bool   SkipTuesday = true;   // أوقف التداول يوم الثلاثاء

input group "=== مؤشرات ==="
input int    EMA_Period    = 200;
input int    W1_EMA_Period = 50;
input int    RSI_Period    = 14;
input int    MACD_Fast     = 12;
input int    MACD_Slow     = 26;
input int    MACD_Signal   = 9;
input int    ADX_Period    = 14;
input double ADX_MinLevel  = 25.0;

input group "=== وضع التجربة ==="
input bool   ForceResetDailyLimit = false; // ⚡ true = تجاوز Daily Limit يدوياً

//+------------------------------------------------------------------+
//| بنية معلومات كل زوج                                             |
//+------------------------------------------------------------------+
struct PairInfo {
   string   symbol;
   int      sessionStart;
   int      sessionEnd;
   bool     enabled;
   double   normalSpread;

   // Constructor
   void Init(string sym, int sStart, int sEnd, bool en) {
      symbol       = sym;
      sessionStart = sStart;
      sessionEnd   = sEnd;
      enabled      = en;
      normalSpread = 0;
   }
};

PairInfo pairs[6];

//+------------------------------------------------------------------+
//| متغيرات عامة                                                    |
//+------------------------------------------------------------------+
double   startDayBalance  = 0;
datetime lastDayChecked   = 0;
bool     dailyLimitHit    = false;
int      magicNumber      = 77777;
string   stateFile        = "STS_State.txt";
datetime lastBarTime[6];  // آخر شمعة فُحصت لكل زوج

//+------------------------------------------------------------------+
//| OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(10);

   // إعداد الأزواج مع جلساتها (GMT) + Suffix تلقائي
   pairs[0].Init("EURUSD" + SymbolSuffix, 7,  10, Use_EURUSD);
   pairs[1].Init("GBPUSD" + SymbolSuffix, 7,  10, Use_GBPUSD);
   pairs[2].Init("USDJPY" + SymbolSuffix, 0,  3,  Use_USDJPY);
   pairs[3].Init("NZDUSD" + SymbolSuffix, 22, 1,  Use_NZDUSD);
   pairs[4].Init("USDCAD" + SymbolSuffix, 13, 16, Use_USDCAD);
   pairs[5].Init("AUDUSD" + SymbolSuffix, 22, 1,  Use_AUDUSD);

   // احسب السبريد الطبيعي لكل زوج
   for(int i = 0; i < 6; i++) {
      if(pairs[i].enabled)
         pairs[i].normalSpread = GetCurrentSpread(pairs[i].symbol);
   }

   // استرجع الحالة المحفوظة أو ابدأ جديد
   LoadState();

   // تهيئة lastBarTime
   ArrayInitialize(lastBarTime, 0);

   Print("✅ Session Trend Sniper v4.0 Started | Balance: ", startDayBalance,
         " | DailyLimitHit: ", dailyLimitHit);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                          |
//+------------------------------------------------------------------+
void OnTick() {
   // فحص وتحديث الخسارة اليومية
   CheckDailyLoss();
   if(dailyLimitHit) return;

   // إدارة الصفقات المفتوحة (Breakeven + Trailing) - كل تيك
   ManageOpenTrades();

   // فحص وقت الأخبار
   if(UseNewsFilter && IsNewsTime()) return;

   // فلتر يوم الثلاثاء
   if(SkipTuesday) {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(), t);
      if(t.day_of_week == 2) return; // 2 = الثلاثاء
   }

   // عدد الصفقات المفتوحة
   if(CountOpenTrades() >= MaxOpenTrades) return;

   // فحص كل زوج - فقط عند شمعة H1 جديدة
   for(int i = 0; i < 6; i++) {
      if(!pairs[i].enabled) continue;
      if(!IsSessionTime(pairs[i])) continue;
      if(!SpreadOK(pairs[i])) continue;
      if(HasOpenPosition(pairs[i].symbol)) continue;

      // === OnBar: فحص الإشارة مرة واحدة لكل شمعة H1 ===
      datetime currentBar = iTime(pairs[i].symbol, PERIOD_H1, 0);
      if(currentBar == lastBarTime[i]) continue; // نفس الشمعة → تجاهل
      lastBarTime[i] = currentBar;

      int signal = GetSignal(pairs[i].symbol);
      if(signal == 0) continue;

      if(!CorrelationOK(pairs[i].symbol, signal)) continue;

      OpenTrade(pairs[i].symbol, signal);
   }
}

//+------------------------------------------------------------------+
//| GetSignal - 6 شروط الدخول                                      |
//+------------------------------------------------------------------+
int GetSignal(string symbol) {

   // === فلتر 0: ATR Minimum - سوق متحرك فقط ===
   double atr = GetATR(symbol);
   if(atr < ATR_MinFilter) return 0;

   // === فلتر 1: W1 - EMA 50 (الاتجاه الأسبوعي) ===
   double w1ema[];
   int w1Handle = iMA(symbol, PERIOD_W1, W1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(w1Handle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(w1ema, true);
   CopyBuffer(w1Handle, 0, 0, 3, w1ema);
   IndicatorRelease(w1Handle);
   double lastW1Close = iClose(symbol, PERIOD_W1, 1);
   bool bullW1 = lastW1Close > w1ema[0];
   bool bearW1 = lastW1Close < w1ema[0];

   // === فلتر 2: H4 - EMA 200 (الاتجاه الرئيسي) ===
   double ema200[];
   int emaHandle = iMA(symbol, PERIOD_H4, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(ema200, true);
   CopyBuffer(emaHandle, 0, 0, 3, ema200);
   IndicatorRelease(emaHandle);
   double lastH4Close = iClose(symbol, PERIOD_H4, 1);
   bool bullH4 = lastH4Close > ema200[0];
   bool bearH4 = lastH4Close < ema200[0];

   // W1 و H4 لازم يتفقان
   if(bullW1 != bullH4) return 0;
   if(bearW1 != bearH4) return 0;

   // === فلتر 3: H1 - ADX (قوة الترند) ===
   double adxVal[];
   int adxHandle = iADX(symbol, PERIOD_H1, ADX_Period);
   if(adxHandle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(adxVal, true);
   CopyBuffer(adxHandle, 0, 0, 3, adxVal);
   IndicatorRelease(adxHandle);
   if(adxVal[0] < ADX_MinLevel) return 0; // ترند ضعيف → لا تدخل

   // === فلتر 4: H1 - MACD ===
   double macdMain[], macdSig[];
   int macdHandle = iMACD(symbol, PERIOD_H1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   if(macdHandle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSig, true);
   CopyBuffer(macdHandle, 0, 0, 3, macdMain);
   CopyBuffer(macdHandle, 1, 0, 3, macdSig);
   IndicatorRelease(macdHandle);
   bool bullH1 = macdMain[0] > macdSig[0];
   bool bearH1 = macdMain[0] < macdSig[0];

   // === فلتر 5: M15 - RSI بين 40-60 ===
   double rsiVal[];
   int rsiHandle = iRSI(symbol, PERIOD_M15, RSI_Period, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(rsiVal, true);
   CopyBuffer(rsiHandle, 0, 0, 3, rsiVal);
   IndicatorRelease(rsiHandle);
   bool rsiOK = (rsiVal[0] >= 40.0 && rsiVal[0] <= 60.0);

   // === فلتر 6: M5 - Engulfing أو Pin Bar ===
   bool bullM5 = IsBullishCandle(symbol);
   bool bearM5 = IsBearishCandle(symbol);

   // === تجميع الشروط ===
   if(bullW1 && bullH4 && bullH1 && rsiOK && bullM5) return 1;  // BUY
   if(bearW1 && bearH4 && bearH1 && rsiOK && bearM5) return -1; // SELL

   return 0;
}

//+------------------------------------------------------------------+
//| فحص الشمعة على M5                                               |
//+------------------------------------------------------------------+
bool IsBullishCandle(string symbol) {
   double open1  = iOpen(symbol, PERIOD_M5, 1);
   double close1 = iClose(symbol, PERIOD_M5, 1);
   double open2  = iOpen(symbol, PERIOD_M5, 2);
   double close2 = iClose(symbol, PERIOD_M5, 2);
   double high1  = iHigh(symbol, PERIOD_M5, 1);
   double low1   = iLow(symbol, PERIOD_M5, 1);

   // Bullish Engulfing
   bool engulfing = (close2 < open2) && (close1 > open1) && (close1 > open2) && (open1 < close2);

   // Pin Bar صاعد
   double body   = MathAbs(close1 - open1);
   double tail   = open1 - low1;
   bool pinBar   = (tail >= body * 2) && (close1 > open1);

   return (engulfing || pinBar);
}

bool IsBearishCandle(string symbol) {
   double open1  = iOpen(symbol, PERIOD_M5, 1);
   double close1 = iClose(symbol, PERIOD_M5, 1);
   double open2  = iOpen(symbol, PERIOD_M5, 2);
   double close2 = iClose(symbol, PERIOD_M5, 2);
   double high1  = iHigh(symbol, PERIOD_M5, 1);
   double low1   = iLow(symbol, PERIOD_M5, 1);

   // Bearish Engulfing
   bool engulfing = (close2 > open2) && (close1 < open1) && (close1 < open2) && (open1 > close2);

   // Pin Bar هابط
   double body   = MathAbs(close1 - open1);
   double wick   = high1 - open1;
   bool pinBar   = (wick >= body * 2) && (close1 < open1);

   return (engulfing || pinBar);
}

//+------------------------------------------------------------------+
//| حساب اللوت الديناميكي بناءً على % المخاطرة                     |
//+------------------------------------------------------------------+
double CalculateLot(string symbol, double slPoints) {
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100.0);

   double tickValue  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tickValue <= 0 || tickSize <= 0 || slPoints <= 0) return 0.01;

   double pipValue = (tickValue / tickSize) * point;
   double lot      = riskAmount / (slPoints * pipValue);

   // تقريب للـ lot step
   double lotStep  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   Print("💰 Lot Calculated | ", symbol,
         " | Risk: $", DoubleToString(riskAmount, 2),
         " | SL pts: ", slPoints,
         " | Lot: ", lot);
   return lot;
}

//+------------------------------------------------------------------+
//| فتح الصفقة مع SL + TP1 + TP2 + Dynamic Lot                    |
//+------------------------------------------------------------------+
void OpenTrade(string symbol, int direction) {
   double atr = GetATR(symbol);
   if(atr <= 0) return;

   double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double ask     = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(symbol, SYMBOL_BID);
   int    digits  = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double slPoints = atr * ATR_SL_Multi / point;
   double lot      = CalculateLot(symbol, slPoints);
   double halfLot  = MathMax(SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                             MathFloor((lot / 2) / SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP))
                             * SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));

   if(direction == 1) { // BUY
      double entry = ask;
      double sl    = NormalizeDouble(entry - atr * ATR_SL_Multi, digits);
      double tp1   = NormalizeDouble(entry + atr * ATR_TP1_Multi, digits);
      double tp2   = NormalizeDouble(entry + atr * ATR_TP2_Multi, digits);

      trade.Buy(halfLot, symbol, entry, sl, tp1, "STS_BUY_TP1");
      trade.Buy(halfLot, symbol, entry, sl, tp2, "STS_BUY_TP2");

   } else { // SELL
      double entry = bid;
      double sl    = NormalizeDouble(entry + atr * ATR_SL_Multi, digits);
      double tp1   = NormalizeDouble(entry - atr * ATR_TP1_Multi, digits);
      double tp2   = NormalizeDouble(entry - atr * ATR_TP2_Multi, digits);

      trade.Sell(halfLot, symbol, entry, sl, tp1, "STS_SELL_TP1");
      trade.Sell(halfLot, symbol, entry, sl, tp2, "STS_SELL_TP2");
   }

   Print("📈 Trade Opened | ", symbol,
         " | Dir: ", direction == 1 ? "BUY" : "SELL",
         " | Lot: ", halfLot, "×2",
         " | ATR: ", atr);
}

//+------------------------------------------------------------------+
//| إدارة الصفقات المفتوحة: Breakeven + Trailing                   |
//+------------------------------------------------------------------+
void ManageOpenTrades() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != magicNumber) continue;

      string symbol    = posInfo.Symbol();
      double atr       = GetATR(symbol);
      double entry     = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();
      double currentTP = posInfo.TakeProfit();
      int    digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      long   posType   = posInfo.PositionType();

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double price = (posType == POSITION_TYPE_BUY) ? bid : ask;

      double beTrigger  = (posType == POSITION_TYPE_BUY)
                          ? entry + atr * ATR_BE_Multi
                          : entry - atr * ATR_BE_Multi;

      // === المرحلة 1: Breakeven ===
      if(posType == POSITION_TYPE_BUY && price >= beTrigger && currentSL < entry) {
         double newSL = NormalizeDouble(entry, digits);
         trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         Print("✅ Breakeven | ", symbol, " #", posInfo.Ticket());
         continue;
      }
      if(posType == POSITION_TYPE_SELL && price <= beTrigger && currentSL > entry) {
         double newSL = NormalizeDouble(entry, digits);
         trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         Print("✅ Breakeven | ", symbol, " #", posInfo.Ticket());
         continue;
      }

      // === المرحلة 2: Trailing Stop (بعد Breakeven) ===
      double minMove = MinTrailPips * SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;

      if(posType == POSITION_TYPE_BUY && currentSL >= entry) {
         double trailSL = NormalizeDouble(price - atr * ATR_Trail_Multi, digits);
         if(trailSL > currentSL + minMove) {
            trade.PositionModify(posInfo.Ticket(), trailSL, currentTP);
         }
      }
      if(posType == POSITION_TYPE_SELL && currentSL <= entry && entry > 0) {
         double trailSL = NormalizeDouble(price + atr * ATR_Trail_Multi, digits);
         if(trailSL < currentSL - minMove || currentSL == 0) {
            trade.PositionModify(posInfo.Ticket(), trailSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Daily Loss Check                                                 |
//+------------------------------------------------------------------+
void CheckDailyLoss() {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   // يوم جديد → جدد الرصيد
   MqlDateTime last;
   TimeToStruct(lastDayChecked, last);
   if(now.day != last.day) {
      startDayBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked   = TimeCurrent();
      dailyLimitHit    = false;
      SaveState();
      Print("📅 New Day | Start Balance: ", startDayBalance);
   }

   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPercent = (startDayBalance - equity) / startDayBalance * 100.0;

   if(lossPercent >= MaxDailyLoss && !dailyLimitHit) {
      dailyLimitHit = true;
      CloseAllTrades();
      SaveState();
      Print("🛑 Daily Loss Limit ", MaxDailyLoss, "% Hit! Bot paused for today.");
   }
}

//+------------------------------------------------------------------+
//| حفظ الحالة في ملف                                               |
//+------------------------------------------------------------------+
void SaveState() {
   int handle = FileOpen(stateFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle == INVALID_HANDLE) {
      Print("⚠️ Cannot save state file");
      return;
   }
   FileWrite(handle, DoubleToString(startDayBalance, 2));
   FileWrite(handle, TimeToString(TimeCurrent()));
   FileWrite(handle, dailyLimitHit ? "1" : "0");
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| استرجاع الحالة عند إعادة التشغيل                                |
//+------------------------------------------------------------------+
void LoadState() {

   // === ForceReset: تجاوز يدوي لـ Daily Limit ===
   if(ForceResetDailyLimit) {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      dailyLimitHit   = false;
      SaveState();
      Print("⚡ Force Reset Applied | Daily Limit Cleared | New Balance: ", startDayBalance);
      return;
   }

   // === لا يوجد ملف محفوظ → ابدأ جديد ===
   if(!FileIsExist(stateFile, FILE_COMMON)) {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      dailyLimitHit   = false;
      SaveState();
      Print("📋 No State File | Fresh Start | Balance: ", startDayBalance);
      return;
   }

   // === قرأ الملف المحفوظ ===
   int handle = FileOpen(stateFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(handle == INVALID_HANDLE) {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      return;
   }

   double   savedBalance = StringToDouble(FileReadString(handle));
   datetime savedTime    = StringToTime(FileReadString(handle));
   bool     savedLimit   = FileReadString(handle) == "1";
   FileClose(handle);

   // === قارن اليوم المحفوظ مع اليوم الحالي ===
   MqlDateTime now, saved;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(savedTime, saved);

   if(now.day == saved.day && now.mon == saved.mon && now.year == saved.year) {
      // نفس اليوم → استرجع الحالة كاملة
      startDayBalance = savedBalance;
      lastDayChecked  = savedTime;
      dailyLimitHit   = savedLimit;

      if(dailyLimitHit)
         Print("⛔ State Restored | Daily Limit was HIT today | Bot paused",
               " | To override: set ForceResetDailyLimit = true");
      else
         Print("♻️ State Restored | Balance: ", startDayBalance,
               " | Resuming normally...");
   } else {
      // يوم جديد → ابدأ من جديد
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      dailyLimitHit   = false;
      SaveState();
      Print("📅 New Day on Restart | Fresh Start | Balance: ", startDayBalance);
   }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool CorrelationOK(string symbol, int direction) {

   // EURUSD و GBPUSD إيجابيان 85% → لا تفتح كليهم بنفس الاتجاه
   if(symbol == "EURUSD" || symbol == "GBPUSD") {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Magic() != magicNumber) continue;
         string sym = posInfo.Symbol();
         int existDir = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
         if((sym == "EURUSD" || sym == "GBPUSD") && sym != symbol && existDir == direction) {
            Print("⚠️ Correlation Block: Double EUR/GBP exposure");
            return false;
         }
      }
   }

   // AUDUSD و NZDUSD إيجابيان 75% → لا تفتح كليهم بنفس الاتجاه
   if(symbol == "AUDUSD" || symbol == "NZDUSD") {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Magic() != magicNumber) continue;
         string sym = posInfo.Symbol();
         int existDir = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
         if((sym == "AUDUSD" || sym == "NZDUSD") && sym != symbol && existDir == direction) {
            Print("⚠️ Correlation Block: Double AUD/NZD exposure");
            return false;
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Session Time Check                                               |
//+------------------------------------------------------------------+
bool IsSessionTime(PairInfo &pair) {
   MqlDateTime gmt;
   TimeToStruct(TimeGMT(), gmt);
   int hour = gmt.hour;

   // AUDUSD جلسة تمتد من 22 لـ 01 (تعبر منتصف الليل)
   if(pair.sessionStart > pair.sessionEnd) {
      return (hour >= pair.sessionStart || hour < pair.sessionEnd);
   }
   return (hour >= pair.sessionStart && hour < pair.sessionEnd);
}

//+------------------------------------------------------------------+
//| News Filter - أوقات الأخبار الكبيرة (GMT)                       |
//+------------------------------------------------------------------+
bool IsNewsTime() {
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);

   // أوقات أخبار ثابتة عالية الخطورة (GMT)
   // {hour, minute, dayOfWeek}
   int newsHour[]      = {13, 19, 13};
   int newsMinute[]    = {30,  0, 30};
   int newsDayOfWeek[] = { 5,  3,  3};
   // الجمعة 13:30 (NFP) | الأربعاء 19:00 (Fed) | الأربعاء 13:30 (CPI)

   int total = ArraySize(newsHour);
   for(int i = 0; i < total; i++) {
      if(t.day_of_week != newsDayOfWeek[i]) continue;
      int currentMins = t.hour * 60 + t.min;
      int newsMins    = newsHour[i] * 60 + newsMinute[i];
      if(MathAbs(currentMins - newsMins) <= NewsMinutesBefore) {
         Print("📰 News Filter Active");
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double GetATR(string symbol) {
   double atr[];
   int handle = iATR(symbol, PERIOD_M15, ATR_Period);
   if(handle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(atr, true);
   CopyBuffer(handle, 0, 0, 3, atr);
   IndicatorRelease(handle);
   return atr[0];
}

double GetCurrentSpread(string symbol) {
   return (double)(SymbolInfoInteger(symbol, SYMBOL_SPREAD));
}

bool SpreadOK(PairInfo &pair) {
   double current = GetCurrentSpread(pair.symbol);
   if(pair.normalSpread <= 0) {
      pair.normalSpread = current;
      return true;
   }
   return current <= pair.normalSpread * MaxSpreadMulti;
}

bool HasOpenPosition(string symbol) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == symbol && posInfo.Magic() == magicNumber)
         return true;
   }
   return false;
}

int CountOpenTrades() {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() == magicNumber) count++;
   }
   return count;
}

void CloseAllTrades() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() == magicNumber)
         trade.PositionClose(posInfo.Ticket());
   }
}
//+------------------------------------------------------------------+
