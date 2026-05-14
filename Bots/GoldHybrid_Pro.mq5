//+------------------------------------------------------------------+
//|                                        GoldHybrid_Pro.mq5       |
//|                   XAUUSD Scalp + Swing Hybrid Bot               |
//|                    24/5 | Smart Entry | Capital Protection       |
//+------------------------------------------------------------------+
#property copyright   "GoldHybrid Pro"
#property version     "1.00"
#property description "XAUUSD Scalp+Swing | 24/5 | No daily limit"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "=== Money Management ==="
input double RiskPercent      = 0.5;   // Risk % per trade (conservative)
input double MaxLotSize       = 3.0;   // Max lot size
input int    MaxScalpTrades   = 2;     // Max simultaneous scalp trades
input int    MaxSwingTrades   = 1;     // Max simultaneous swing trades

input group "=== Scalp Settings (M5) ==="
input ENUM_TIMEFRAMES TF_Scalp   = PERIOD_M5;  // Scalp timeframe
input int    Scalp_EMA_Fast      = 8;    // Fast EMA
input int    Scalp_EMA_Slow      = 21;   // Slow EMA
input int    Scalp_RSI_Period    = 7;    // RSI period
input double Scalp_RSI_OB        = 70.0; // RSI overbought
input double Scalp_RSI_OS        = 30.0; // RSI oversold
input int    Scalp_ATR_Period    = 10;   // ATR period
input double Scalp_ATR_SL        = 1.5;  // SL = ATR x this (wider, avoid SL hunting)
input double Scalp_RR            = 2.0;  // Risk:Reward for scalp
input int    Scalp_MinBars       = 4;    // Min bars between scalp trades

input group "=== Swing Settings (H1) ==="
input ENUM_TIMEFRAMES TF_Swing   = PERIOD_H1;  // Swing timeframe
input int    Swing_EMA_Fast      = 21;   // Fast EMA
input int    Swing_EMA_Slow      = 50;   // Slow EMA
input int    Swing_EMA_Trend     = 200;  // Trend EMA
input int    Swing_RSI_Period    = 14;   // RSI period
input double Swing_RSI_OB        = 65.0; // RSI overbought
input double Swing_RSI_OS        = 35.0; // RSI oversold
input int    Swing_ATR_Period    = 14;   // ATR period
input double Swing_ATR_SL        = 1.8;  // SL = ATR x this
input double Swing_RR            = 3.0;  // Risk:Reward for swing (higher)

input group "=== Trade Management ==="
input bool   UseBreakEven        = true; // Breakeven
input double BE_Trigger_Scalp    = 0.7;  // BE trigger scalp (ATR x)
input double BE_Trigger_Swing    = 1.0;  // BE trigger swing (ATR x)
input bool   UseTrailing         = true; // Trailing stop
input double Trail_Scalp         = 0.5;  // Trail scalp (ATR x)
input double Trail_Swing         = 1.2;  // Trail swing (ATR x)

input group "=== Filters ==="
input bool   AvoidNews           = true; // Avoid news times
input int    News_Hour1          = 8;    // London open GMT
input int    News_Hour2          = 13;   // NY open GMT
input int    News_Hour3          = 15;   // US data GMT
input bool   SessionBoost        = false; // Session boost OFF (safer)

input group "=== Drawdown Protection ==="
input double MaxDailyLossPct     = 3.0;   // Max daily loss % before stopping
input double MaxTotalDrawdownPct = 10.0;  // Max total drawdown % before stopping

input group "=== EA Settings ==="
input int    MagicScalp          = 20250416;
input int    MagicSwing          = 20250417;
input int    Slippage            = 50;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

// === SCALP HANDLES (M5) ===
int hs_EMA_Fast, hs_EMA_Slow;
int hs_RSI, hs_ATR, hs_Stoch;

// === SWING HANDLES (H1) ===
int hw_EMA_Fast, hw_EMA_Slow, hw_EMA_Trend;
int hw_RSI, hw_ATR, hw_MACD;

// === SCALP BUFFERS ===
double bs_EMA_Fast[], bs_EMA_Slow[];
double bs_RSI[], bs_ATR[];
double bs_Stoch_K[], bs_Stoch_D[];

// === SWING BUFFERS ===
double bw_EMA_Fast[], bw_EMA_Slow[], bw_EMA_Trend[];
double bw_RSI[], bw_ATR[];
double bw_MACD_Main[], bw_MACD_Sig[];

// State
datetime lastBarM5     = 0;
datetime lastBarH1     = 0;
int      scalpBars     = 0;
int      swingTrendDir = 0;

// Drawdown protection
double   startEquity   = 0;
double   dayStartEquity= 0;
datetime lastDayReset  = 0;
bool     protectionHit = false;

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Scalp handles M5
   hs_EMA_Fast = iMA(_Symbol, TF_Scalp, Scalp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hs_EMA_Slow = iMA(_Symbol, TF_Scalp, Scalp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hs_RSI      = iRSI(_Symbol, TF_Scalp, Scalp_RSI_Period, PRICE_CLOSE);
   hs_ATR      = iATR(_Symbol, TF_Scalp, Scalp_ATR_Period);
   hs_Stoch    = iStochastic(_Symbol, TF_Scalp, 5, 3, 3, MODE_SMA, STO_LOWHIGH);

   // Swing handles H1
   hw_EMA_Fast  = iMA(_Symbol, TF_Swing, Swing_EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   hw_EMA_Slow  = iMA(_Symbol, TF_Swing, Swing_EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   hw_EMA_Trend = iMA(_Symbol, TF_Swing, Swing_EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   hw_RSI       = iRSI(_Symbol, TF_Swing, Swing_RSI_Period, PRICE_CLOSE);
   hw_ATR       = iATR(_Symbol, TF_Swing, Swing_ATR_Period);
   hw_MACD      = iMACD(_Symbol, TF_Swing, 12, 26, 9, PRICE_CLOSE);

   if(hs_EMA_Fast == INVALID_HANDLE || hs_EMA_Slow == INVALID_HANDLE ||
      hs_RSI      == INVALID_HANDLE || hs_ATR      == INVALID_HANDLE ||
      hs_Stoch    == INVALID_HANDLE || hw_EMA_Fast == INVALID_HANDLE ||
      hw_EMA_Slow == INVALID_HANDLE || hw_EMA_Trend== INVALID_HANDLE ||
      hw_RSI      == INVALID_HANDLE || hw_ATR      == INVALID_HANDLE ||
      hw_MACD     == INVALID_HANDLE)
     {
      Print("❌ ERROR: Indicators failed!");
      return INIT_FAILED;
     }

   ArraySetAsSeries(bs_EMA_Fast,  true);
   ArraySetAsSeries(bs_EMA_Slow,  true);
   ArraySetAsSeries(bs_RSI,       true);
   ArraySetAsSeries(bs_ATR,       true);
   ArraySetAsSeries(bs_Stoch_K,   true);
   ArraySetAsSeries(bs_Stoch_D,   true);
   ArraySetAsSeries(bw_EMA_Fast,  true);
   ArraySetAsSeries(bw_EMA_Slow,  true);
   ArraySetAsSeries(bw_EMA_Trend, true);
   ArraySetAsSeries(bw_RSI,       true);
   ArraySetAsSeries(bw_ATR,       true);
   ArraySetAsSeries(bw_MACD_Main, true);
   ArraySetAsSeries(bw_MACD_Sig,  true);

   startEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStartEquity = startEquity;
   Print("✅ GoldHybrid Pro Ready | Scalp(M5) + Swing(H1) | 24/5");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   int handles[] = {hs_EMA_Fast, hs_EMA_Slow, hs_RSI, hs_ATR, hs_Stoch,
                    hw_EMA_Fast, hw_EMA_Slow, hw_EMA_Trend, hw_RSI, hw_ATR, hw_MACD};
   for(int i = 0; i < ArraySize(handles); i++)
      IndicatorRelease(handles[i]);
  }

//+------------------------------------------------------------------+
//| MAIN TICK                                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Check drawdown protection first
   if(!DrawdownCheck()) return;

   // Manage all positions every tick
   ManagePositions();

   // === H1 bar: swing logic ===
   datetime curH1 = iTime(_Symbol, TF_Swing, 0);
   if(curH1 != lastBarH1)
     {
      lastBarH1 = curH1;
      if(LoadSwingBuffers())
        {
         UpdateSwingTrend();
         if(!IsNewsTime() && CountPositions(MagicSwing) < MaxSwingTrades)
            CheckSwingEntry();
        }
     }

   // === M5 bar: scalp logic ===
   datetime curM5 = iTime(_Symbol, TF_Scalp, 0);
   if(curM5 != lastBarM5)
     {
      lastBarM5 = curM5;
      scalpBars++;

      if(LoadScalpBuffers())
        {
         if(!IsNewsTime() &&
            CountPositions(MagicScalp) < MaxScalpTrades &&
            scalpBars >= Scalp_MinBars)
            CheckScalpEntry();
        }
     }
  }

//+------------------------------------------------------------------+
//| LOAD SCALP BUFFERS (M5)                                          |
//+------------------------------------------------------------------+
bool LoadScalpBuffers()
  {
   if(CopyBuffer(hs_EMA_Fast, 0, 0, 5, bs_EMA_Fast) < 5) return false;
   if(CopyBuffer(hs_EMA_Slow, 0, 0, 5, bs_EMA_Slow) < 5) return false;
   if(CopyBuffer(hs_RSI,      0, 0, 5, bs_RSI)      < 5) return false;
   if(CopyBuffer(hs_ATR,      0, 0, 5, bs_ATR)      < 5) return false;
   if(CopyBuffer(hs_Stoch,    0, 0, 5, bs_Stoch_K)  < 5) return false;
   if(CopyBuffer(hs_Stoch,    1, 0, 5, bs_Stoch_D)  < 5) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| LOAD SWING BUFFERS (H1)                                          |
//+------------------------------------------------------------------+
bool LoadSwingBuffers()
  {
   if(CopyBuffer(hw_EMA_Fast,  0, 0, 5, bw_EMA_Fast)  < 5) return false;
   if(CopyBuffer(hw_EMA_Slow,  0, 0, 5, bw_EMA_Slow)  < 5) return false;
   if(CopyBuffer(hw_EMA_Trend, 0, 0, 5, bw_EMA_Trend) < 5) return false;
   if(CopyBuffer(hw_RSI,       0, 0, 5, bw_RSI)       < 5) return false;
   if(CopyBuffer(hw_ATR,       0, 0, 5, bw_ATR)       < 5) return false;
   if(CopyBuffer(hw_MACD,      0, 0, 5, bw_MACD_Main) < 5) return false;
   if(CopyBuffer(hw_MACD,      1, 0, 5, bw_MACD_Sig)  < 5) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| UPDATE SWING TREND                                               |
//+------------------------------------------------------------------+
void UpdateSwingTrend()
  {
   double price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ema_trend = bw_EMA_Trend[0];
   double ema_fast  = bw_EMA_Fast[0];
   double ema_slow  = bw_EMA_Slow[0];

   if(price > ema_trend && ema_fast > ema_slow)
      swingTrendDir = 1;
   else if(price < ema_trend && ema_fast < ema_slow)
      swingTrendDir = -1;
   else
      swingTrendDir = 0;
  }

//+------------------------------------------------------------------+
//| SCALP ENTRY - M5                                                 |
//| Fast signals: EMA cross + RSI + Stoch                           |
//+------------------------------------------------------------------+
void CheckScalpEntry()
  {
   double fast0  = bs_EMA_Fast[0], fast1 = bs_EMA_Fast[1];
   double slow0  = bs_EMA_Slow[0], slow1 = bs_EMA_Slow[1];
   double rsi    = bs_RSI[0];
   double atr    = bs_ATR[0];
   double stochK = bs_Stoch_K[0], stochK1 = bs_Stoch_K[1];
   double stochD = bs_Stoch_D[0];

   if(atr <= 0 || swingTrendDir == 0) return;

   double lot = CalcLot(atr * Scalp_ATR_SL, MagicScalp);
   if(SessionBoost) lot = AdjustLotSession(lot);

   // BUY scalp: trend up + EMA cross up + RSI ok + Stoch cross up
   if(swingTrendDir == 1)
     {
      bool emaCross  = (fast1 < slow1 && fast0 > slow0);
      bool rsiOk     = (rsi > 40 && rsi < Scalp_RSI_OB);
      bool stochCross= (stochK1 < stochD && stochK > stochD && stochK < 75);

      if((emaCross || stochCross) && rsiOk)
         OpenTrade(ORDER_TYPE_BUY, atr, lot, MagicScalp,
                   Scalp_ATR_SL, Scalp_RR, "SCALP_BUY");
     }

   // SELL scalp: trend down + EMA cross down + RSI ok + Stoch cross down
   if(swingTrendDir == -1)
     {
      bool emaCross  = (fast1 > slow1 && fast0 < slow0);
      bool rsiOk     = (rsi < 60 && rsi > Scalp_RSI_OS);
      bool stochCross= (stochK1 > stochD && stochK < stochD && stochK > 25);

      if((emaCross || stochCross) && rsiOk)
         OpenTrade(ORDER_TYPE_SELL, atr, lot, MagicScalp,
                   Scalp_ATR_SL, Scalp_RR, "SCALP_SELL");
     }
  }

//+------------------------------------------------------------------+
//| SWING ENTRY - H1                                                 |
//| Strong trend setups with wider SL and higher RR                  |
//+------------------------------------------------------------------+
void CheckSwingEntry()
  {
   if(swingTrendDir == 0) return;

   double fast0  = bw_EMA_Fast[0],  fast1 = bw_EMA_Fast[1];
   double slow0  = bw_EMA_Slow[0],  slow1 = bw_EMA_Slow[1];
   double rsi    = bw_RSI[0];
   double atr    = bw_ATR[0];
   double macd   = bw_MACD_Main[0];
   double msig   = bw_MACD_Sig[0];
   double macd1  = bw_MACD_Main[1];
   double msig1  = bw_MACD_Sig[1];

   if(atr <= 0) return;

   double lot = CalcLot(atr * Swing_ATR_SL, MagicSwing);

   // BUY swing: fresh EMA cross + MACD cross + RSI healthy
   if(swingTrendDir == 1)
     {
      bool emaCross  = (fast1 <= slow1 && fast0 > slow0);
      bool macdCross = (macd1 <= msig1 && macd > msig);
      bool rsiOk     = (rsi > 40 && rsi < Swing_RSI_OB);

      if((emaCross || macdCross) && rsiOk)
         OpenTrade(ORDER_TYPE_BUY, atr, lot, MagicSwing,
                   Swing_ATR_SL, Swing_RR, "SWING_BUY");
     }

   // SELL swing: fresh EMA cross + MACD cross + RSI healthy
   if(swingTrendDir == -1)
     {
      bool emaCross  = (fast1 >= slow1 && fast0 < slow0);
      bool macdCross = (macd1 >= msig1 && macd < msig);
      bool rsiOk     = (rsi < 60 && rsi > Swing_RSI_OS);

      if((emaCross || macdCross) && rsiOk)
         OpenTrade(ORDER_TYPE_SELL, atr, lot, MagicSwing,
                   Swing_ATR_SL, Swing_RR, "SWING_SELL");
     }
  }

//+------------------------------------------------------------------+
//| OPEN TRADE                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double atr, double lot,
               int magic, double slMult, double rrRatio, string comment)
  {
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double slDist = atr * slMult;
   double tpDist = slDist * rrRatio;

   double price, sl, tp;
   if(type == ORDER_TYPE_BUY)
     {
      price = ask;
      sl    = NormalizeDouble(price - slDist, digits);
      tp    = NormalizeDouble(price + tpDist, digits);
     }
   else
     {
      price = bid;
      sl    = NormalizeDouble(price + slDist, digits);
      tp    = NormalizeDouble(price - tpDist, digits);
     }

   if(lot <= 0) return;

   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot, _Symbol, price, sl, tp, comment)
             : trade.Sell(lot, _Symbol, price, sl, tp, comment);

   if(ok)
     {
      if(magic == MagicScalp) scalpBars = 0;
      string mode = (magic == MagicScalp) ? "⚡ SCALP" : "🌊 SWING";
      Print("✅ ", mode, " | ", EnumToString(type),
            " | Lot: ", lot,
            " | SL: ", DoubleToString(sl, digits),
            " | TP: ", DoubleToString(tp, digits));
     }
   else
      Print("❌ Failed [", comment, "]: ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| CALCULATE LOT                                                     |
//+------------------------------------------------------------------+
double CalcLot(double slDistance, int magic)
  {
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt  = equity * (RiskPercent / 100.0);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), MaxLotSize);

   if(tickVal == 0 || tickSize == 0 || slDistance == 0) return minLot;

   double valPerLot = (slDistance / tickSize) * tickVal;
   if(valPerLot <= 0) return minLot;

   double lot = riskAmt / valPerLot;
   lot = MathFloor(lot / lotStep) * lotStep;
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lot)), 2);
  }

//+------------------------------------------------------------------+
//| ADJUST LOT FOR SESSION                                           |
//+------------------------------------------------------------------+
double AdjustLotSession(double lot)
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(h >= 7 && h < 12)       lot *= 1.2; // London
   else if(h >= 13 && h < 17) lot *= 1.2; // New York
   else if(h >= 0 && h < 6)   lot *= 0.7; // Asian (low vol)

   lot = MathFloor(lot / lotStep) * lotStep;
   return NormalizeDouble(MathMax(minLot, lot), 2);
  }

//+------------------------------------------------------------------+
//| MANAGE POSITIONS - BE + TRAILING FOR BOTH SCALP AND SWING       |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   // Load ATR for both timeframes
   double atrScalp = 0, atrSwing = 0;
   double tmpATR[];
   ArraySetAsSeries(tmpATR, true);

   if(CopyBuffer(hs_ATR, 0, 0, 3, tmpATR) >= 3) atrScalp = tmpATR[0];
   if(CopyBuffer(hw_ATR, 0, 0, 3, tmpATR) >= 3) atrSwing = tmpATR[0];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;

      int    magic  = (int)posInfo.Magic();
      if(magic != MagicScalp && magic != MagicSwing) continue;

      bool   isScalp = (magic == MagicScalp);
      double atr     = isScalp ? atrScalp : atrSwing;
      double beTrig  = isScalp ? BE_Trigger_Scalp : BE_Trigger_Swing;
      double trailM  = isScalp ? Trail_Scalp : Trail_Swing;

      if(atr <= 0) continue;

      double open   = posInfo.PriceOpen();
      double curSL  = posInfo.StopLoss();
      double curTP  = posInfo.TakeProfit();
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      ulong  ticket = posInfo.Ticket();

      trade.SetExpertMagicNumber(magic);

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double beSL    = NormalizeDouble(open + _Point * 3, digits);
         double trailSL = NormalizeDouble(bid - atr * trailM, digits);

         if(UseBreakEven && bid >= open + atr * beTrig && curSL < beSL)
            trade.PositionModify(ticket, beSL, curTP);
         else if(UseTrailing && bid > open + atr * trailM && trailSL > curSL)
            trade.PositionModify(ticket, trailSL, curTP);
        }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double beSL    = NormalizeDouble(open - _Point * 3, digits);
         double trailSL = NormalizeDouble(ask + atr * trailM, digits);

         if(UseBreakEven && ask <= open - atr * beTrig && (curSL > beSL || curSL == 0))
            trade.PositionModify(ticket, beSL, curTP);
         else if(UseTrailing && ask < open - atr * trailM && (trailSL < curSL || curSL == 0))
            trade.PositionModify(ticket, trailSL, curTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| COUNT POSITIONS BY MAGIC                                         |
//+------------------------------------------------------------------+
int CountPositions(int magic)
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if((int)posInfo.Magic() == magic && posInfo.Symbol() == _Symbol)
            count++;
   return count;
  }

//+------------------------------------------------------------------+
//| NEWS TIME CHECK                                                   |
//+------------------------------------------------------------------+
bool IsNewsTime()
  {
   if(!AvoidNews) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int totalMin = dt.hour * 60 + dt.min;
   int news[3];
   news[0] = News_Hour1 * 60;
   news[1] = News_Hour2 * 60;
   news[2] = News_Hour3 * 60;
   for(int i = 0; i < 3; i++)
      if(totalMin >= news[i] - 20 && totalMin <= news[i] + 20)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| DRAWDOWN PROTECTION - Circuit Breaker                           |
//+------------------------------------------------------------------+
bool DrawdownCheck()
  {
   // Reset daily tracker
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime todayStart = StringToTime(
      IntegerToString(dt.year)+"."+IntegerToString(dt.mon)+"."+IntegerToString(dt.day));
   if(todayStart > lastDayReset)
     {
      lastDayReset   = todayStart;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      protectionHit  = false;
      Print("📅 New day | Day equity reset: $", DoubleToString(dayStartEquity, 2));
     }

   if(protectionHit) return false;

   double equity       = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossPct = ((equity - dayStartEquity) / dayStartEquity) * 100.0;
   double totalDDPct   = ((equity - startEquity)    / startEquity)    * 100.0;

   // Daily loss exceeded
   if(dailyLossPct <= -MaxDailyLossPct)
     {
      protectionHit = true;
      CloseAll();
      Print("🛑 DAILY LOSS LIMIT HIT: ", DoubleToString(dailyLossPct, 2),
            "% | Trading paused until tomorrow");
      return false;
     }

   // Total drawdown exceeded
   if(totalDDPct <= -MaxTotalDrawdownPct)
     {
      protectionHit = true;
      CloseAll();
      Print("🛑 MAX DRAWDOWN HIT: ", DoubleToString(totalDDPct, 2),
            "% | EA stopped - Please review settings");
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS                                              |
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol)
            if((int)posInfo.Magic() == MagicScalp || (int)posInfo.Magic() == MagicSwing)
               trade.PositionClose(posInfo.Ticket());
     }
  }

//+------------------------------------------------------------------+
//| ON TRADE - LOGGING                                               |
//+------------------------------------------------------------------+
void OnTrade()
  {
   static int lastTotal = 0;
   int currentTotal = HistoryDealsTotal();
   if(currentTotal <= lastTotal) return;
   lastTotal = currentTotal;

   if(!HistorySelect(0, TimeCurrent())) return;
   ulong ticket = HistoryDealGetTicket(currentTotal - 1);
   if(ticket == 0) return;

   int dealMagic = (int)HistoryDealGetInteger(ticket, DEAL_MAGIC);
   if(dealMagic != MagicScalp && dealMagic != MagicSwing) return;

   long   dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
   long   dealType  = HistoryDealGetInteger(ticket, DEAL_TYPE);
   double profit    = HistoryDealGetDouble(ticket, DEAL_PROFIT);
   double swap      = HistoryDealGetDouble(ticket, DEAL_SWAP);
   double comm      = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   double net       = profit + swap + comm;
   double price     = HistoryDealGetDouble(ticket, DEAL_PRICE);
   double lotD      = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   string dir       = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
   string mode      = (dealMagic == MagicScalp) ? "⚡ SCALP" : "🌊 SWING";

   if(dealEntry == DEAL_ENTRY_IN)
     {
      Print("┌────────────────────────────────────────");
      Print("│ 📂 ", mode, " OPENED | ", dir);
      Print("│ Lot: ", DoubleToString(lotD, 2),
            " | @", DoubleToString(price, _Digits));
      Print("│ Balance: $", DoubleToString(balance, 2));
      Print("└────────────────────────────────────────");
     }

   if(dealEntry == DEAL_ENTRY_OUT)
     {
      string res  = (net > 0) ? "✅ WIN" : (net < 0) ? "❌ LOSS" : "➖ BE";
      string sign = (net >= 0) ? "+" : "";
      Print("┌────────────────────────────────────────");
      Print("│ 📁 ", mode, " CLOSED | ", res);
      Print("│ Net P&L: $", sign, DoubleToString(net, 2));
      Print("│ Balance: $", DoubleToString(balance, 2),
            " | Equity: $", DoubleToString(equity, 2));
      Print("└────────────────────────────────────────");
     }
  }

//+------------------------------------------------------------------+
//| ON CHART EVENT - Press S for status                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam,
                  const double& dparam, const string& sparam)
  {
   if(id == CHARTEVENT_KEYDOWN && lparam == 83)
     {
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      string session = "Asian 🌏";
      if(dt.hour >= 7  && dt.hour < 12) session = "London 🇬🇧";
      if(dt.hour >= 13 && dt.hour < 17) session = "New York 🇺🇸";

      Print("╔══════════════════════════════════════════╗");
      Print("║       GOLDHYBRID PRO - STATUS            ║");
      Print("╠══════════════════════════════════════════╣");
      Print("║ Balance      : $", DoubleToString(balance, 2));
      Print("║ Equity       : $", DoubleToString(equity, 2));
      Print("║ Float P&L    : $", DoubleToString(equity - balance, 2));
      Print("║ Swing Trend  : ", (swingTrendDir == 1 ? "↑ BULLISH" : swingTrendDir == -1 ? "↓ BEARISH" : "→ NEUTRAL"));
      Print("║ Session      : ", session);
      Print("║ Scalp Trades : ", CountPositions(MagicScalp), " / ", MaxScalpTrades);
      Print("║ Swing Trades : ", CountPositions(MagicSwing), " / ", MaxSwingTrades);
      Print("║ News Zone    : ", (IsNewsTime() ? "⚠️ PAUSED" : "✅ CLEAR"));
      Print("╚══════════════════════════════════════════╝");
     }
  }
//+------------------------------------------------------------------+
