//+------------------------------------------------------------------+
//|          London Breaker EA                                       |
//|          استراتيجية: Donchian + London Breakout + Market Structure|
//|          الإصدار: 1.0                                           |
//+------------------------------------------------------------------+
#property copyright "London Breaker EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== الأزواج ==="
input bool   Use_EURUSD  = true;
input bool   Use_GBPUSD  = true;
input bool   Use_GBPJPY  = true;
input bool   Use_USDCAD  = true;
input string SymbolSuffix = "m"; // Exness mini → "m" | Standard → ""

input group "=== إدارة الرصيد ==="
input double RiskPercent   = 1.0;  // نسبة المخاطرة % لكل صفقة
input double MaxDailyLoss  = 3.0;  // أقصى خسارة يومية %
input int    MaxOpenTrades = 1;    // أقصى صفقات مفتوحة

input group "=== London Breakout (GMT) ==="
input int    AsianStartHour = 2;   // بداية جلسة Asian (GMT)
input int    AsianEndHour   = 7;   // نهاية جلسة Asian / بداية London
input int    LondonEndHour  = 10;  // نهاية نافذة الدخول

input group "=== Donchian Channel ==="
input int    DonchianPeriod = 20;  // فترة Donchian على H4

input group "=== Market Structure ==="
input int    StructurePeriod = 10; // عدد الشمعات لتحديد HH/LL على H1

input group "=== ATR & SL/TP ==="
input int    ATR_Period      = 14;
input double ATR_SL_Multi    = 1.5;  // SL = ATR × 1.5
input double ATR_BE_Multi    = 1.0;  // Breakeven عند ATR × 1.0
input double ATR_TP1_Multi   = 2.0;  // TP1 = ATR × 2.0
input double ATR_TP2_Multi   = 3.5;  // TP2 = ATR × 3.5
input double ATR_Trail_Multi = 1.0;  // Trailing gap
input double MinTrailPips    = 5.0;

input group "=== فلاتر ==="
input double ADX_MinLevel    = 25.0; // قوة الترند
input int    ADX_Period      = 14;
input double MinRangeSize    = 0.0005; // الحد الأدنى لحجم Asian Range

input group "=== وضع التجربة ==="
input bool   SkipTuesday         = true;
input bool   ForceResetDailyLimit = false;

//+------------------------------------------------------------------+
//| بنية الزوج                                                       |
//+------------------------------------------------------------------+
struct PairInfo {
   string symbol;
   bool   enabled;
   double normalSpread;
   double asianHigh;   // أعلى نقطة في Asian Session
   double asianLow;    // أدنى نقطة في Asian Session
   bool   rangeSet;    // هل تم تحديد الـ Range؟
   datetime lastBar;

   void Init(string sym, bool en) {
      symbol      = sym;
      enabled     = en;
      normalSpread = 0;
      asianHigh   = 0;
      asianLow    = 0;
      rangeSet    = false;
      lastBar     = 0;
   }
};

PairInfo pairs[4];

//+------------------------------------------------------------------+
//| متغيرات عامة                                                    |
//+------------------------------------------------------------------+
double   startDayBalance = 0;
datetime lastDayChecked  = 0;
bool     dailyLimitHit   = false;
int      magicNumber     = 88888;
string   stateFile       = "LB_State.txt";

//+------------------------------------------------------------------+
//| OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(10);

   pairs[0].Init("EURUSD" + SymbolSuffix, Use_EURUSD);
   pairs[1].Init("GBPUSD" + SymbolSuffix, Use_GBPUSD);
   pairs[2].Init("GBPJPY" + SymbolSuffix, Use_GBPJPY);
   pairs[3].Init("USDCAD" + SymbolSuffix, Use_USDCAD);

   for(int i = 0; i < 4; i++) {
      if(pairs[i].enabled)
         pairs[i].normalSpread = GetCurrentSpread(pairs[i].symbol);
   }

   LoadState();
   Print("✅ London Breaker v1.0 Started | Balance: ", startDayBalance);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                          |
//+------------------------------------------------------------------+
void OnTick() {
   CheckDailyLoss();
   if(dailyLimitHit) return;

   ManageOpenTrades();

   // فلتر يوم الثلاثاء
   if(SkipTuesday) {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(), t);
      if(t.day_of_week == 2) return;
   }

   if(CountOpenTrades() >= MaxOpenTrades) return;

   MqlDateTime gmt;
   TimeToStruct(TimeGMT(), gmt);
   int hour = gmt.hour;

   for(int i = 0; i < 4; i++) {
      if(!pairs[i].enabled) continue;
      if(HasOpenPosition(pairs[i].symbol)) continue;
      if(!SpreadOK(pairs[i])) continue;

      // === مرحلة 1: تسجيل Asian Range (2-7 GMT) ===
      if(hour >= AsianStartHour && hour < AsianEndHour) {
         UpdateAsianRange(pairs[i]);
         continue;
      }

      // === مرحلة 2: London Breakout (7-10 GMT) ===
      if(hour >= AsianEndHour && hour < LondonEndHour) {
         if(!pairs[i].rangeSet) continue;

         // فحص عند شمعة H1 جديدة فقط
         datetime currentBar = iTime(pairs[i].symbol, PERIOD_H1, 0);
         if(currentBar == pairs[i].lastBar) continue;
         pairs[i].lastBar = currentBar;

         int signal = GetBreakoutSignal(pairs[i]);
         if(signal == 0) continue;

         OpenTrade(pairs[i].symbol, signal);
      }

      // === إعادة تعيين الـ Range في نهاية اليوم ===
      if(hour == 1) {
         pairs[i].rangeSet = false;
         pairs[i].asianHigh = 0;
         pairs[i].asianLow  = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| تسجيل Asian Range                                               |
//+------------------------------------------------------------------+
void UpdateAsianRange(PairInfo &pair) {
   double high = iHigh(pair.symbol, PERIOD_H1, 0);
   double low  = iLow(pair.symbol,  PERIOD_H1, 0);

   if(pair.asianHigh == 0 || high > pair.asianHigh) pair.asianHigh = high;
   if(pair.asianLow  == 0 || low  < pair.asianLow)  pair.asianLow  = low;
   pair.rangeSet = true;
}

//+------------------------------------------------------------------+
//| GetBreakoutSignal - الشروط الثلاثة مدمجة                       |
//+------------------------------------------------------------------+
int GetBreakoutSignal(PairInfo &pair) {
   string symbol = pair.symbol;
   double ask    = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(symbol, SYMBOL_BID);

   // تأكد من حجم الـ Range كافي
   double rangeSize = pair.asianHigh - pair.asianLow;
   if(rangeSize < MinRangeSize) return 0;

   // === الشرط 1: Donchian H4 - الاتجاه الرئيسي ===
   double donchHigh = 0, donchLow = 999999;
   for(int i = 1; i <= DonchianPeriod; i++) {
      double h = iHigh(symbol, PERIOD_H4, i);
      double l = iLow(symbol,  PERIOD_H4, i);
      if(h > donchHigh) donchHigh = h;
      if(l < donchLow)  donchLow  = l;
   }
   double donchMid  = (donchHigh + donchLow) / 2.0;
   double lastH4    = iClose(symbol, PERIOD_H4, 1);
   bool   donchBull = lastH4 > donchMid;  // فوق المنتصف = صاعد
   bool   donchBear = lastH4 < donchMid;  // تحت المنتصف = هابط

   // === الشرط 2: ADX - قوة الترند ===
   double adxVal[];
   int adxHandle = iADX(symbol, PERIOD_H1, ADX_Period);
   if(adxHandle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(adxVal, true);
   CopyBuffer(adxHandle, 0, 0, 3, adxVal);
   IndicatorRelease(adxHandle);
   if(adxVal[0] < ADX_MinLevel) return 0;

   // === الشرط 3: London Breakout - كسر الـ Range ===
   bool breakoutBuy  = ask > pair.asianHigh; // كسر الأعلى → BUY
   bool breakoutSell = bid < pair.asianLow;  // كسر الأدنى → SELL

   // === الشرط 4: Market Structure - HH أو LL على H1 ===
   bool hhConfirm = IsHigherHigh(symbol);  // BUY تأكيد
   bool llConfirm = IsLowerLow(symbol);    // SELL تأكيد

   // === الشرط 5: Donchian Breakout تأكيد إضافي ===
   // السعر يكسر الـ Donchian High/Low = إشارة قوية
   bool donchBreakBuy  = ask > donchHigh;
   bool donchBreakSell = bid < donchLow;

   // === تجميع الشروط ===
   // BUY: Donchian صاعد + London كسر الأعلى + HH + ADX قوي
   if(donchBull && breakoutBuy && hhConfirm) {
      Print("🚀 BUY Signal | ", symbol,
            " | Range: ", pair.asianLow, "-", pair.asianHigh,
            " | Donch Mid: ", donchMid,
            " | ADX: ", adxVal[0]);
      return 1;
   }

   // SELL: Donchian هابط + London كسر الأدنى + LL + ADX قوي
   if(donchBear && breakoutSell && llConfirm) {
      Print("🔻 SELL Signal | ", symbol,
            " | Range: ", pair.asianLow, "-", pair.asianHigh,
            " | Donch Mid: ", donchMid,
            " | ADX: ", adxVal[0]);
      return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Market Structure - Higher High                                   |
//+------------------------------------------------------------------+
bool IsHigherHigh(string symbol) {
   double prevHigh  = 0;
   double recentHigh = 0;

   // أعلى نقطة في الفترة البعيدة
   for(int i = StructurePeriod * 2; i > StructurePeriod; i--)
      prevHigh = MathMax(prevHigh, iHigh(symbol, PERIOD_H1, i));

   // أعلى نقطة في الفترة الأخيرة
   for(int i = StructurePeriod; i >= 1; i--)
      recentHigh = MathMax(recentHigh, iHigh(symbol, PERIOD_H1, i));

   return recentHigh > prevHigh; // Higher High ✅
}

//+------------------------------------------------------------------+
//| Market Structure - Lower Low                                     |
//+------------------------------------------------------------------+
bool IsLowerLow(string symbol) {
   double prevLow   = 999999;
   double recentLow = 999999;

   for(int i = StructurePeriod * 2; i > StructurePeriod; i--)
      prevLow = MathMin(prevLow, iLow(symbol, PERIOD_H1, i));

   for(int i = StructurePeriod; i >= 1; i--)
      recentLow = MathMin(recentLow, iLow(symbol, PERIOD_H1, i));

   return recentLow < prevLow; // Lower Low ✅
}

//+------------------------------------------------------------------+
//| فتح الصفقة                                                       |
//+------------------------------------------------------------------+
void OpenTrade(string symbol, int direction) {
   double atr    = GetATR(symbol);
   if(atr <= 0) return;

   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double ask    = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double slPoints = atr * ATR_SL_Multi / point;
   double lot      = CalculateLot(symbol, slPoints);
   double halfLot  = MathMax(
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
      MathFloor((lot / 2) / SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP))
      * SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));

   if(direction == 1) {
      double sl  = NormalizeDouble(ask - atr * ATR_SL_Multi, digits);
      double tp1 = NormalizeDouble(ask + atr * ATR_TP1_Multi, digits);
      double tp2 = NormalizeDouble(ask + atr * ATR_TP2_Multi, digits);
      trade.Buy(halfLot, symbol, ask, sl, tp1, "LB_BUY_TP1");
      trade.Buy(halfLot, symbol, ask, sl, tp2, "LB_BUY_TP2");
   } else {
      double sl  = NormalizeDouble(bid + atr * ATR_SL_Multi, digits);
      double tp1 = NormalizeDouble(bid - atr * ATR_TP1_Multi, digits);
      double tp2 = NormalizeDouble(bid - atr * ATR_TP2_Multi, digits);
      trade.Sell(halfLot, symbol, bid, sl, tp1, "LB_SELL_TP1");
      trade.Sell(halfLot, symbol, bid, sl, tp2, "LB_SELL_TP2");
   }

   Print("📈 Trade | ", symbol, " | ", direction == 1 ? "BUY" : "SELL",
         " | Lot: ", halfLot, "×2 | ATR: ", atr);
}

//+------------------------------------------------------------------+
//| إدارة الصفقات: Breakeven + Trailing                             |
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
      double bid       = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double price     = (posType == POSITION_TYPE_BUY) ? bid : ask;
      double minMove   = MinTrailPips * SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;

      double beTrigger = (posType == POSITION_TYPE_BUY)
                         ? entry + atr * ATR_BE_Multi
                         : entry - atr * ATR_BE_Multi;

      // Breakeven
      if(posType == POSITION_TYPE_BUY && price >= beTrigger && currentSL < entry) {
         trade.PositionModify(posInfo.Ticket(), NormalizeDouble(entry, digits), currentTP);
         Print("✅ Breakeven | ", symbol);
         continue;
      }
      if(posType == POSITION_TYPE_SELL && price <= beTrigger && currentSL > entry) {
         trade.PositionModify(posInfo.Ticket(), NormalizeDouble(entry, digits), currentTP);
         Print("✅ Breakeven | ", symbol);
         continue;
      }

      // Trailing
      if(posType == POSITION_TYPE_BUY && currentSL >= entry) {
         double trailSL = NormalizeDouble(price - atr * ATR_Trail_Multi, digits);
         if(trailSL > currentSL + minMove)
            trade.PositionModify(posInfo.Ticket(), trailSL, currentTP);
      }
      if(posType == POSITION_TYPE_SELL && currentSL <= entry && entry > 0) {
         double trailSL = NormalizeDouble(price + atr * ATR_Trail_Multi, digits);
         if(trailSL < currentSL - minMove || currentSL == 0)
            trade.PositionModify(posInfo.Ticket(), trailSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
//| Daily Loss Check                                                 |
//+------------------------------------------------------------------+
void CheckDailyLoss() {
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(lastDayChecked, last);

   if(now.day != last.day) {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      dailyLimitHit   = false;
      SaveState();
      Print("📅 New Day | Balance: ", startDayBalance);
   }

   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPercent = (startDayBalance - equity) / startDayBalance * 100.0;

   if(lossPercent >= MaxDailyLoss && !dailyLimitHit) {
      dailyLimitHit = true;
      CloseAllTrades();
      SaveState();
      Print("🛑 Daily Loss Limit Hit! ", MaxDailyLoss, "%");
   }
}

//+------------------------------------------------------------------+
//| حساب اللوت الديناميكي                                           |
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
   double lotStep  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lot));
}

//+------------------------------------------------------------------+
//| Save / Load State                                               |
//+------------------------------------------------------------------+
void SaveState() {
   int handle = FileOpen(stateFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle == INVALID_HANDLE) return;
   FileWrite(handle, DoubleToString(startDayBalance, 2));
   FileWrite(handle, TimeToString(TimeCurrent()));
   FileWrite(handle, dailyLimitHit ? "1" : "0");
   FileClose(handle);
}

void LoadState() {
   if(ForceResetDailyLimit) {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      dailyLimitHit   = false;
      SaveState();
      Print("⚡ Force Reset Applied");
      return;
   }
   if(!FileIsExist(stateFile, FILE_COMMON)) {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      SaveState();
      return;
   }
   int handle = FileOpen(stateFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(handle == INVALID_HANDLE) { startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE); return; }
   double   savedBalance = StringToDouble(FileReadString(handle));
   datetime savedTime    = StringToTime(FileReadString(handle));
   bool     savedLimit   = FileReadString(handle) == "1";
   FileClose(handle);

   MqlDateTime now, saved;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(savedTime, saved);

   if(now.day == saved.day && now.mon == saved.mon && now.year == saved.year) {
      startDayBalance = savedBalance;
      lastDayChecked  = savedTime;
      dailyLimitHit   = savedLimit;
      Print("♻️ State Restored | Balance: ", startDayBalance, " | LimitHit: ", dailyLimitHit);
   } else {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      dailyLimitHit   = false;
      SaveState();
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double GetATR(string symbol) {
   double atr[];
   int handle = iATR(symbol, PERIOD_H1, ATR_Period);
   if(handle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(atr, true);
   CopyBuffer(handle, 0, 0, 3, atr);
   IndicatorRelease(handle);
   return atr[0];
}

double GetCurrentSpread(string symbol) {
   return (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
}

bool SpreadOK(PairInfo &pair) {
   double current = GetCurrentSpread(pair.symbol);
   if(pair.normalSpread <= 0) { pair.normalSpread = current; return true; }
   return current <= pair.normalSpread * 2.0;
}

bool HasOpenPosition(string symbol) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == symbol && posInfo.Magic() == magicNumber) return true;
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
