//+------------------------------------------------------------------+
//|          Stochastic Anti-Martingale EA                           |
//|          استراتيجية: Stochastic Crossover + Sessions            |
//|          الإصدار: 1.0                                           |
//+------------------------------------------------------------------+
#property copyright "Stochastic AM EA"
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
input bool   Use_AUDUSD  = true;
input bool   Use_NZDUSD  = true;
input string SymbolSuffix = "m";

input group "=== Anti-Martingale ==="
input double BaseLot      = 0.01;
input double MaxLot       = 0.08;
input int    WinsToDouble = 2;
input double MaxDailyLoss = 5.0;

input group "=== ATR Settings ==="
input int    ATR_Period      = 14;
input double ATR_SL_Multi    = 1.5;
input double ATR_BE_Multi    = 1.0;
input double ATR_TP1_Multi   = 2.5;
input double ATR_TP2_Multi   = 4.0;
input double ATR_Trail_Multi = 1.5;
input double MinTrailPips    = 5.0;

input group "=== Stochastic ==="
input int    Stoch_K       = 5;    // %K period
input int    Stoch_D       = 3;    // %D period
input int    Stoch_Slowing = 3;    // Slowing
input double Stoch_OB      = 70.0; // Overbought
input double Stoch_OS      = 30.0; // Oversold

input group "=== Spread Filter ==="
input double MaxSpreadMulti = 2.0;

input group "=== News Filter ==="
input bool   UseNewsFilter     = true;
input int    NewsMinutesBefore = 30;

input group "=== وضع التجربة ==="
input bool   ForceResetDailyLimit = false;

//+------------------------------------------------------------------+
//| بنية الزوج                                                       |
//+------------------------------------------------------------------+
struct PairInfo {
   string   symbol;
   int      sessionStart;
   int      sessionEnd;
   bool     enabled;
   double   normalSpread;
   datetime lastBar;
   double   currentLot;
   int      consecutiveWins;

   void Init(string sym, int sStart, int sEnd, bool en) {
      symbol          = sym;
      sessionStart    = sStart;
      sessionEnd      = sEnd;
      enabled         = en;
      normalSpread    = 0;
      lastBar         = 0;
      currentLot      = 0.01;
      consecutiveWins = 0;
   }
};

PairInfo pairs[6];

//+------------------------------------------------------------------+
//| متغيرات عامة                                                    |
//+------------------------------------------------------------------+
double   startDayBalance = 0;
datetime lastDayChecked  = 0;
bool     dailyLimitHit   = false;
int      magicNumber     = 11111;
string   stateFile       = "Stoch_State.txt";

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

   for(int i = 0; i < 6; i++) {
      pairs[i].currentLot = BaseLot;
      if(pairs[i].enabled)
         pairs[i].normalSpread = GetCurrentSpread(pairs[i].symbol);
   }

   LoadState();
   Print("✅ Stochastic AM EA v1.0 Started");
   Print("📊 BaseLot:", BaseLot, " MaxLot:", MaxLot,
         " OB:", Stoch_OB, " OS:", Stoch_OS);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                          |
//+------------------------------------------------------------------+
void OnTick() {
   CheckDailyLoss();
   if(dailyLimitHit) return;

   ManageOpenTrades();

   if(UseNewsFilter && IsNewsTime()) return;

   for(int i = 0; i < 6; i++) {
      if(!pairs[i].enabled) continue;
      if(!IsSessionTime(pairs[i])) continue;
      if(!SpreadOK(pairs[i])) continue;
      if(HasOpenPosition(pairs[i].symbol)) continue;

      UpdateAntiMartingale(pairs[i]);

      datetime currentBar = iTime(pairs[i].symbol, PERIOD_H1, 0);
      if(currentBar == pairs[i].lastBar) continue;
      pairs[i].lastBar = currentBar;

      int signal = GetSignal(pairs[i].symbol);
      if(signal == 0) continue;

      OpenTrade(pairs[i], signal);
   }
}

//+------------------------------------------------------------------+
//| GetSignal - Stochastic Crossover                                |
//+------------------------------------------------------------------+
int GetSignal(string symbol) {

   double stochK[], stochD[];
   int stochHandle = iStochastic(symbol, PERIOD_H1,
                                 Stoch_K, Stoch_D, Stoch_Slowing,
                                 MODE_SMA, STO_LOWHIGH);
   if(stochHandle == INVALID_HANDLE) return 0;

   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   CopyBuffer(stochHandle, 0, 0, 3, stochK); // %K
   CopyBuffer(stochHandle, 1, 0, 3, stochD); // %D
   IndicatorRelease(stochHandle);

   // %K تقطع %D من تحت لفوق + Oversold → BUY
   bool bullCross = (stochK[0] > stochD[0]) && (stochK[1] <= stochD[1]);
   bool inOS      = stochK[1] < Stoch_OS;

   // %K تقطع %D من فوق لتحت + Overbought → SELL
   bool bearCross = (stochK[0] < stochD[0]) && (stochK[1] >= stochD[1]);
   bool inOB      = stochK[1] > Stoch_OB;

   Print("🔍 ", symbol,
         " | %K:", DoubleToString(stochK[0], 1),
         " %D:", DoubleToString(stochD[0], 1),
         " | Signal:", (bullCross&&inOS)?"🟢BUY":((bearCross&&inOB)?"🔴SELL":"⚪None"));

   if(bullCross && inOS)  return 1;
   if(bearCross && inOB)  return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| فتح الصفقة                                                      |
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
      trade.Buy(halfLot, symbol, ask, sl, tp1, "STOCH_BUY_TP1");
      trade.Buy(halfLot, symbol, ask, sl, tp2, "STOCH_BUY_TP2");
   } else {
      double sl  = NormalizeDouble(bid + atr * ATR_SL_Multi, digits);
      double tp1 = NormalizeDouble(bid - atr * ATR_TP1_Multi, digits);
      double tp2 = NormalizeDouble(bid - atr * ATR_TP2_Multi, digits);
      trade.Sell(halfLot, symbol, bid, sl, tp1, "STOCH_SELL_TP1");
      trade.Sell(halfLot, symbol, bid, sl, tp2, "STOCH_SELL_TP2");
   }

   Print("📈 ", direction==1?"BUY":"SELL", " | ", symbol,
         " | Lot:", halfLot, "×2 | ATR:", DoubleToString(atr,5));
}

//+------------------------------------------------------------------+
//| ManageOpenTrades - Breakeven + Trailing                         |
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
      double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double minMove   = MinTrailPips * point * 10;
      double beTrigger = (posType == POSITION_TYPE_BUY)
                         ? entry + atr * ATR_BE_Multi
                         : entry - atr * ATR_BE_Multi;

      // Breakeven - مرة وحدة فقط
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

      // Trailing Stop
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
//| UpdateAntiMartingale                                            |
//+------------------------------------------------------------------+
void UpdateAntiMartingale(PairInfo &pair) {
   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0) return;
   HistorySelect(0, TimeCurrent());

   for(int i = totalDeals - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL)  != pair.symbol)   continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != magicNumber)   continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

      double   profit   = HistoryDealGetDouble(ticket,  DEAL_PROFIT);
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      static datetime lastProcessed[];
      if(ArraySize(lastProcessed) < 6) ArrayResize(lastProcessed, 6);

      int pairIdx = -1;
      for(int j = 0; j < 6; j++)
         if(pairs[j].symbol == pair.symbol) { pairIdx = j; break; }
      if(pairIdx < 0) return;
      if(dealTime <= lastProcessed[pairIdx]) return;
      lastProcessed[pairIdx] = dealTime;

      if(profit > 0) {
         pair.consecutiveWins++;
         Print("✅ WIN | ", pair.symbol, " | Consecutive:", pair.consecutiveWins);
         if(pair.consecutiveWins >= WinsToDouble) {
            double newLot = NormalizeLot(pair.symbol, pair.currentLot * 2);
            pair.currentLot      = (newLot <= MaxLot) ? newLot : MaxLot;
            pair.consecutiveWins = 0;
            Print("📈 LOT DOUBLED | ", pair.symbol, " | New Lot:", pair.currentLot);
         }
      } else {
         pair.currentLot      = BaseLot;
         pair.consecutiveWins = 0;
         Print("❌ LOSS | ", pair.symbol, " | Reset to BaseLot");
      }
      break;
   }
}

//+------------------------------------------------------------------+
//| CheckDailyLoss                                                  |
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
      Print("📅 New Day | Balance:", startDayBalance);
   }

   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPercent = (startDayBalance - equity) / startDayBalance * 100.0;

   if(lossPercent >= MaxDailyLoss && !dailyLimitHit) {
      dailyLimitHit = true;
      CloseAllTrades();
      for(int i = 0; i < 6; i++) {
         pairs[i].currentLot      = BaseLot;
         pairs[i].consecutiveWins = 0;
      }
      SaveState();
      Print("🛑 Daily Loss ", MaxDailyLoss, "% Hit!");
   }
}

//+------------------------------------------------------------------+
//| Session Time                                                    |
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
//| News Filter                                                     |
//+------------------------------------------------------------------+
bool IsNewsTime() {
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   int newsHour[]      = {13, 19, 13};
   int newsMinute[]    = {30,  0, 30};
   int newsDayOfWeek[] = { 5,  3,  3};
   for(int i = 0; i < 3; i++) {
      if(t.day_of_week != newsDayOfWeek[i]) continue;
      int currentMins = t.hour * 60 + t.min;
      int newsMins    = newsHour[i] * 60 + newsMinute[i];
      if(MathAbs(currentMins - newsMins) <= NewsMinutesBefore) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Save / Load State                                              |
//+------------------------------------------------------------------+
void SaveState() {
   int handle = FileOpen(stateFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle == INVALID_HANDLE) return;
   FileWrite(handle, DoubleToString(startDayBalance, 2));
   FileWrite(handle, TimeToString(TimeCurrent()));
   FileWrite(handle, dailyLimitHit ? "1" : "0");
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
   double   savedLots[6];
   int      savedWins[6];
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
      Print("♻️ State Restored | DailyLimit:", dailyLimitHit);
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
//| Helpers                                                         |
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
