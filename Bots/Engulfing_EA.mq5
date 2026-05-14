//+------------------------------------------------------------------+
//|                    Engulfing EA v1.7                             |
//|          Strategy: H4 Trend + H1 Confirm + M5 Execute           |
//|          Filter : Pivot Points + RSI + News Filter               |
//|          Added  : Trailing Stop + Breakeven                      |
//|          Fix    : Invalid Stops - Broker MinStopLevel Check      |
//|          Update : H4 & H1 = Price vs EMA50 (faster response)    |
//+------------------------------------------------------------------+
#property copyright "Ahmed - Engulfing EA"
#property version   "1.70"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input group "=== Trend Settings ==="
input int    EMA_Fast       = 50;       // EMA Fast Period
input int    EMA_Slow       = 200;      // EMA Slow Period

input group "=== RSI Settings ==="
input int    RSI_Period     = 14;       // RSI Period
input double RSI_Upper      = 55.0;    // RSI Upper Level (Bullish)
input double RSI_Lower      = 45.0;    // RSI Lower Level (Bearish)

input group "=== Trade Settings ==="
input double RiskPercent    = 1.0;     // Risk % per trade
input double RR_Ratio       = 2.0;     // Risk:Reward Ratio (1:2)
input int    Slippage        = 10;      // Slippage in points
input int    MagicNumber     = 123456;  // Magic Number

input group "=== News Filter (GMT) ==="
input bool   UseNewsFilter   = true;    // Enable News Filter
input int    NewsMinsBefore  = 30;      // Minutes before news
input int    NewsMinsAfter   = 30;      // Minutes after news

input group "=== Pivot Settings ==="
input bool   UsePivotFilter  = false;   // Enable Pivot Point Filter
input int    PivotBuffer     = 50;      // Points near Pivot to allow entry

input group "=== Trailing Stop Settings ==="
input bool   UseTrailingStop   = true;  // Enable Trailing Stop
input double BreakevenRatio    = 0.6;   // Move to Breakeven at X% of TP (0.6 = 60%)
input int    TrailingStep      = 30;    // Trailing Step in Points

//--- Global Variables
int    ema_fast_h4;
int    ema_fast_h1;
int    rsi_h1;
double PivotPoint, R1, R2, S1, S2;

//+------------------------------------------------------------------+
//| News Times (Fixed - GMT)                                         |
//+------------------------------------------------------------------+
struct NewsTime { int month; int day; int hour; int minute; };

NewsTime NewsList[] = {
   // NFP - First Friday of each month at 13:30 GMT (approximate)
   {1,  3,  13, 30}, {2,  7,  13, 30}, {3,  7,  13, 30},
   {4,  4,  13, 30}, {5,  2,  13, 30}, {6,  6,  13, 30},
   {7,  4,  13, 30}, {8,  1,  13, 30}, {9,  5,  13, 30},
   {10, 3,  13, 30}, {11, 7,  13, 30}, {12, 5,  13, 30},
   // CPI - Usually around 15th each month at 13:30 GMT
   {1,  15, 13, 30}, {2,  14, 13, 30}, {3,  12, 13, 30},
   {4,  10, 13, 30}, {5,  15, 13, 30}, {6,  12, 13, 30},
   {7,  11, 13, 30}, {8,  14, 13, 30}, {9,  11, 13, 30},
   {10, 10, 13, 30}, {11, 13, 13, 30}, {12, 11, 13, 30},
   // FOMC - 8 times per year at 19:00 GMT (approximate dates)
   {1,  29, 19, 0},  {3,  19, 19, 0},  {5,  7,  19, 0},
   {6,  18, 19, 0},  {7,  30, 19, 0},  {9,  17, 19, 0},
   {11, 5,  19, 0},  {12, 10, 19, 0}
};

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // H4 EMA50 only (price vs EMA50 for trend direction)
   ema_fast_h4 = iMA(_Symbol, PERIOD_H4, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);

   // H1 EMA50 only (price vs EMA50 for trend confirmation)
   ema_fast_h1 = iMA(_Symbol, PERIOD_H1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);

   // H1 RSI
   rsi_h1 = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);

   Print("Engulfing EA v1.7 Started on ", _Symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(ema_fast_h4);
   IndicatorRelease(ema_fast_h1);
   IndicatorRelease(rsi_h1);
}

//+------------------------------------------------------------------+
//| Main Tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   // Trailing Stop - runs on every tick
   if(UseTrailingStop) ManageTrailingStop();

   // Only run on new M5 candle
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   // 1. Check if trade already open
   if(PositionSelect(_Symbol)) return;

   // 2. News Filter
   if(UseNewsFilter && IsNewsTime()) return;

   // 3. Get Trend Direction
   int trend = GetTrend();
   if(trend == 0) return; // No clear trend

   // 4. Check RSI on H1
   if(!CheckRSI(trend)) return;

   // 5. Calculate Pivot Points
   CalcPivotPoints();

   // 6. Check Engulfing on M5
   int signal = CheckEngulfing();
   if(signal == 0) return;

   // 7. Signal must match trend
   if(signal != trend) return;

   // 8. Check price near Pivot (optional)
   if(UsePivotFilter && !IsNearPivot()) return;

   // 9. Execute Trade
   ExecuteTrade(signal);
}

//+------------------------------------------------------------------+
//| Get H4 + H1 Trend Direction                                      |
//| Returns: 1=Bullish, -1=Bearish, 0=No Trend                      |
//+------------------------------------------------------------------+
int GetTrend()
{
   double ema_f_h4[], ema_f_h1[];

   if(CopyBuffer(ema_fast_h4, 0, 1, 1, ema_f_h4) <= 0) return 0;
   if(CopyBuffer(ema_fast_h1, 0, 1, 1, ema_f_h1) <= 0) return 0;

   double h4_close = iClose(_Symbol, PERIOD_H4, 1);
   double h1_close = iClose(_Symbol, PERIOD_H1, 1);

   bool h4_bull = h4_close > ema_f_h4[0];  // H4: Price > EMA50
   bool h4_bear = h4_close < ema_f_h4[0];  // H4: Price < EMA50
   bool h1_bull = h1_close > ema_f_h1[0];  // H1: Price > EMA50
   bool h1_bear = h1_close < ema_f_h1[0];  // H1: Price < EMA50

   if(h4_bull && h1_bull) return  1;  // Bullish
   if(h4_bear && h1_bear) return -1;  // Bearish
   return 0;
}

//+------------------------------------------------------------------+
//| Check RSI on H1                                                  |
//+------------------------------------------------------------------+
bool CheckRSI(int trend)
{
   double rsi[];
   if(CopyBuffer(rsi_h1, 0, 1, 1, rsi) <= 0) return false;

   if(trend ==  1 && rsi[0] > RSI_Upper) return true;  // Bullish
   if(trend == -1 && rsi[0] < RSI_Lower) return true;  // Bearish
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Daily Pivot Points                                     |
//+------------------------------------------------------------------+
void CalcPivotPoints()
{
   datetime yesterday = iTime(_Symbol, PERIOD_D1, 1);
   double high = iHigh(_Symbol, PERIOD_D1, 1);
   double low  = iLow (_Symbol, PERIOD_D1, 1);
   double close = iClose(_Symbol, PERIOD_D1, 1);

   PivotPoint = (high + low + close) / 3.0;
   R1 = (2 * PivotPoint) - low;
   R2 = PivotPoint + (high - low);
   S1 = (2 * PivotPoint) - high;
   S2 = PivotPoint - (high - low);
}

//+------------------------------------------------------------------+
//| Check if price is near a Pivot Level                             |
//+------------------------------------------------------------------+
bool IsNearPivot()
{
   double price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = PivotBuffer * _Point;

   double levels[] = {PivotPoint, R1, R2, S1, S2};

   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(MathAbs(price - levels[i]) <= buffer)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check Engulfing Pattern on M5                                    |
//| Returns: 1=Bullish, -1=Bearish, 0=None                          |
//+------------------------------------------------------------------+
int CheckEngulfing()
{
   double open1  = iOpen (_Symbol, PERIOD_M5, 2);
   double close1 = iClose(_Symbol, PERIOD_M5, 2);
   double open2  = iOpen (_Symbol, PERIOD_M5, 1);
   double close2 = iClose(_Symbol, PERIOD_M5, 1);

   double body1 = MathAbs(close1 - open1);
   double body2 = MathAbs(close2 - open2);

   // Minimum body size filter (avoid doji)
   if(body1 < 5 * _Point || body2 < 5 * _Point) return 0;

   // Bullish Engulfing
   if(close1 < open1 &&       // Candle 1 is Bearish
      close2 > open2 &&       // Candle 2 is Bullish
      open2  <= close1 &&     // Opens below prev close
      close2 >= open1)        // Closes above prev open
      return 1;

   // Bearish Engulfing
   if(close1 > open1 &&       // Candle 1 is Bullish
      close2 < open2 &&       // Candle 2 is Bearish
      open2  >= close1 &&     // Opens above prev close
      close2 <= open1)        // Closes below prev open
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Execute Trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
   double price, sl, tp;
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1  = iLow (_Symbol, PERIOD_M5, 1);

   double slDistance = 0;

   if(signal == 1) // Buy
   {
      price      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl         = low1 - (10 * _Point);
      slDistance = price - sl;
      tp         = price + (slDistance * RR_Ratio);
   }
   else // Sell
   {
      price      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl         = high1 + (10 * _Point);
      slDistance = sl - price;
      tp         = price - (slDistance * RR_Ratio);
   }

   double lotSize = CalcLotSize(slDistance);
   if(lotSize <= 0) return;

   if(signal == 1)
      trade.Buy(lotSize, _Symbol, price, sl, tp, "Engulfing Buy");
   else
      trade.Sell(lotSize, _Symbol, price, sl, tp, "Engulfing Sell");
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk %                               |
//+------------------------------------------------------------------+
double CalcLotSize(double slDistance)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount     = accountBalance * (RiskPercent / 100.0);
   double tickValue      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize       = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize == 0 || slDistance == 0) return 0;

   double lotSize = riskAmount / ((slDistance / tickSize) * tickValue);

   // Normalize lot size
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return lotSize;
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop & Breakeven                                 |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!PositionSelect(_Symbol)) return;
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) return;

   double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL  = PositionGetDouble(POSITION_SL);
   double currentTP  = PositionGetDouble(POSITION_TP);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long   posType    = PositionGetInteger(POSITION_TYPE);

   // Get broker minimum stop distance
   double spread       = currentAsk - currentBid;
   double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double minDist      = MathMax(minStopLevel, spread) * 1.1; // 10% buffer

   double tpDistance = MathAbs(currentTP - openPrice);
   double trailStep  = TrailingStep * _Point;
   double newSL      = 0;

   if(posType == POSITION_TYPE_BUY)
   {
      double profit = currentBid - openPrice;

      // Step 1: Move to Breakeven
      if(profit >= tpDistance * BreakevenRatio && currentSL < openPrice)
      {
         newSL = openPrice + minDist;
         if(newSL > currentSL && (currentBid - newSL) >= minDist)
            trade.PositionModify(_Symbol, newSL, currentTP);
         return;
      }

      // Step 2: Trail SL after Breakeven
      if(currentSL >= openPrice)
      {
         newSL = currentBid - MathMax(trailStep, minDist);
         if(newSL > currentSL && (currentBid - newSL) >= minDist)
            trade.PositionModify(_Symbol, newSL, currentTP);
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double profit = openPrice - currentAsk;

      // Step 1: Move to Breakeven
      if(profit >= tpDistance * BreakevenRatio && currentSL > openPrice)
      {
         newSL = openPrice - minDist;
         if(newSL < currentSL && (newSL - currentAsk) >= minDist)
            trade.PositionModify(_Symbol, newSL, currentTP);
         return;
      }

      // Step 2: Trail SL after Breakeven
      if(currentSL <= openPrice)
      {
         newSL = currentAsk + MathMax(trailStep, minDist);
         if(newSL < currentSL && (newSL - currentAsk) >= minDist)
            trade.PositionModify(_Symbol, newSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if current time is near a news event                       |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   MqlDateTime now;
   TimeToStruct(TimeGMT(), now);

   for(int i = 0; i < ArraySize(NewsList); i++)
   {
      if(now.mon != NewsList[i].month || now.day != NewsList[i].day) continue;

      int newsMinutes = NewsList[i].hour * 60 + NewsList[i].minute;
      int nowMinutes  = now.hour * 60 + now.min;
      int diff        = newsMinutes - nowMinutes;

      if(diff >= -NewsMinsAfter && diff <= NewsMinsBefore)
         return true;
   }
   return false;
}
//+------------------------------------------------------------------+
