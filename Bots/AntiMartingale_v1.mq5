//+------------------------------------------------------------------+
//|          Anti-Martingale EA                                      |
//|          بناءً على إشارات Session Trend Sniper v4.1             |
//|          الإصدار: 1.0                                           |
//+------------------------------------------------------------------+
//  منطق Anti-Martingale لكل زوج مستقل:
//  ابدأ: 0.01
//  بعد ربحتين متتاليتين → ضاعف اللوت (×2)
//  أقصى لوت: 0.08
//  أول خسارة → ارجع لـ 0.01
//+------------------------------------------------------------------+
#property copyright "Anti-Martingale EA"
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
input bool   Use_USDJPY  = true;
input bool   Use_USDCAD  = true;
input bool   Use_AUDUSD  = true;   // AUDUSD - Asian 22:00-01:00 GMT
input bool   Use_NZDUSD  = true;   // NZDUSD - Asian 22:00-01:00 GMT
input string SymbolSuffix = "m";

input group "=== Anti-Martingale ==="
input double BaseLot        = 0.01;  // اللوت الابتدائي
input double MaxLot         = 0.08;  // الحد الأقصى للوت
input int    WinsToDouble   = 2;     // عدد الربحات قبل التضاعف
input double MaxDailyLoss   = 5.0;   // أقصى خسارة يومية %

input group "=== ATR Settings ==="
input int    ATR_Period      = 14;
input double ATR_SL_Multi    = 1.0;
input double ATR_BE_Multi    = 1.0;
input double ATR_TP1_Multi   = 2.5;
input double ATR_TP2_Multi   = 4.0;
input double ATR_Trail_Multi = 1.5;
input double MinTrailPips    = 5.0;

input group "=== Spread Filter ==="
input double MaxSpreadMulti  = 2.0;

input group "=== News Filter (GMT) ==="
input bool   UseNewsFilter     = true;
input int    NewsMinutesBefore = 30;

input group "=== وضع التجربة ==="
input bool   ForceResetDailyLimit = false;

//+------------------------------------------------------------------+
//| بنية كل زوج مع Anti-Martingale                                  |
//+------------------------------------------------------------------+
struct PairInfo {
   string   symbol;
   int      sessionStart;
   int      sessionEnd;
   bool     enabled;
   double   normalSpread;
   datetime lastBar;

   // Anti-Martingale tracking (مستقل لكل زوج)
   double   currentLot;      // اللوت الحالي
   int      consecutiveWins; // عدد الربحات المتتالية
   int      winsThisCycle;   // الربحات في الدورة الحالية

   void Init(string sym, int sStart, int sEnd, bool en) {
      symbol          = sym;
      sessionStart    = sStart;
      sessionEnd      = sEnd;
      enabled         = en;
      normalSpread    = 0;
      lastBar         = 0;
      currentLot      = 0.01; // يتحدد من BaseLot في OnInit
      consecutiveWins = 0;
      winsThisCycle   = 0;
   }
};

PairInfo pairs[6];

//+------------------------------------------------------------------+
//| متغيرات عامة                                                    |
//+------------------------------------------------------------------+
double   startDayBalance = 0;
datetime lastDayChecked  = 0;
bool     dailyLimitHit   = false;
int      magicNumber     = 99999;
string   stateFile       = "AM_State.txt";

//+------------------------------------------------------------------+
//| OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(10);

   pairs[0].Init("EURUSD" + SymbolSuffix, 7,  10, Use_EURUSD);
   pairs[1].Init("GBPUSD" + SymbolSuffix, 7,  10, Use_GBPUSD);
   pairs[2].Init("USDJPY" + SymbolSuffix, 0,  3,  Use_USDJPY);
   pairs[3].Init("USDCAD" + SymbolSuffix, 13, 16, Use_USDCAD);
   pairs[4].Init("AUDUSD" + SymbolSuffix, 22, 1,  Use_AUDUSD);
   pairs[5].Init("NZDUSD" + SymbolSuffix, 22, 1,  Use_NZDUSD);

   // تعيين اللوت الابتدائي لكل زوج
   for(int i = 0; i < 6; i++) {
      pairs[i].currentLot = BaseLot;
      if(pairs[i].enabled)
         pairs[i].normalSpread = GetCurrentSpread(pairs[i].symbol);
   }

   LoadState();
   Print("✅ Anti-Martingale EA v1.0 Started");
   Print("📊 BaseLot: ", BaseLot, " | MaxLot: ", MaxLot,
         " | WinsToDouble: ", WinsToDouble);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                          |
//+------------------------------------------------------------------+
void OnTick() {
   CheckDailyLoss();
   if(dailyLimitHit) return;

   ManageOpenTrades();

   // فحص الأخبار
   if(UseNewsFilter && IsNewsTime()) return;

   for(int i = 0; i < 6; i++) {
      if(!pairs[i].enabled) continue;
      if(!IsSessionTime(pairs[i])) continue;
      if(!SpreadOK(pairs[i])) continue;
      if(HasOpenPosition(pairs[i].symbol)) continue;

      // فحص نتيجة الصفقة السابقة وتحديث اللوت
      UpdateAntiMartingale(pairs[i]);

      // فحص إشارة عند شمعة H1 جديدة فقط
      datetime currentBar = iTime(pairs[i].symbol, PERIOD_H1, 0);
      if(currentBar == pairs[i].lastBar) continue;
      pairs[i].lastBar = currentBar;

      int signal = GetSignal(pairs[i].symbol);
      if(signal == 0) continue;

      OpenTrade(pairs[i], signal);
   }
}

//+------------------------------------------------------------------+
//| Anti-Martingale: تحديث اللوت بعد كل صفقة                       |
//+------------------------------------------------------------------+
void UpdateAntiMartingale(PairInfo &pair) {
   // ابحث عن آخر صفقة مغلقة لهذا الزوج
   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0) return;

   // اختار آخر صفقة مغلقة
   HistorySelect(0, TimeCurrent());

   for(int i = totalDeals - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != pair.symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      // تجنب معالجة نفس الصفقة مرتين
      static datetime lastProcessed[];
      if(ArraySize(lastProcessed) < 6) ArrayResize(lastProcessed, 6);

      // نحدد index الزوج
      int pairIdx = -1;
      for(int j = 0; j < 6; j++)
         if(pairs[j].symbol == pair.symbol) { pairIdx = j; break; }
      if(pairIdx < 0) return;
      if(dealTime <= lastProcessed[pairIdx]) return;
      lastProcessed[pairIdx] = dealTime;

      if(profit > 0) {
         // ربح ✅
         pair.consecutiveWins++;
         Print("✅ WIN | ", pair.symbol,
               " | Consecutive: ", pair.consecutiveWins,
               " | Profit: ", profit);

         // لو وصل WinsToDouble → ضاعف اللوت
         if(pair.consecutiveWins >= WinsToDouble) {
            double newLot = NormalizeLot(pair.symbol, pair.currentLot * 2);
            if(newLot <= MaxLot) {
               pair.currentLot = newLot;
               Print("📈 LOT DOUBLED | ", pair.symbol,
                     " | New Lot: ", pair.currentLot);
            } else {
               pair.currentLot = MaxLot;
               Print("⚠️ MAX LOT Reached | ", pair.symbol,
                     " | Lot: ", pair.currentLot);
            }
            pair.consecutiveWins = 0; // ريست العداد بعد التضاعف
         }
      } else {
         // خسارة ❌ → ارجع للأصل
         if(pair.currentLot > BaseLot || pair.consecutiveWins > 0) {
            Print("❌ LOSS | ", pair.symbol,
                  " | Reset Lot: ", pair.currentLot, " → ", BaseLot,
                  " | Was on: ", pair.consecutiveWins, " wins");
            pair.currentLot      = BaseLot;
            pair.consecutiveWins = 0;
         }
      }
      break;
   }
}

//+------------------------------------------------------------------+
//| GetSignal - Triple EMA فقط (بدون H4 filter)                    |
//+------------------------------------------------------------------+
int GetSignal(string symbol) {

   // === Triple EMA على H1 فقط ===
   double ema4[], ema8[], ema21[];
   int ema4Handle  = iMA(symbol, PERIOD_H1, 4,  0, MODE_EMA, PRICE_CLOSE);
   int ema8Handle  = iMA(symbol, PERIOD_H1, 8,  0, MODE_EMA, PRICE_CLOSE);
   int ema21Handle = iMA(symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
   if(ema4Handle==INVALID_HANDLE || ema8Handle==INVALID_HANDLE || ema21Handle==INVALID_HANDLE) return 0;

   ArraySetAsSeries(ema4,  true);
   ArraySetAsSeries(ema8,  true);
   ArraySetAsSeries(ema21, true);
   CopyBuffer(ema4Handle,  0, 0, 3, ema4);
   CopyBuffer(ema8Handle,  0, 0, 3, ema8);
   CopyBuffer(ema21Handle, 0, 0, 3, ema21);
   IndicatorRelease(ema4Handle);
   IndicatorRelease(ema8Handle);
   IndicatorRelease(ema21Handle);

   // BUY:  EMA4 > EMA8 > EMA21
   // SELL: EMA4 < EMA8 < EMA21
   bool bullEMA = (ema4[0] > ema8[0]) && (ema8[0] > ema21[0]);
   bool bearEMA = (ema4[0] < ema8[0]) && (ema8[0] < ema21[0]);

   Print("🔍 ", symbol,
         " | EMA4:", DoubleToString(ema4[0],5),
         " EMA8:", DoubleToString(ema8[0],5),
         " EMA21:", DoubleToString(ema21[0],5),
         " | Signal:", bullEMA?"🟢BUY":(bearEMA?"🔴SELL":"⚪None"));

   if(bullEMA) return 1;
   if(bearEMA) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| فتح الصفقة باللوت الحالي للزوج                                  |
//+------------------------------------------------------------------+
void OpenTrade(PairInfo &pair, int direction) {
   string symbol = pair.symbol;
   double atr    = GetATR(symbol);
   if(atr <= 0) return;

   int    digits  = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double ask     = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(symbol, SYMBOL_BID);
   double lot     = pair.currentLot;
   double halfLot = NormalizeLot(symbol, lot / 2);

   if(direction == 1) {
      double sl  = NormalizeDouble(ask - atr * ATR_SL_Multi, digits);
      double tp1 = NormalizeDouble(ask + atr * ATR_TP1_Multi, digits);
      double tp2 = NormalizeDouble(ask + atr * ATR_TP2_Multi, digits);
      trade.Buy(halfLot, symbol, ask, sl, tp1, "AM_BUY_TP1");
      trade.Buy(halfLot, symbol, ask, sl, tp2, "AM_BUY_TP2");
   } else {
      double sl  = NormalizeDouble(bid + atr * ATR_SL_Multi, digits);
      double tp1 = NormalizeDouble(bid - atr * ATR_TP1_Multi, digits);
      double tp2 = NormalizeDouble(bid - atr * ATR_TP2_Multi, digits);
      trade.Sell(halfLot, symbol, bid, sl, tp1, "AM_SELL_TP1");
      trade.Sell(halfLot, symbol, bid, sl, tp2, "AM_SELL_TP2");
   }

   Print("📈 ", direction == 1 ? "BUY" : "SELL", " | ", symbol,
         " | Lot: ", halfLot, "×2",
         " | Wins: ", pair.consecutiveWins,
         " | ATR: ", DoubleToString(atr, 5));
}

//+------------------------------------------------------------------+
//| Breakeven + Trailing                                             |
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

      double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);

      // Breakeven - يتفعل مرة وحدة فقط (threshold بـ point واحد)
      if(posType == POSITION_TYPE_BUY && price >= beTrigger && currentSL < entry - point) {
         trade.PositionModify(posInfo.Ticket(), NormalizeDouble(entry, digits), currentTP);
         Print("✅ Breakeven | ", symbol);
         continue;
      }
      if(posType == POSITION_TYPE_SELL && price <= beTrigger && currentSL > entry + point) {
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
      // ريست كل الأزواج عند Daily Loss
      for(int i = 0; i < 6; i++) {
         pairs[i].currentLot      = BaseLot;
         pairs[i].consecutiveWins = 0;
      }
      SaveState();
      Print("🛑 Daily Loss ", MaxDailyLoss, "% Hit! All pairs reset to BaseLot.");
   }
}

//+------------------------------------------------------------------+
//| M5 Candle Patterns                                               |
//+------------------------------------------------------------------+
bool IsBullishCandle(string symbol) {
   double open1  = iOpen(symbol,  PERIOD_M5, 1);
   double close1 = iClose(symbol, PERIOD_M5, 1);
   double open2  = iOpen(symbol,  PERIOD_M5, 2);
   double close2 = iClose(symbol, PERIOD_M5, 2);
   double low1   = iLow(symbol,   PERIOD_M5, 1);
   bool engulfing = (close2 < open2) && (close1 > open1) && (close1 > open2) && (open1 < close2);
   double body  = MathAbs(close1 - open1);
   double tail  = open1 - low1;
   bool pinBar  = (tail >= body * 2) && (close1 > open1);
   return (engulfing || pinBar);
}

bool IsBearishCandle(string symbol) {
   double open1  = iOpen(symbol,  PERIOD_M5, 1);
   double close1 = iClose(symbol, PERIOD_M5, 1);
   double open2  = iOpen(symbol,  PERIOD_M5, 2);
   double close2 = iClose(symbol, PERIOD_M5, 2);
   double high1  = iHigh(symbol,  PERIOD_M5, 1);
   bool engulfing = (close2 > open2) && (close1 < open1) && (close1 < open2) && (open1 > close2);
   double body  = MathAbs(close1 - open1);
   double wick  = high1 - open1;
   bool pinBar  = (wick >= body * 2) && (close1 < open1);
   return (engulfing || pinBar);
}

//+------------------------------------------------------------------+
//| Session Time Check                                               |
//+------------------------------------------------------------------+
bool IsSessionTime(PairInfo &pair) {
   MqlDateTime gmt;
   TimeToStruct(TimeGMT(), gmt);
   int hour = gmt.hour;
   if(pair.sessionStart > pair.sessionEnd)
      return (hour >= pair.sessionStart || hour < pair.sessionEnd);
   return (hour >= pair.sessionStart && hour < pair.sessionEnd);
}

//+------------------------------------------------------------------+
//| News Filter                                                      |
//+------------------------------------------------------------------+
bool IsNewsTime() {
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   int newsHour[]      = {13, 19, 13};
   int newsMinute[]    = {30,  0, 30};
   int newsDayOfWeek[] = { 5,  3,  3};
   int total = ArraySize(newsHour);
   for(int i = 0; i < total; i++) {
      if(t.day_of_week != newsDayOfWeek[i]) continue;
      int currentMins = t.hour * 60 + t.min;
      int newsMins    = newsHour[i] * 60 + newsMinute[i];
      if(MathAbs(currentMins - newsMins) <= NewsMinutesBefore) return true;
   }
   return false;
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
   // حفظ حالة كل زوج
   for(int i = 0; i < 6; i++) {
      FileWrite(handle, DoubleToString(pairs[i].currentLot, 2));
      FileWrite(handle, IntegerToString(pairs[i].consecutiveWins));
   }
   FileClose(handle);
}

void LoadState() {
   if(ForceResetDailyLimit) {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      dailyLimitHit   = false;
      for(int i = 0; i < 6; i++) {
         pairs[i].currentLot      = BaseLot;
         pairs[i].consecutiveWins = 0;
      }
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

   // استرجاع حالة كل زوج
   double savedLots[6];
   int    savedWins[6];
   for(int i = 0; i < 6; i++) {
      savedLots[i] = StringToDouble(FileReadString(handle));
      savedWins[i] = (int)StringToInteger(FileReadString(handle));
   }
   FileClose(handle);

   MqlDateTime now, saved;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(savedTime, saved);

   if(now.day == saved.day && now.mon == saved.mon && now.year == saved.year) {
      startDayBalance = savedBalance;
      lastDayChecked  = savedTime;
      dailyLimitHit   = savedLimit;
      for(int i = 0; i < 6; i++) {
         pairs[i].currentLot      = savedLots[i] > 0 ? savedLots[i] : BaseLot;
         pairs[i].consecutiveWins = savedWins[i];
      }
      Print("♻️ State Restored | DailyLimit: ", dailyLimitHit);
      for(int i = 0; i < 6; i++)
         Print("   ", pairs[i].symbol, " | Lot: ", pairs[i].currentLot,
               " | Wins: ", pairs[i].consecutiveWins);
   } else {
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayChecked  = TimeCurrent();
      dailyLimitHit   = false;
      for(int i = 0; i < 6; i++) {
         pairs[i].currentLot      = BaseLot;
         pairs[i].consecutiveWins = 0;
      }
      SaveState();
      Print("📅 New Day on Restart");
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

double NormalizeLot(string symbol, double lot) {
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lot));
}

double GetCurrentSpread(string symbol) {
   return (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
}

bool SpreadOK(PairInfo &pair) {
   double current = GetCurrentSpread(pair.symbol);
   if(pair.normalSpread <= 0) { pair.normalSpread = current; return true; }
   return current <= pair.normalSpread * MaxSpreadMulti;
}

bool HasOpenPosition(string symbol) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == symbol && posInfo.Magic() == magicNumber) return true;
   }
   return false;
}

void CloseAllTrades() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() == magicNumber)
         trade.PositionClose(posInfo.Ticket());
   }
}
//+------------------------------------------------------------------+
