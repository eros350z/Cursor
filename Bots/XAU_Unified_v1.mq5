//+------------------------------------------------------------------+
//|                                          XAU_Unified_v1.mq5      |
//|  Unified XAU: HTF trend + pullback + M5 trigger                  |
//|  Filters: spread, session, news window, daily loss cap          |
//|  Trade mgmt: partial take-profit (ATR) + breakeven + ATR trail   |
//+------------------------------------------------------------------+
#property copyright "XAU Unified"
#property version   "1.01"
#property description "XAUUSD unified EA — M5 profiles + partial + BE + trail"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

enum ENUM_SIGNAL_PROFILE
  {
   PROFILE_M5_MODERATE = 0, // H4 trend + M5 momentum — moderate trade count
   PROFILE_M5_FREQUENT = 1, // H4 + M5 EMA cross — higher trade count
   PROFILE_STRICT      = 2  // H1 pullback + candle pattern — fewer trades
  };

CTrade         trade;
CPositionInfo  posInfo;

//--- inputs: symbol & core
input group "=== Symbol ==="
input string   TradeSymbol        = "XAUUSD";   // e.g. XAUUSD or XAUUSDm

input group "=== Money ==="
input double   RiskPercent        = 1.0;        // % balance risked at SL distance
input double   MaxDailyLossPct    = 3.0;        // pause new trades + flat if hit
input int      MaxOpenPositions   = 1;
input double   MaxLotCap          = 5.0;        // hard cap (0 = no cap)

input group "=== ATR (M15) — distances ==="
input int      ATR_Period         = 14;
input ENUM_TIMEFRAMES ATR_TF      = PERIOD_M15;
input double   ATR_MinFilter      = 0.10;       // skip if ATR too low (broker units)
input double   ATR_SL_Multi       = 1.5;
input double   ATR_TP1_Multi      = 1.0;        // first partial trigger (profit in ATR)
input double   ATR_TP2_Multi      = 2.0;
input double   ATR_TP3_Multi      = 3.2;        // last partial; then trail
input double   ATR_TP_Far_Multi   = 6.0;        // broker TP (safety far target)
input double   ATR_BE_Multi       = 0.8;        // optional early BE if no partial yet
input double   ATR_Trail_Multi    = 1.2;        // trail distance after TP3
input double   MinTrailMovePrice  = 0.15;       // min price move to modify trail (XAU units)

input group "=== Partial closes (% of current volume) ==="
input double   TP1_ClosePct       = 30.0;
input double   TP2_ClosePct       = 30.0;
input double   TP3_ClosePct       = 25.0;

input group "=== Breakeven ==="
input bool     MoveBE_AfterTP1    = true;       // move SL to BE+offset after TP1
input double   BE_OffsetPrice     = 0.05;       // lock tiny profit (price units)

input group "=== Spread filter ==="
input bool     UseSpreadFilter    = true;
input double   MaxSpreadMult      = 2.5;        // vs baseline sampled at init

input group "=== Session (GMT) ==="
input bool     UseSessionFilter   = true;
input int      SessionStartGMT    = 6;          // inclusive
input int      SessionEndGMT      = 18;         // exclusive
input bool     BlockFridayAfter   = true;
input int      FridayCutoffGMT    = 20;         // no new entries from this hour Fri

input group "=== News window (GMT, static slots) ==="
input bool     UseNewsFilter      = true;
input int      NewsMinutesBefore  = 30;
input int      NewsMinutesAfter   = 30;

input group "=== Signal — M5 profile & HTF trend ==="
input ENUM_SIGNAL_PROFILE SignalProfile = PROFILE_M5_MODERATE;
input int      MinM5BarsBetweenTrades = 2;     // min full M5 bars between new entries
input int      MaxTradesPerDay        = 0;     // 0 = no cap; else max new entries / GMT day
input bool     UseH1PullbackFilter    = false; // if true: H1 must be near EMA21 (like strict)
input bool     RequireM5CandlePattern = false; // if true: need engulfing/pin on M5
input bool     UseADXFilter           = true;
input ENUM_TIMEFRAMES ADX_Timeframe   = PERIOD_M5;
input int      H4_EMA_Period          = 200;
input int      H1_EMA_Period        = 21;
input double   Pullback_ATRMult     = 0.45;    // with UseH1PullbackFilter: max |H1 close-EMA| vs ATR(H1)
input int      M5_EMA_Fast          = 8;
input int      M5_EMA_Slow          = 21;
input int      M5_RSI_Period        = 7;
input double   M5_RSI_Neutral       = 50.0;
input int      ADX_Period           = 14;
input double   ADX_MinLevel         = 16.0;    // with UseADXFilter on ADX_Timeframe (strict uses H1)

input group "=== EA ==="
input ulong    MagicNumber        = 202505141;
input int      DeviationPoints    = 80;
input bool     ForceResetDaily    = false;
input string   StateFileName      = "XAU_Unified_v1_state.txt";

//--- globals
string         gSym;
double         gBaselineSpread    = 0;
datetime       gLastM5Bar         = 0;
double         gDayStartBalance   = 0;
datetime       gLastDayCheck      = 0;
bool           gDailyPaused       = false;
datetime       gLastEntryM5BarTime = 0;
int            gTradesToday       = 0;
int            gTradeDayId        = 0;         // yyyymmdd GMT

struct TradeState
{
   ulong    ticket;
   bool     tp1;
   bool     tp2;
   bool     tp3;
   bool     beDone;
};

TradeState gStates[];

//+------------------------------------------------------------------+
int StateIndex(ulong ticket)
{
   for(int i = 0; i < ArraySize(gStates); i++)
      if(gStates[i].ticket == ticket) return i;
   int n = ArraySize(gStates);
   ArrayResize(gStates, n + 1);
   gStates[n].ticket = ticket;
   gStates[n].tp1 = false;
   gStates[n].tp2 = false;
   gStates[n].tp3 = false;
   gStates[n].beDone = false;
   return n;
}

//+------------------------------------------------------------------+
double ATRValue()
{
   int h = iATR(gSym, ATR_TF, ATR_Period);
   if(h == INVALID_HANDLE) return 0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h, 0, 1, 2, buf) < 1) { IndicatorRelease(h); return 0; }
   double v = buf[0];
   IndicatorRelease(h);
   return v;
}

double ATR_H1()
{
   int h = iATR(gSym, PERIOD_H1, ATR_Period);
   if(h == INVALID_HANDLE) return 0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h, 0, 1, 2, buf) < 1) { IndicatorRelease(h); return 0; }
   double v = buf[0];
   IndicatorRelease(h);
   return v;
}

//+------------------------------------------------------------------+
bool SpreadOK()
{
   if(!UseSpreadFilter) return true;
   long sp = SymbolInfoInteger(gSym, SYMBOL_SPREAD);
   if(gBaselineSpread <= 0) return true;
   return (double)sp <= gBaselineSpread * MaxSpreadMult;
}

//+------------------------------------------------------------------+
bool SessionOK()
{
   if(!UseSessionFilter) return true;
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   if(BlockFridayAfter && t.day_of_week == 5 && t.hour >= FridayCutoffGMT)
      return false;
   int h = t.hour;
   if(SessionStartGMT < SessionEndGMT)
      return (h >= SessionStartGMT && h < SessionEndGMT);
   // window across midnight (rare)
   return (h >= SessionStartGMT || h < SessionEndGMT);
}

//+------------------------------------------------------------------+
bool IsNewsTime()
{
   if(!UseNewsFilter) return false;
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   int cur = t.hour * 60 + t.min;

   int nh[3] = {13, 19, 13};
   int nm[3] = {30, 0, 30};
   int nd[3] = {5, 3, 3}; // Fri / Wed / Wed (GMT placeholders)

   for(int i = 0; i < 3; i++)
   {
      if(t.day_of_week != nd[i]) continue;
      int nmin = nh[i] * 60 + nm[i];
      if(cur >= nmin - NewsMinutesBefore && cur <= nmin + NewsMinutesAfter)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void SaveState()
{
   int fh = FileOpen(StateFileName, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(fh == INVALID_HANDLE) return;
   FileWriteString(fh, DoubleToString(gDayStartBalance, 2) + "\n");
   FileWriteString(fh, TimeToString(gLastDayCheck) + "\n");
   FileWriteString(fh, gDailyPaused ? "1" : "0");
   FileClose(fh);
}

void LoadState()
{
   if(ForceResetDaily)
   {
      gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      gLastDayCheck    = TimeCurrent();
      gDailyPaused     = false;
      SaveState();
      return;
   }
   if(!FileIsExist(StateFileName, FILE_COMMON))
   {
      gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      gLastDayCheck     = TimeCurrent();
      gDailyPaused      = false;
      SaveState();
      return;
   }
   int fh = FileOpen(StateFileName, FILE_READ | FILE_TXT | FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      return;
   }
   double savedBal = StringToDouble(FileReadString(fh));
   datetime savedTm = StringToTime(FileReadString(fh));
   string lim = FileReadString(fh);
   FileClose(fh);

   MqlDateTime n, s;
   TimeToStruct(TimeCurrent(), n);
   TimeToStruct(savedTm, s);
   if(n.day == s.day && n.mon == s.mon && n.year == s.year)
   {
      gDayStartBalance = savedBal;
      gLastDayCheck    = savedTm;
      gDailyPaused     = (lim == "1");
   }
   else
   {
      gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      gLastDayCheck    = TimeCurrent();
      gDailyPaused     = false;
      SaveState();
   }
}

void CheckDailyLoss()
{
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(gLastDayCheck, last);
   if(now.day != last.day || now.mon != last.mon || now.year != last.year)
   {
      gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      gLastDayCheck    = TimeCurrent();
      gDailyPaused     = false;
      SaveState();
   }
   if(gDayStartBalance <= 0) return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct = (gDayStartBalance - eq) / gDayStartBalance * 100.0;
   if(lossPct >= MaxDailyLossPct && !gDailyPaused)
   {
      gDailyPaused = true;
      SaveState();
      // close our symbol positions only
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Symbol() != gSym || posInfo.Magic() != MagicNumber) continue;
         trade.PositionClose(posInfo.Ticket());
      }
      Print("XAU_Unified: daily loss limit hit — flat and paused today.");
   }
}

//+------------------------------------------------------------------+
double CalcLot(double slDistancePrice)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance * RiskPercent / 100.0;
   double tv = SymbolInfoDouble(gSym, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(gSym, SYMBOL_TRADE_TICK_SIZE);
   double pt = SymbolInfoDouble(gSym, SYMBOL_POINT);
   double minLot = SymbolInfoDouble(gSym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(gSym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(gSym, SYMBOL_VOLUME_STEP);
   if(slDistancePrice <= 0 || tv <= 0 || ts <= 0 || pt <= 0) return minLot;

   double slPoints = slDistancePrice / pt;
   double lossPerLot = slPoints * pt / ts * tv;
   if(lossPerLot <= 0) return minLot;
   double lot = riskAmt / lossPerLot;
   lot = MathFloor(lot / step) * step;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   if(MaxLotCap > 0) lot = MathMin(lot, MaxLotCap);
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
bool IsBullM5()
{
   double o1 = iOpen(gSym, PERIOD_M5, 1), c1 = iClose(gSym, PERIOD_M5, 1);
   double o2 = iOpen(gSym, PERIOD_M5, 2), c2 = iClose(gSym, PERIOD_M5, 2);
   double l1 = iLow(gSym, PERIOD_M5, 1);
   bool engulf = (c2 < o2) && (c1 > o1) && (c1 > o2) && (o1 < c2);
   double body = MathAbs(c1 - o1);
   double tail = o1 - l1;
   bool pin = (body > 0 && tail >= body * 2 && c1 > o1);
   return engulf || pin;
}

bool IsBearM5()
{
   double o1 = iOpen(gSym, PERIOD_M5, 1), c1 = iClose(gSym, PERIOD_M5, 1);
   double o2 = iOpen(gSym, PERIOD_M5, 2), c2 = iClose(gSym, PERIOD_M5, 2);
   double h1 = iHigh(gSym, PERIOD_M5, 1);
   bool engulf = (c2 > o2) && (c1 < o1) && (c1 < o2) && (o1 > c2);
   double body = MathAbs(c1 - o1);
   double wick = h1 - o1;
   bool pin = (body > 0 && wick >= body * 2 && c1 < o1);
   return engulf || pin;
}

//+------------------------------------------------------------------+
void BumpTradeDayIfNeeded()
{
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   int id = t.year * 10000 + t.mon * 100 + t.day;
   if(gTradeDayId != id)
   {
      gTradeDayId  = id;
      gTradesToday = 0;
   }
}

//+------------------------------------------------------------------+
bool EntryCooldownOk()
{
   if(MinM5BarsBetweenTrades <= 0) return true;
   if(gLastEntryM5BarTime == 0) return true;
   int sh = iBarShift(gSym, PERIOD_M5, gLastEntryM5BarTime, false);
   if(sh < 0) return true;
   return (sh >= MinM5BarsBetweenTrades);
}

//+------------------------------------------------------------------+
double GetADXValue(const ENUM_TIMEFRAMES tf)
{
   if(!UseADXFilter) return 999.0;
   int adxH = iADX(gSym, tf, ADX_Period);
   if(adxH == INVALID_HANDLE) return 0;
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(adxH, 0, 1, 2, adx) < 2) { IndicatorRelease(adxH); return 0; }
   IndicatorRelease(adxH);
   return adx[0];
}

//+------------------------------------------------------------------+
bool H4Trend(bool &bull, bool &bear)
{
   int h4 = iMA(gSym, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(h4 == INVALID_HANDLE) return false;
   double e4[];
   ArraySetAsSeries(e4, true);
   if(CopyBuffer(h4, 0, 1, 2, e4) < 1) { IndicatorRelease(h4); return false; }
   IndicatorRelease(h4);
   double c4 = iClose(gSym, PERIOD_H4, 1);
   bull = c4 > e4[0];
   bear = c4 < e4[0];
   return true;
}

//+------------------------------------------------------------------+
bool H1PullbackOk(const bool forBuy)
{
   double atrH1 = ATR_H1();
   if(atrH1 <= 0) return false;
   int h1e = iMA(gSym, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(h1e == INVALID_HANDLE) return false;
   double e1[];
   ArraySetAsSeries(e1, true);
   if(CopyBuffer(h1e, 0, 1, 2, e1) < 1) { IndicatorRelease(h1e); return false; }
   IndicatorRelease(h1e);
   double c1h = iClose(gSym, PERIOD_H1, 1);
   double dist = MathAbs(c1h - e1[0]);
   if(dist > Pullback_ATRMult * atrH1) return false;
   if(forBuy)  return (c1h > e1[0]);
   return (c1h < e1[0]);
}

//+------------------------------------------------------------------+
bool LoadM5Core(double &bf[], double &bs[], double &r[])
{
   ArrayResize(bf, 2);
   ArrayResize(bs, 2);
   ArrayResize(r, 2);
   ArraySetAsSeries(bf, true);
   ArraySetAsSeries(bs, true);
   ArraySetAsSeries(r, true);
   int emaF = iMA(gSym, PERIOD_M5, M5_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   int emaS = iMA(gSym, PERIOD_M5, M5_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   int rsiH = iRSI(gSym, PERIOD_M5, M5_RSI_Period, PRICE_CLOSE);
   if(emaF == INVALID_HANDLE || emaS == INVALID_HANDLE || rsiH == INVALID_HANDLE) return false;
   if(CopyBuffer(emaF, 0, 1, 2, bf) < 2) { IndicatorRelease(emaF); IndicatorRelease(emaS); IndicatorRelease(rsiH); return false; }
   if(CopyBuffer(emaS, 0, 1, 2, bs) < 2) { IndicatorRelease(emaF); IndicatorRelease(emaS); IndicatorRelease(rsiH); return false; }
   if(CopyBuffer(rsiH, 0, 1, 2, r) < 2) { IndicatorRelease(emaF); IndicatorRelease(emaS); IndicatorRelease(rsiH); return false; }
   IndicatorRelease(emaF);
   IndicatorRelease(emaS);
   IndicatorRelease(rsiH);
   return true;
}

//+------------------------------------------------------------------+
int GetSignalStrict()
{
   double atr = ATRValue();
   if(atr < ATR_MinFilter) return 0;

   bool bullH4, bearH4;
   if(!H4Trend(bullH4, bearH4)) return 0;

   double atrH1 = ATR_H1();
   if(atrH1 <= 0) return 0;
   int h1e = iMA(gSym, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(h1e == INVALID_HANDLE) return 0;
   double e1[];
   ArraySetAsSeries(e1, true);
   if(CopyBuffer(h1e, 0, 1, 2, e1) < 1) { IndicatorRelease(h1e); return 0; }
   IndicatorRelease(h1e);
   double c1h = iClose(gSym, PERIOD_H1, 1);
   double dist = MathAbs(c1h - e1[0]);
   if(dist > Pullback_ATRMult * atrH1) return 0;
   bool priceAbove = c1h > e1[0];
   bool priceBelow = c1h < e1[0];

   double adxH1 = GetADXValue(PERIOD_H1);
   if(UseADXFilter && adxH1 < ADX_MinLevel) return 0;

   double bf[], bs[], r[];
   if(!LoadM5Core(bf, bs, r)) return 0;

   bool crossUp = (r[1] < M5_RSI_Neutral && r[0] >= M5_RSI_Neutral);
   bool crossDn = (r[1] > M5_RSI_Neutral && r[0] <= M5_RSI_Neutral);

   if(bullH4 && priceAbove && bf[0] > bs[0] && crossUp && IsBullM5()) return 1;
   if(bearH4 && priceBelow && bf[0] < bs[0] && crossDn && IsBearM5()) return -1;
   return 0;
}

//+------------------------------------------------------------------+
int GetSignalModerate()
{
   double atr = ATRValue();
   if(atr < ATR_MinFilter) return 0;

   bool bullH4, bearH4;
   if(!H4Trend(bullH4, bearH4)) return 0;

   if(UseH1PullbackFilter)
   {
      if(bullH4 && !H1PullbackOk(true)) return 0;
      if(bearH4 && !H1PullbackOk(false)) return 0;
   }

   double adxV = GetADXValue(ADX_Timeframe);
   if(UseADXFilter && adxV < ADX_MinLevel) return 0;

   double bf[], bs[], r[];
   if(!LoadM5Core(bf, bs, r)) return 0;

   bool crossUp = (r[1] < M5_RSI_Neutral && r[0] >= M5_RSI_Neutral);
   bool crossDn = (r[1] > M5_RSI_Neutral && r[0] <= M5_RSI_Neutral);
   bool rsiSlopeBuy  = (r[0] > 40.0 && r[0] < 62.0 && r[0] > r[1]);
   bool rsiSlopeSell = (r[0] > 38.0 && r[0] < 60.0 && r[0] < r[1]);

   if(bullH4 && bf[0] > bs[0] && (crossUp || rsiSlopeBuy))
   {
      if(RequireM5CandlePattern && !IsBullM5()) return 0;
      return 1;
   }
   if(bearH4 && bf[0] < bs[0] && (crossDn || rsiSlopeSell))
   {
      if(RequireM5CandlePattern && !IsBearM5()) return 0;
      return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
int GetSignalFrequent()
{
   double atr = ATRValue();
   if(atr < ATR_MinFilter) return 0;

   bool bullH4, bearH4;
   if(!H4Trend(bullH4, bearH4)) return 0;

   double adxV = GetADXValue(ADX_Timeframe);
   if(UseADXFilter && adxV < ADX_MinLevel * 0.85) return 0;

   double bf[], bs[], r[];
   if(!LoadM5Core(bf, bs, r)) return 0;

   bool crossBuy  = (bf[1] <= bs[1] && bf[0] > bs[0]);
   bool crossSell = (bf[1] >= bs[1] && bf[0] < bs[0]);

   if(bullH4 && crossBuy && r[0] > 38.0 && r[0] < 68.0)
   {
      if(RequireM5CandlePattern && !IsBullM5()) return 0;
      return 1;
   }
   if(bearH4 && crossSell && r[0] > 32.0 && r[0] < 62.0)
   {
      if(RequireM5CandlePattern && !IsBearM5()) return 0;
      return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
// Return 1 = buy, -1 = sell, 0 = none
int GetSignal()
{
   switch(SignalProfile)
   {
      case PROFILE_STRICT:        return GetSignalStrict();
      case PROFILE_M5_FREQUENT:   return GetSignalFrequent();
      case PROFILE_M5_MODERATE:
      default:                    return GetSignalModerate();
   }
}

//+------------------------------------------------------------------+
int CountOurPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == gSym && posInfo.Magic() == MagicNumber) c++;
   }
   return c;
}

//+------------------------------------------------------------------+
void PartialCloseVol(ulong ticket, double pct, double curVol)
{
   double step = SymbolInfoDouble(gSym, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(gSym, SYMBOL_VOLUME_MIN);
   double v = MathFloor((curVol * pct / 100.0) / step) * step;
   if(v < minL) return;
   // never close full by mistake
   if(v >= curVol) v = MathFloor((curVol - minL) / step) * step;
   if(v < minL) return;
   trade.PositionClosePartial(ticket, v);
}

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   double atr = ATRValue();
   if(atr <= 0) return;
   int dg = (int)SymbolInfoInteger(gSym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(gSym, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != gSym || posInfo.Magic() != MagicNumber) continue;

      ulong  ticket = posInfo.Ticket();
      long   typ    = posInfo.PositionType();
      double open   = posInfo.PriceOpen();
      double vol    = posInfo.Volume();
      double sl     = posInfo.StopLoss();
      double tp     = posInfo.TakeProfit();
      double bid    = SymbolInfoDouble(gSym, SYMBOL_BID);
      double ask    = SymbolInfoDouble(gSym, SYMBOL_ASK);

      int ix = StateIndex(ticket);

      double profPrice = (typ == POSITION_TYPE_BUY) ? (bid - open) : (open - ask);

      double t1 = atr * ATR_TP1_Multi;
      double t2 = atr * ATR_TP2_Multi;
      double t3 = atr * ATR_TP3_Multi;
      double beTrig = atr * ATR_BE_Multi;

      // Early breakeven (optional path if TP1 not yet done)
      if(!gStates[ix].tp1 && !gStates[ix].beDone && profPrice >= beTrig)
      {
         if(typ == POSITION_TYPE_BUY)
         {
            double be = NormalizeDouble(open + BE_OffsetPrice, dg);
            if(sl < be && trade.PositionModify(ticket, be, tp))
               gStates[ix].beDone = true;
         }
         else
         {
            double be = NormalizeDouble(open - BE_OffsetPrice, dg);
            if((sl > be || sl == 0) && trade.PositionModify(ticket, be, tp))
               gStates[ix].beDone = true;
         }
      }

      if(profPrice >= t1 && !gStates[ix].tp1)
      {
         PartialCloseVol(ticket, TP1_ClosePct, vol);
         gStates[ix].tp1 = true;
         if(MoveBE_AfterTP1)
         {
            if(typ == POSITION_TYPE_BUY)
            {
               double be = NormalizeDouble(open + BE_OffsetPrice, dg);
               trade.PositionModify(ticket, be, tp);
            }
            else
            {
               double be = NormalizeDouble(open - BE_OffsetPrice, dg);
               trade.PositionModify(ticket, be, tp);
            }
            gStates[ix].beDone = true;
         }
      }

      // refresh volume after partial
      if(!posInfo.SelectByTicket(ticket)) continue;
      vol = posInfo.Volume();
      sl = posInfo.StopLoss();
      tp = posInfo.TakeProfit();
      bid = SymbolInfoDouble(gSym, SYMBOL_BID);
      ask = SymbolInfoDouble(gSym, SYMBOL_ASK);
      profPrice = (typ == POSITION_TYPE_BUY) ? (bid - open) : (open - ask);

      if(profPrice >= t2 && !gStates[ix].tp2)
      {
         PartialCloseVol(ticket, TP2_ClosePct, vol);
         gStates[ix].tp2 = true;
      }

      if(!posInfo.SelectByTicket(ticket)) continue;
      vol = posInfo.Volume();
      sl = posInfo.StopLoss();
      tp = posInfo.TakeProfit();
      bid = SymbolInfoDouble(gSym, SYMBOL_BID);
      ask = SymbolInfoDouble(gSym, SYMBOL_ASK);
      profPrice = (typ == POSITION_TYPE_BUY) ? (bid - open) : (open - ask);

      if(profPrice >= t3 && !gStates[ix].tp3)
      {
         PartialCloseVol(ticket, TP3_ClosePct, vol);
         gStates[ix].tp3 = true;
      }

      // Trailing after TP3
      if(!gStates[ix].tp3) continue;
      if(!posInfo.SelectByTicket(ticket)) continue;
      sl = posInfo.StopLoss();
      tp = posInfo.TakeProfit();
      bid = SymbolInfoDouble(gSym, SYMBOL_BID);
      ask = SymbolInfoDouble(gSym, SYMBOL_ASK);

      double gap = atr * ATR_Trail_Multi;
      if(typ == POSITION_TYPE_BUY)
      {
         double trail = NormalizeDouble(bid - gap, dg);
         double openBE = open + BE_OffsetPrice;
         if(sl >= openBE && trail > sl + MinTrailMovePrice)
            trade.PositionModify(ticket, trail, tp);
      }
      else
      {
         double trail = NormalizeDouble(ask + gap, dg);
         double openBE = open - BE_OffsetPrice;
         if((sl <= openBE || sl == 0) && (trail < sl - MinTrailMovePrice || sl == 0))
            trade.PositionModify(ticket, trail, tp);
      }
   }
}

//+------------------------------------------------------------------+
void OpenPosition(int dir)
{
   double atr = ATRValue();
   if(atr <= 0) return;
   int dg = (int)SymbolInfoInteger(gSym, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(gSym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(gSym, SYMBOL_BID);
   double slDist = atr * ATR_SL_Multi;
   double lot = CalcLot(slDist);

   if(dir == 1)
   {
      double sl = NormalizeDouble(ask - slDist, dg);
      double tp = NormalizeDouble(ask + atr * ATR_TP_Far_Multi, dg);
      if(trade.Buy(lot, gSym, ask, sl, tp, "XAU_Unified_BUY"))
      {
         gLastEntryM5BarTime = iTime(gSym, PERIOD_M5, 0);
         gTradesToday++;
         Print("XAU_Unified BUY lot=", lot, " SL=", sl, " TP=", tp);
      }
   }
   else
   {
      double sl = NormalizeDouble(bid + slDist, dg);
      double tp = NormalizeDouble(bid - atr * ATR_TP_Far_Multi, dg);
      if(trade.Sell(lot, gSym, bid, sl, tp, "XAU_Unified_SELL"))
      {
         gLastEntryM5BarTime = iTime(gSym, PERIOD_M5, 0);
         gTradesToday++;
         Print("XAU_Unified SELL lot=", lot, " SL=", sl, " TP=", tp);
      }
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   gSym = TradeSymbol;
   StringTrimLeft(gSym);
   StringTrimRight(gSym);
   if(!SymbolSelect(gSym, true))
   {
      Print("XAU_Unified: symbol not found ", gSym);
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);

   gBaselineSpread = (double)SymbolInfoInteger(gSym, SYMBOL_SPREAD);
   LoadState();

   Print("XAU_Unified_v1.01 | ", gSym, " | profile=", (int)SignalProfile,
         " | baseline spread=", gBaselineSpread);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckDailyLoss();
   BumpTradeDayIfNeeded();
   ManageOpenPositions();

   if(gDailyPaused) return;
   if(IsNewsTime()) return;
   if(!SessionOK()) return;
   if(!SpreadOK()) return;
   if(CountOurPositions() >= MaxOpenPositions) return;

   if(MaxTradesPerDay > 0 && gTradesToday >= MaxTradesPerDay) return;

   datetime m5 = iTime(gSym, PERIOD_M5, 0);
   if(m5 == gLastM5Bar) return;
   gLastM5Bar = m5;

   if(!EntryCooldownOk()) return;

   int sig = GetSignal();
   if(sig == 0) return;
   OpenPosition(sig);
}

//+------------------------------------------------------------------+
