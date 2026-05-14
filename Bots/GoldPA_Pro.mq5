//+------------------------------------------------------------------+
//|                                         GoldPA_Pro.mq5          |
//|              XAUUSD Pure Price Action Bot | 24/5                 |
//|     Strategy: London Breakout + H4 Pullback + Candle Patterns   |
//+------------------------------------------------------------------+
#property copyright   "GoldPA Pro"
#property version     "1.00"
#property description "XAUUSD Price Action | London Breakout + H4 Trend Pullback"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "=== Money Management ==="
input double RiskPercent       = 1.0;   // Risk % per trade
input double MaxLotSize        = 2.0;   // Max lot size
input int    MaxOpenTrades     = 3;     // Max simultaneous trades

input group "=== Strategy 1: London Breakout ==="
input bool   UseBreakout       = true;  // Enable London Breakout strategy
input int    AsianStart_GMT    = 0;     // Asian session start (GMT)
input int    AsianEnd_GMT      = 6;     // Asian session end (GMT)
input int    LondonOpen_GMT    = 7;     // London open (GMT)
input int    LondonClose_GMT   = 17;   // Stop new breakout trades after this hour
input double BreakoutBuffer    = 3.0;  // Extra pips above/below Asian range

input group "=== Strategy 2: H4 Trend Pullback ==="
input bool   UsePullback       = true;  // Enable H4 Pullback strategy
input int    EMA_Fast_H4       = 21;    // Fast EMA H4
input int    EMA_Slow_H4       = 50;    // Slow EMA H4
input int    EMA_Trend_H4      = 200;   // Trend EMA H4
input double FibRetrace_Min    = 0.382; // Min Fibonacci retracement
input double FibRetrace_Max    = 0.618; // Max Fibonacci retracement

input group "=== Candlestick Pattern Filter ==="
input bool   UseCandleFilter   = true;  // Require candle pattern confirmation
input double EngulfMin         = 1.5;   // Engulfing: body ratio min
input double PinBarMin         = 2.0;   // Pin bar: wick/body ratio min

input group "=== Trade Management ==="
input double ATR_Period        = 14;    // ATR period
input double ATR_SL            = 1.5;  // SL = ATR x this
input double RR_Ratio          = 2.5;  // Risk:Reward
input bool   UseBreakEven      = true; // Move SL to breakeven
input double BE_Trigger        = 1.0;  // BE trigger (ATR x)
input bool   UseTrailing       = true; // Trailing stop
input double Trail_ATR         = 1.0;  // Trail (ATR x)

input group "=== Drawdown Protection ==="
input double MaxDailyLoss      = 1.5;  // Max daily loss % → pause trading
input double MaxDrawdown       = 12.0; // Max total drawdown % → stop EA

input group "=== Filters ==="
input bool   AvoidHighSpread   = true; // Avoid high spread (news)
input double MaxSpread         = 40.0; // Max allowed spread in points
input bool   AvoidWeekendEdge  = true; // Avoid Friday close / Monday open

input group "=== EA Settings ==="
input int    MagicNumber       = 20250416;
input int    Slippage          = 30;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

// Handles
int h_ATR_M15, h_ATR_H4;
int h_EMA_Fast, h_EMA_Slow, h_EMA_Trend;

// Buffers
double b_ATR_M15[], b_ATR_H4[];
double b_EMA_Fast[], b_EMA_Slow[], b_EMA_Trend[];

// Asian range (reset daily)
double asianHigh    = 0;
double asianLow     = 0;
bool   asianBuilt   = false;
bool   breakoutDone = false;

// Bar tracking
datetime lastBarM15 = 0;
datetime lastBarH4  = 0;

// Drawdown protection
double   startEquity    = 0;
double   dayStartEquity = 0;
datetime lastDayReset   = 0;
bool     protectionHit  = false;

// H4 trend state
int      h4TrendDir = 0;
double   h4SwingHigh = 0;
double   h4SwingLow  = 0;

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   h_ATR_M15  = iATR(_Symbol, PERIOD_M15, (int)ATR_Period);
   h_ATR_H4   = iATR(_Symbol, PERIOD_H4,  (int)ATR_Period);
   h_EMA_Fast = iMA(_Symbol, PERIOD_H4, EMA_Fast_H4,  0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Slow = iMA(_Symbol, PERIOD_H4, EMA_Slow_H4,  0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Trend= iMA(_Symbol, PERIOD_H4, EMA_Trend_H4, 0, MODE_EMA, PRICE_CLOSE);

   if(h_ATR_M15 == INVALID_HANDLE || h_ATR_H4   == INVALID_HANDLE ||
      h_EMA_Fast == INVALID_HANDLE || h_EMA_Slow == INVALID_HANDLE ||
      h_EMA_Trend== INVALID_HANDLE)
     {
      Print("❌ ERROR: Indicators failed!");
      return INIT_FAILED;
     }

   ArraySetAsSeries(b_ATR_M15,  true);
   ArraySetAsSeries(b_ATR_H4,   true);
   ArraySetAsSeries(b_EMA_Fast, true);
   ArraySetAsSeries(b_EMA_Slow, true);
   ArraySetAsSeries(b_EMA_Trend,true);

   startEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStartEquity = startEquity;

   Print("✅ GoldPA Pro Ready | Price Action | London Breakout + H4 Pullback | 24/5");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(h_ATR_M15);
   IndicatorRelease(h_ATR_H4);
   IndicatorRelease(h_EMA_Fast);
   IndicatorRelease(h_EMA_Slow);
   IndicatorRelease(h_EMA_Trend);
  }

//+------------------------------------------------------------------+
//| MAIN TICK                                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Drawdown check every tick
   if(!DrawdownCheck()) return;

   // Manage positions every tick
   ManagePositions();

   // Auto status every 60 ticks approx
   static int tickCount = 0;
   tickCount++;
   if(tickCount >= 100)
     {
      tickCount = 0;
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double dailyPct = ((eq - dayStartEquity) / dayStartEquity) * 100.0;
      Print("📊 STATUS | Trend:", (h4TrendDir==1?"↑UP":h4TrendDir==-1?"↓DN":"→NEU"),
            " | Range:", (asianBuilt?"✅":"⏳"),
            " | DailyPnL:", DoubleToString(dailyPct,2), "%",
            " | Equity:$", DoubleToString(eq,2),
            " | Trades:", CountMyPositions(),
            " | Protection:", (protectionHit?"🛑":"✅"));
     }

   // M15 bar logic
   datetime curM15 = iTime(_Symbol, PERIOD_M15, 0);
   if(curM15 != lastBarM15)
     {
      lastBarM15 = curM15;

      BuildAsianRange();

      if(SpreadOk() && !IsWeekendEdge() && CountMyPositions() < MaxOpenTrades)
        {
         if(UseBreakout) CheckLondonBreakout();
        }
     }

   // H4 bar logic
   datetime curH4 = iTime(_Symbol, PERIOD_H4, 0);
   if(curH4 != lastBarH4)
     {
      lastBarH4 = curH4;
      UpdateH4Trend();

      if(SpreadOk() && !IsWeekendEdge() && CountMyPositions() < MaxOpenTrades)
        {
         if(UsePullback) CheckH4Pullback();
        }
     }
  }

//+------------------------------------------------------------------+
//| BUILD ASIAN RANGE (00:00 - 06:00 GMT)                           |
//| Gold consolidates in Asian session → range breakout in London    |
//+------------------------------------------------------------------+
void BuildAsianRange()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;

   // Reset at midnight
   if(hour == 0 && dt.min <= 15)
     {
      asianHigh    = 0;
      asianLow     = 999999;
      asianBuilt   = false;
      breakoutDone = false;
      Print("📅 Asian range reset for new day");
     }

   // Build range during Asian session
   if(hour >= AsianStart_GMT && hour < AsianEnd_GMT)
     {
      double high = iHigh(_Symbol, PERIOD_M15, 0);
      double low  = iLow(_Symbol,  PERIOD_M15, 0);
      if(asianHigh == 0) asianHigh = high;
      if(asianLow  == 999999) asianLow = low;
      if(high > asianHigh) asianHigh = high;
      if(low  < asianLow)  asianLow  = low;
     }

   // Mark range as complete at London open OR if Asian session just ended
   if((hour >= LondonOpen_GMT) && !asianBuilt && asianHigh > 0 && asianLow < 999999)
     {
      asianBuilt = true;
      double rangeSize = (asianHigh - asianLow) / _Point;
      Print("📐 Asian Range Built | High: ", DoubleToString(asianHigh, _Digits),
            " | Low: ", DoubleToString(asianLow, _Digits),
            " | Size: ", DoubleToString(rangeSize, 0), " pts");
     }
  }

//+------------------------------------------------------------------+
//| STRATEGY 1: LONDON TREND ENTRY                                   |
//| Enter at London open in trend direction - no breakout needed     |
//+------------------------------------------------------------------+
void CheckLondonBreakout()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;

   // Only trade London window
   if(hour < LondonOpen_GMT || hour >= LondonClose_GMT) return;

   // Only one entry per day
   if(breakoutDone) return;

   if(CopyBuffer(h_ATR_M15, 0, 0, 3, b_ATR_M15) < 3) return;
   double atr = b_ATR_M15[0];
   if(atr <= 0) return;

   double lot = CalcLot(atr * ATR_SL);

   // Load H4 EMAs for confirmation
   if(CopyBuffer(h_ATR_H4, 0, 0, 3, b_ATR_H4) < 3) return;

   // Only BUY in uptrend (gold is bullish 80% of time)
   if(h4TrendDir != 1) return;

   // Candle confirmation
   if(UseCandleFilter && !IsBullishCandle(PERIOD_M15, 1)) return;

   OpenTrade(ORDER_TYPE_BUY, atr, lot, "LONDON_BUY");
   breakoutDone = true;
  }

//+------------------------------------------------------------------+
//| UPDATE H4 TREND + SWING POINTS                                   |
//+------------------------------------------------------------------+
void UpdateH4Trend()
  {
   if(CopyBuffer(h_EMA_Fast,  0, 0, 5, b_EMA_Fast)  < 5) return;
   if(CopyBuffer(h_EMA_Slow,  0, 0, 5, b_EMA_Slow)  < 5) return;
   if(CopyBuffer(h_EMA_Trend, 0, 0, 5, b_EMA_Trend) < 5) return;

   double price    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double emaFast  = b_EMA_Fast[0];
   double emaSlow  = b_EMA_Slow[0];
   double emaTrend = b_EMA_Trend[0];

   // Uptrend: price > EMA50 > EMA200
   if(price > emaSlow && emaSlow > emaTrend)
      h4TrendDir = 1;
   // Downtrend or reversal: stop buying
   else if(price < emaSlow || emaSlow < emaTrend)
      h4TrendDir = -1;
   else
      h4TrendDir = 0;

   // Track recent swing high/low for Fibonacci (last 20 H4 bars)
   double high = iHigh(_Symbol, PERIOD_H4, 1);
   double low  = iLow(_Symbol,  PERIOD_H4, 1);
   for(int i = 1; i <= 20; i++)
     {
      double h = iHigh(_Symbol, PERIOD_H4, i);
      double l = iLow(_Symbol,  PERIOD_H4, i);
      if(h > high) high = h;
      if(l < low)  low  = l;
     }
   h4SwingHigh = high;
   h4SwingLow  = low;
  }

//+------------------------------------------------------------------+
//| STRATEGY 2: H4 TREND PULLBACK + FIBONACCI                       |
//| Enter on pullback to 38.2%-61.8% Fib zone in trend direction    |
//+------------------------------------------------------------------+
void CheckH4Pullback()
  {
   if(h4TrendDir == 0) return;
   if(h4SwingHigh == 0 || h4SwingLow == 0) return;

   if(CopyBuffer(h_ATR_H4, 0, 0, 3, b_ATR_H4) < 3) return;
   double atr   = b_ATR_H4[0];
   if(atr <= 0) return;

   double range = h4SwingHigh - h4SwingLow;
   if(range <= 0) return;

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Fibonacci zones
   double fib618 = h4SwingHigh - range * FibRetrace_Max;  // 61.8% from high
   double fib382 = h4SwingHigh - range * FibRetrace_Min;  // 38.2% from high

   // BUY pullback in uptrend: price pulls back to fib zone
   if(h4TrendDir == 1)
     {
      bool inFibZone = (bid >= fib618 && bid <= fib382);
      if(!inFibZone) return;

      // Candle confirmation
      if(UseCandleFilter)
        {
         bool bull = IsBullishEngulfing(PERIOD_H4, 1) ||
                     IsBullishPinBar(PERIOD_H4, 1);
         if(!bull) return;
        }

      double lot = CalcLot(atr * ATR_SL);
      OpenTrade(ORDER_TYPE_BUY, atr, lot, "PULLBACK_BUY");
     }

   // SELL pullback in downtrend
   if(h4TrendDir == -1)
     {
      double fib382dn = h4SwingLow + range * FibRetrace_Min;
      double fib618dn = h4SwingLow + range * FibRetrace_Max;
      bool inFibZone  = (ask >= fib382dn && ask <= fib618dn);
      if(!inFibZone) return;

      if(UseCandleFilter)
        {
         bool bear = IsBearishEngulfing(PERIOD_H4, 1) ||
                     IsBearishPinBar(PERIOD_H4, 1);
         if(!bear) return;
        }

      double lot = CalcLot(atr * ATR_SL);
      OpenTrade(ORDER_TYPE_SELL, atr, lot, "PULLBACK_SELL");
     }
  }

//+------------------------------------------------------------------+
//| CANDLESTICK PATTERNS                                             |
//+------------------------------------------------------------------+

// Simple bullish/bearish candle check
bool IsBullishCandle(ENUM_TIMEFRAMES tf, int shift)
  {
   double open  = iOpen(_Symbol, tf, shift);
   double close = iClose(_Symbol, tf, shift);
   return (close > open);
  }

bool IsBearishCandle(ENUM_TIMEFRAMES tf, int shift)
  {
   double open  = iOpen(_Symbol, tf, shift);
   double close = iClose(_Symbol, tf, shift);
   return (close < open);
  }

// Bullish Engulfing
bool IsBullishEngulfing(ENUM_TIMEFRAMES tf, int shift)
  {
   double o1 = iOpen(_Symbol, tf, shift+1), c1 = iClose(_Symbol, tf, shift+1);
   double o0 = iOpen(_Symbol, tf, shift),   c0 = iClose(_Symbol, tf, shift);
   double body1 = MathAbs(c1 - o1);
   double body0 = MathAbs(c0 - o0);
   if(body1 <= 0) return false;
   // Prev candle bearish, current bullish and engulfs previous
   return (c1 < o1 && c0 > o0 && body0 >= body1 * EngulfMin &&
           c0 > o1 && o0 < c1);
  }

// Bearish Engulfing
bool IsBearishEngulfing(ENUM_TIMEFRAMES tf, int shift)
  {
   double o1 = iOpen(_Symbol, tf, shift+1), c1 = iClose(_Symbol, tf, shift+1);
   double o0 = iOpen(_Symbol, tf, shift),   c0 = iClose(_Symbol, tf, shift);
   double body1 = MathAbs(c1 - o1);
   double body0 = MathAbs(c0 - o0);
   if(body1 <= 0) return false;
   return (c1 > o1 && c0 < o0 && body0 >= body1 * EngulfMin &&
           c0 < o1 && o0 > c1);
  }

// Bullish Pin Bar (hammer)
bool IsBullishPinBar(ENUM_TIMEFRAMES tf, int shift)
  {
   double o    = iOpen(_Symbol, tf, shift);
   double h    = iHigh(_Symbol, tf, shift);
   double l    = iLow(_Symbol,  tf, shift);
   double c    = iClose(_Symbol, tf, shift);
   double body = MathAbs(c - o);
   double lowerWick = MathMin(o, c) - l;
   double upperWick = h - MathMax(o, c);
   if(body <= 0) return false;
   // Long lower wick, small upper wick, bullish close
   return (lowerWick >= body * PinBarMin && upperWick <= body * 0.5 && c > o);
  }

// Bearish Pin Bar (shooting star)
bool IsBearishPinBar(ENUM_TIMEFRAMES tf, int shift)
  {
   double o    = iOpen(_Symbol, tf, shift);
   double h    = iHigh(_Symbol, tf, shift);
   double l    = iLow(_Symbol,  tf, shift);
   double c    = iClose(_Symbol, tf, shift);
   double body = MathAbs(c - o);
   double upperWick = h - MathMax(o, c);
   double lowerWick = MathMin(o, c) - l;
   if(body <= 0) return false;
   // Long upper wick, small lower wick, bearish close
   return (upperWick >= body * PinBarMin && lowerWick <= body * 0.5 && c < o);
  }

//+------------------------------------------------------------------+
//| OPEN TRADE                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double atr, double lot, string comment)
  {
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double slDist = atr * ATR_SL;
   double tpDist = slDist * RR_Ratio;

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
      Print("✅ [", comment, "] ", EnumToString(type),
            " | Lot: ", lot,
            " | SL: ", DoubleToString(sl, digits),
            " | TP: ", DoubleToString(tp, digits));
   else
      Print("❌ [", comment, "] Failed: ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| CALCULATE LOT                                                     |
//+------------------------------------------------------------------+
double CalcLot(double slDistance)
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
//| MANAGE POSITIONS - BE + TRAILING                                 |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   double atr = 0;
   double tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyBuffer(h_ATR_M15, 0, 0, 3, tmp) >= 3) atr = tmp[0];
   if(atr <= 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))        continue;
      if(posInfo.Magic()  != MagicNumber)  continue;
      if(posInfo.Symbol() != _Symbol)      continue;

      double open   = posInfo.PriceOpen();
      double curSL  = posInfo.StopLoss();
      double curTP  = posInfo.TakeProfit();
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      ulong  ticket = posInfo.Ticket();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double beSL    = NormalizeDouble(open + _Point * 3, digits);
         double trailSL = NormalizeDouble(bid - atr * Trail_ATR, digits);
         if(UseBreakEven && bid >= open + atr * BE_Trigger && curSL < beSL)
            trade.PositionModify(ticket, beSL, curTP);
         else if(UseTrailing && bid > open + atr * Trail_ATR && trailSL > curSL)
            trade.PositionModify(ticket, trailSL, curTP);
        }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double beSL    = NormalizeDouble(open - _Point * 3, digits);
         double trailSL = NormalizeDouble(ask + atr * Trail_ATR, digits);
         if(UseBreakEven && ask <= open - atr * BE_Trigger && (curSL > beSL || curSL == 0))
            trade.PositionModify(ticket, beSL, curTP);
         else if(UseTrailing && ask < open - atr * Trail_ATR && (trailSL < curSL || curSL == 0))
            trade.PositionModify(ticket, trailSL, curTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| DRAWDOWN PROTECTION                                              |
//+------------------------------------------------------------------+
bool DrawdownCheck()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime todayStart = StringToTime(
      IntegerToString(dt.year)+"."+IntegerToString(dt.mon)+"."+IntegerToString(dt.day));

   if(todayStart > lastDayReset)
     {
      lastDayReset   = todayStart;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      protectionHit  = false;
      Print("📅 New day | Equity: $", DoubleToString(dayStartEquity, 2));
     }

   if(protectionHit) return false;

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = ((equity - dayStartEquity) / dayStartEquity) * 100.0;
   double totalDD   = ((equity - startEquity)    / startEquity)    * 100.0;

   if(dailyLoss <= -MaxDailyLoss)
     {
      protectionHit = true;
      CloseAll();
      Print("🛑 DAILY LOSS ", DoubleToString(dailyLoss,2), "% → Paused until tomorrow");
      return false;
     }
   if(totalDD <= -MaxDrawdown)
     {
      protectionHit = true;
      CloseAll();
      Print("🛑 MAX DRAWDOWN ", DoubleToString(totalDD,2), "% → EA stopped");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| CLOSE ALL                                                         |
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && (int)posInfo.Magic() == MagicNumber)
            trade.PositionClose(posInfo.Ticket());
  }

//+------------------------------------------------------------------+
//| SPREAD CHECK                                                      |
//+------------------------------------------------------------------+
bool SpreadOk()
  {
   if(!AvoidHighSpread) return true;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= MaxSpread);
  }

//+------------------------------------------------------------------+
//| WEEKEND EDGE CHECK                                               |
//+------------------------------------------------------------------+
bool IsWeekendEdge()
  {
   if(!AvoidWeekendEdge) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   // Friday after 20:00 GMT or Monday before 02:00 GMT
   if(dt.day_of_week == 5 && dt.hour >= 20) return true;
   if(dt.day_of_week == 1 && dt.hour < 2)   return true;
   return false;
  }

//+------------------------------------------------------------------+
//| COUNT POSITIONS                                                   |
//+------------------------------------------------------------------+
int CountMyPositions()
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol)
            count++;
   return count;
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
   if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) return;

   long   dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
   long   dealType  = HistoryDealGetInteger(ticket, DEAL_TYPE);
   double net       = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(ticket, DEAL_SWAP)   +
                      HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   double price     = HistoryDealGetDouble(ticket, DEAL_PRICE);
   double lotD      = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   string dir       = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";

   if(dealEntry == DEAL_ENTRY_IN)
     {
      Print("┌────────────────────────────────────────");
      Print("│ 📂 OPENED | ", dir,
            " | Lot: ", DoubleToString(lotD, 2),
            " | @", DoubleToString(price, _Digits));
      Print("│ Balance: $", DoubleToString(balance, 2));
      Print("└────────────────────────────────────────");
     }
   if(dealEntry == DEAL_ENTRY_OUT)
     {
      string res  = (net > 0) ? "✅ WIN" : (net < 0) ? "❌ LOSS" : "➖ BE";
      string sign = (net >= 0) ? "+" : "";
      Print("┌────────────────────────────────────────");
      Print("│ 📁 CLOSED | ", res, " | $", sign, DoubleToString(net, 2));
      Print("│ Balance: $", DoubleToString(balance, 2),
            " | Equity: $", DoubleToString(equity, 2));
      Print("└────────────────────────────────────────");
     }
  }

//+------------------------------------------------------------------+
//| ON CHART EVENT - S for status                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam,
                  const double& dparam, const string& sparam)
  {
   if(id == CHARTEVENT_KEYDOWN && lparam == 83)
     {
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double dailyPnL= ((equity - dayStartEquity) / dayStartEquity) * 100.0;
      double totalDD = ((equity - startEquity)    / startEquity)    * 100.0;

      Print("╔══════════════════════════════════════════╗");
      Print("║         GOLDPA PRO - STATUS              ║");
      Print("╠══════════════════════════════════════════╣");
      Print("║ Balance     : $", DoubleToString(balance, 2));
      Print("║ Equity      : $", DoubleToString(equity, 2));
      Print("║ Daily P&L   : ", DoubleToString(dailyPnL, 2), "%");
      Print("║ Total DD    : ", DoubleToString(totalDD, 2), "%");
      Print("║ H4 Trend    : ", (h4TrendDir==1?"↑ BULLISH":h4TrendDir==-1?"↓ BEARISH":"→ NEUTRAL"));
      Print("║ Asian Range : ", (asianBuilt?"✅ Built":"⏳ Building"));
      if(asianBuilt)
        {
         Print("║ Asian High  : ", DoubleToString(asianHigh, _Digits));
         Print("║ Asian Low   : ", DoubleToString(asianLow,  _Digits));
        }
      Print("║ Open Trades : ", CountMyPositions());
      Print("║ Protection  : ", (protectionHit?"🛑 ACTIVE":"✅ OK"));
      Print("╚══════════════════════════════════════════╝");
     }
  }
//+------------------------------------------------------------------+
