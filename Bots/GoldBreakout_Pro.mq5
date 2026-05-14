//+------------------------------------------------------------------+
//|                                        GoldBreakout_Pro.mq5    |
//|                   XAUUSD Breakout Bot | Exness Optimized        |
//|              Fast Trades + Capital Protection + Daily Profit    |
//+------------------------------------------------------------------+
#property copyright   "GoldBreakout Pro"
#property version     "1.00"
#property description "XAUUSD Breakout | Exness | $2000"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+

input group "=== Breakout Settings ==="
input int    BreakoutBars    = 20;    // Candles to find High/Low
input double BreakoutBuffer  = 5;    // Buffer above/below breakout (points)
input ENUM_TIMEFRAMES TF_Main = PERIOD_M15; // Main timeframe

input group "=== Money Management ==="
input double RiskPercent     = 1.0;  // Risk % per trade
input double MaxLotSize      = 2.0;  // Max lot
input int    MaxTrades       = 3;    // Max simultaneous trades

input group "=== Trade Settings ==="
input double ATR_SL          = 1.5;  // SL = ATR x this
input double RR_Ratio        = 2.0;  // TP = SL x this
input bool   UseBreakEven    = true; // Breakeven
input bool   UseTrailing     = true; // Trailing stop

input group "=== Trend Filter ==="
input int    EMA_Trend       = 50;   // Trend EMA on H1

input group "=== Session Filter ==="
input int    StartHour       = 7;    // Start hour GMT
input int    EndHour         = 20;   // End hour GMT

input group "=== Protection ==="
input double MaxDailyLoss    = 3.0;  // Max daily loss %
input double MaxDrawdown     = 10.0; // Max drawdown %

input group "=== EA Settings ==="
input int    MagicNumber     = 99999;
input int    Slippage        = 30;

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+

int      h_ATR, h_EMA;
double   b_ATR[], b_EMA[];

datetime lastBar     = 0;
double   startEquity    = 0;
double   dayStartEquity = 0;
datetime lastDayReset   = 0;
bool     protectionHit  = false;
int      tickCount      = 0;

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   h_ATR = iATR(_Symbol, TF_Main, 14);
   h_EMA = iMA(_Symbol, PERIOD_H1, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);

   if(h_ATR == INVALID_HANDLE || h_EMA == INVALID_HANDLE)
     {
      Print("❌ Indicators failed!");
      return INIT_FAILED;
     }

   ArraySetAsSeries(b_ATR, true);
   ArraySetAsSeries(b_EMA, true);

   startEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStartEquity = startEquity;

   Print("✅ GoldBreakout Pro Ready | Exness | XAUUSD | $2000");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(h_ATR);
   IndicatorRelease(h_EMA);
  }

//+------------------------------------------------------------------+
//| MAIN TICK                                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!ProtectionCheck()) return;

   // Manage positions every tick
   ManagePositions();

   // Status
   tickCount++;
   if(tickCount >= 100)
     {
      tickCount = 0;
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("📊 STATUS | Trades:", CountMyPositions(),
            " | DailyPnL:", DoubleToString(((eq-dayStartEquity)/dayStartEquity)*100, 2), "%",
            " | Equity:$", DoubleToString(eq, 2),
            " | Protection:", (protectionHit?"🛑":"✅"));
     }

   // New bar check
   datetime curBar = iTime(_Symbol, TF_Main, 0);
   if(curBar == lastBar) return;
   lastBar = curBar;

   // Session check
   if(!IsInSession()) return;

   // Max trades check
   if(CountMyPositions() >= MaxTrades) return;

   // Load indicators
   if(CopyBuffer(h_ATR, 0, 0, 3, b_ATR) < 3) return;
   if(CopyBuffer(h_EMA, 0, 0, 3, b_EMA) < 3) return;

   // Check breakout
   CheckBreakout();
  }

//+------------------------------------------------------------------+
//| BREAKOUT LOGIC                                                    |
//+------------------------------------------------------------------+
void CheckBreakout()
  {
   double atr    = b_ATR[0];
   double ema    = b_EMA[0];
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buf    = BreakoutBuffer * _Point * 10;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(atr <= 0) return;

   // Find highest high and lowest low of last X bars
   double highestHigh = 0;
   double lowestLow   = 999999;

   for(int i = 1; i <= BreakoutBars; i++)
     {
      double h = iHigh(_Symbol, TF_Main, i);
      double l = iLow(_Symbol,  TF_Main, i);
      if(h > highestHigh) highestHigh = h;
      if(l < lowestLow)   lowestLow   = l;
     }

   if(highestHigh == 0 || lowestLow == 999999) return;

   double slDist = atr * ATR_SL;
   double tpDist = slDist * RR_Ratio;
   double lot    = CalcLot(slDist);

   // === BUY BREAKOUT ===
   // Price breaks above highest high + trend is up
   if(ask > highestHigh + buf && bid > ema)
     {
      // No existing buy in same area
      if(!HasRecentTrade(ORDER_TYPE_BUY, highestHigh))
        {
         double sl = NormalizeDouble(ask - slDist, digits);
         double tp = NormalizeDouble(ask + tpDist, digits);
         bool ok = trade.Buy(lot, _Symbol, ask, sl, tp, "BO_BUY");
         if(ok)
            Print("✅ BUY Breakout | @", DoubleToString(ask,digits),
                  " | SL:", DoubleToString(sl,digits),
                  " | TP:", DoubleToString(tp,digits),
                  " | Lot:", lot);
         else
            Print("❌ BUY failed: ", trade.ResultRetcodeDescription());
        }
     }

   // === SELL BREAKOUT ===
   // Price breaks below lowest low + trend is down
   if(bid < lowestLow - buf && ask < ema)
     {
      if(!HasRecentTrade(ORDER_TYPE_SELL, lowestLow))
        {
         double sl = NormalizeDouble(bid + slDist, digits);
         double tp = NormalizeDouble(bid - tpDist, digits);
         bool ok = trade.Sell(lot, _Symbol, bid, sl, tp, "BO_SELL");
         if(ok)
            Print("✅ SELL Breakout | @", DoubleToString(bid,digits),
                  " | SL:", DoubleToString(sl,digits),
                  " | TP:", DoubleToString(tp,digits),
                  " | Lot:", lot);
         else
            Print("❌ SELL failed: ", trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| CHECK IF RECENT TRADE EXISTS NEAR THIS LEVEL                     |
//+------------------------------------------------------------------+
bool HasRecentTrade(ENUM_ORDER_TYPE type, double level)
  {
   double buffer = 500 * _Point * 10;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol)
           {
            ENUM_POSITION_TYPE ptype = (type == ORDER_TYPE_BUY) ?
                                       POSITION_TYPE_BUY : POSITION_TYPE_SELL;
            if(posInfo.PositionType() == ptype)
               if(MathAbs(posInfo.PriceOpen() - level) < buffer)
                  return true;
           }
   return false;
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
//| MANAGE POSITIONS                                                  |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   if(CopyBuffer(h_ATR, 0, 0, 3, b_ATR) < 3) return;
   double atr = b_ATR[0];
   if(atr <= 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))       continue;
      if(posInfo.Magic()  != MagicNumber) continue;
      if(posInfo.Symbol() != _Symbol)     continue;

      double open   = posInfo.PriceOpen();
      double curSL  = posInfo.StopLoss();
      double curTP  = posInfo.TakeProfit();
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      ulong  ticket = posInfo.Ticket();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double beSL    = NormalizeDouble(open + _Point * 5, digits);
         double trailSL = NormalizeDouble(bid - atr * 0.8, digits);

         if(UseBreakEven && bid >= open + atr && curSL < beSL)
            trade.PositionModify(ticket, beSL, curTP);
         else if(UseTrailing && bid > open + atr && trailSL > curSL)
            trade.PositionModify(ticket, trailSL, curTP);
        }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double beSL    = NormalizeDouble(open - _Point * 5, digits);
         double trailSL = NormalizeDouble(ask + atr * 0.8, digits);

         if(UseBreakEven && ask <= open - atr && (curSL > beSL || curSL == 0))
            trade.PositionModify(ticket, beSL, curTP);
         else if(UseTrailing && ask < open - atr && (trailSL < curSL || curSL == 0))
            trade.PositionModify(ticket, trailSL, curTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| SESSION CHECK                                                     |
//+------------------------------------------------------------------+
bool IsInSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return (dt.hour >= StartHour && dt.hour < EndHour);
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
//| PROTECTION CHECK                                                  |
//+------------------------------------------------------------------+
bool ProtectionCheck()
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
      Print("📅 New day | Equity:$", DoubleToString(dayStartEquity, 2));
     }

   if(protectionHit) return false;

   double eq        = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = ((eq - dayStartEquity) / dayStartEquity) * 100.0;
   double totalDD   = ((eq - startEquity)    / startEquity)    * 100.0;

   if(dailyLoss <= -MaxDailyLoss)
     {
      protectionHit = true;
      CloseAll();
      Print("🛑 Daily loss ", DoubleToString(dailyLoss,2), "% → Paused");
      return false;
     }
   if(totalDD <= -MaxDrawdown)
     {
      protectionHit = true;
      CloseAll();
      Print("🛑 Drawdown ", DoubleToString(totalDD,2), "% → Stopped");
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
//| ON TRADE LOGGING                                                  |
//+------------------------------------------------------------------+
void OnTrade()
  {
   static int lastTotal = 0;
   int total = HistoryDealsTotal();
   if(total <= lastTotal) return;
   lastTotal = total;

   if(!HistorySelect(0, TimeCurrent())) return;
   ulong ticket = HistoryDealGetTicket(total - 1);
   if(ticket == 0) return;
   if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) return;

   long   entry   = HistoryDealGetInteger(ticket, DEAL_ENTRY);
   long   type    = HistoryDealGetInteger(ticket, DEAL_TYPE);
   double net     = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                    HistoryDealGetDouble(ticket, DEAL_SWAP)   +
                    HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   double price   = HistoryDealGetDouble(ticket, DEAL_PRICE);
   double lot     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string dir     = (type == DEAL_TYPE_BUY) ? "BUY" : "SELL";
   string sign    = (net >= 0) ? "+" : "";

   if(entry == DEAL_ENTRY_IN)
      Print("┌────────────────────────────────────────");
   Print("│ 📂 ", dir, " | Lot:", DoubleToString(lot,2),
         " | @", DoubleToString(price,_Digits));
   Print("│ Balance:$", DoubleToString(balance,2));
   Print("└────────────────────────────────────────");

   if(entry == DEAL_ENTRY_OUT)
     {
      string res = (net>0)?"✅ WIN":(net<0)?"❌ LOSS":"➖ BE";
      Print("┌────────────────────────────────────────");
      Print("│ 📁 CLOSED | ", res, " | $", sign, DoubleToString(net,2));
      Print("│ Balance:$", DoubleToString(balance,2));
      Print("└────────────────────────────────────────");
     }
  }
//+------------------------------------------------------------------+
