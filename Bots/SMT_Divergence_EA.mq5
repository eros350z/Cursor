//+------------------------------------------------------------------+
//|                                         SMT_Divergence_EA.mq5   |
//|                          SMT Divergence XAUUSD vs XAGUSD M5     |
//+------------------------------------------------------------------+
#property copyright "AI Trading"
#property version   "4.0"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input double   RiskPercent     = 1.0;    // Risk % per trade
input int      SwingBars       = 10;     // Bars each side for swing detection
input double   TP1_Points      = 1000;   // TP1 (10 pip)
input double   TP2_Points      = 2000;   // TP2 (20 pip)
input double   TP3_Points      = 3000;   // TP3 (30 pip)
input double   TP1_ClosePerc   = 25;     // % close at TP1
input double   TP2_ClosePerc   = 25;     // % close at TP2
input double   TP3_ClosePerc   = 25;     // % close at TP3
input double   Trailing_Points = 1500;   // Trailing Stop (15 pip)
input double   SL_Buffer       = 300;    // SL buffer beyond swing (3 pip)
input int      ServerOffset    = 3;      // Server to Kuwait offset
input int      MagicNumber     = 789012; // Magic Number

CTrade trade;

struct TradeState
{
   ulong  ticket;
   bool   tp1Hit;
   bool   tp2Hit;
   bool   tp3Hit;
};
TradeState tradeStates[];

//+------------------------------------------------------------------+
//| Get swing High — highest high with SwingBars on each side        |
//+------------------------------------------------------------------+
double GetSwingHigh(string symbol, int shift)
{
   double high = iHigh(symbol, PERIOD_M5, shift);
   for(int i = 1; i <= SwingBars; i++)
   {
      if(iHigh(symbol, PERIOD_M5, shift + i) > high) return 0; // not a swing
      if(iHigh(symbol, PERIOD_M5, shift - i) > high) return 0;
   }
   return high;
}

//+------------------------------------------------------------------+
//| Get swing Low — lowest low with SwingBars on each side           |
//+------------------------------------------------------------------+
double GetSwingLow(string symbol, int shift)
{
   double low = iLow(symbol, PERIOD_M5, shift);
   for(int i = 1; i <= SwingBars; i++)
   {
      if(iLow(symbol, PERIOD_M5, shift + i) < low) return 0;
      if(iLow(symbol, PERIOD_M5, shift - i) < low) return 0;
   }
   return low;
}

//+------------------------------------------------------------------+
//| SMT Divergence on confirmed swing points                         |
//+------------------------------------------------------------------+
int GetSMTSignal()
{
   // Find last two confirmed swing lows on XAUUSD
   double xauLow1 = 0, xauLow2 = 0;
   double xagLow1 = 0, xagLow2 = 0;
   double xauHigh1 = 0, xauHigh2 = 0;
   double xagHigh1 = 0, xagHigh2 = 0;

   // Search for swing lows
   for(int i = SwingBars + 1; i <= 100; i++)
   {
      double sl = GetSwingLow("XAUUSD", i);
      if(sl > 0)
      {
         if(xauLow1 == 0) { xauLow1 = sl; xagLow1 = iLow("XAGUSD", PERIOD_M5, i); }
         else if(xauLow2 == 0) { xauLow2 = sl; xagLow2 = iLow("XAGUSD", PERIOD_M5, i); break; }
      }
   }

   // Search for swing highs
   for(int i = SwingBars + 1; i <= 100; i++)
   {
      double sh = GetSwingHigh("XAUUSD", i);
      if(sh > 0)
      {
         if(xauHigh1 == 0) { xauHigh1 = sh; xagHigh1 = iHigh("XAGUSD", PERIOD_M5, i); }
         else if(xauHigh2 == 0) { xauHigh2 = sh; xagHigh2 = iHigh("XAGUSD", PERIOD_M5, i); break; }
      }
   }

   // Bullish SMT: XAUUSD lower swing low, XAGUSD higher swing low
   if(xauLow1 > 0 && xauLow2 > 0 && xagLow1 > 0 && xagLow2 > 0)
      if(xauLow1 < xauLow2 && xagLow1 > xagLow2) return 1;

   // Bearish SMT: XAUUSD higher swing high, XAGUSD lower swing high
   if(xauHigh1 > 0 && xauHigh2 > 0 && xagHigh1 > 0 && xagHigh2 > 0)
      if(xauHigh1 > xauHigh2 && xagHigh1 < xagHigh2) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Get state index                                                  |
//+------------------------------------------------------------------+
int GetStateIndex(ulong ticket)
{
   for(int i = 0; i < ArraySize(tradeStates); i++)
      if(tradeStates[i].ticket == ticket) return i;

   int idx = ArraySize(tradeStates);
   ArrayResize(tradeStates, idx + 1);
   tradeStates[idx].ticket = ticket;
   tradeStates[idx].tp1Hit = false;
   tradeStates[idx].tp2Hit = false;
   tradeStates[idx].tp3Hit = false;
   return idx;
}

//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalcLotSize(double slPoints)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100.0;
   double tickValue  = SymbolInfoDouble("XAUUSD", SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble("XAUUSD", SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble("XAUUSD", SYMBOL_POINT);
   double minLot     = SymbolInfoDouble("XAUUSD", SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble("XAUUSD", SYMBOL_VOLUME_MAX);
   double lotStep    = SymbolInfoDouble("XAUUSD", SYMBOL_VOLUME_STEP);

   if(slPoints <= 0 || tickValue <= 0) return minLot;

   double slMoney = slPoints * point / tickSize * tickValue;
   double lot     = riskAmount / slMoney;
   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Trading hours                                                    |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int serverHour = dt.hour;
   int kuwaitHour = (serverHour + ServerOffset) % 24;
   int dayWeek    = dt.day_of_week;
   int kuwaitDay  = dayWeek;
   if(serverHour + ServerOffset >= 24) kuwaitDay = (dayWeek + 1) % 7;

   if(kuwaitDay == 6 || kuwaitDay == 0) return false;
   if(kuwaitDay == 5 && kuwaitHour >= 20) return false;
   if(kuwaitHour >= 0 && kuwaitHour < 4) return false;
   return true;
}

int CountTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == "XAUUSD" &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   return count;
}

//+------------------------------------------------------------------+
//| Partial Close                                                    |
//+------------------------------------------------------------------+
void PartialClose(ulong ticket, double closePercent, double totalLot)
{
   double closeLot = NormalizeDouble(totalLot * closePercent / 100.0, 2);
   double minLot   = SymbolInfoDouble("XAUUSD", SYMBOL_VOLUME_MIN);
   double lotStep  = SymbolInfoDouble("XAUUSD", SYMBOL_VOLUME_STEP);
   closeLot = MathFloor(closeLot / lotStep) * lotStep;
   if(closeLot < minLot) return;
   trade.PositionClosePartial(ticket, closeLot);
}

//+------------------------------------------------------------------+
//| Manage trades                                                    |
//+------------------------------------------------------------------+
void ManageTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != "XAUUSD") continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      int    type      = (int)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double lot       = PositionGetDouble(POSITION_VOLUME);
      double point     = SymbolInfoDouble("XAUUSD", SYMBOL_POINT);
      double bid       = SymbolInfoDouble("XAUUSD", SYMBOL_BID);
      double ask       = SymbolInfoDouble("XAUUSD", SYMBOL_ASK);

      int    idx    = GetStateIndex(ticket);
      double profit = (type == POSITION_TYPE_BUY) ?
                      (bid - openPrice) / point :
                      (openPrice - ask) / point;

      // TP1: close 25% + breakeven
      if(profit >= TP1_Points && !tradeStates[idx].tp1Hit)
      {
         PartialClose(ticket, TP1_ClosePerc, lot);
         trade.PositionModify(ticket, openPrice, currentTP);
         tradeStates[idx].tp1Hit = true;
         Print("TP1 ✅ Closed 25% + Breakeven | Ticket=", ticket);
      }

      // TP2: close 25%
      if(profit >= TP2_Points && !tradeStates[idx].tp2Hit)
      {
         PartialClose(ticket, TP2_ClosePerc, lot);
         tradeStates[idx].tp2Hit = true;
         Print("TP2 ✅ Closed 25% | Ticket=", ticket);
      }

      // TP3: close 25%
      if(profit >= TP3_Points && !tradeStates[idx].tp3Hit)
      {
         PartialClose(ticket, TP3_ClosePerc, lot);
         tradeStates[idx].tp3Hit = true;
         Print("TP3 ✅ Closed 25% + Trailing active | Ticket=", ticket);
      }

      // Trailing for last 25%
      if(tradeStates[idx].tp3Hit)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double newSL = NormalizeDouble(bid - Trailing_Points * point, _Digits);
            if(newSL > currentSL)
               trade.PositionModify(ticket, newSL, currentTP);
         }
         else
         {
            double newSL = NormalizeDouble(ask + Trailing_Points * point, _Digits);
            if(newSL < currentSL || currentSL == 0)
               trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   if(!SymbolSelect("XAGUSD", true))
   {
      Print("❌ XAGUSD not available - add to Market Watch");
      return INIT_FAILED;
   }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int kuwaitHour = (dt.hour + ServerOffset) % 24;
   Print("✅ SMT Divergence EA v4.0 | Server: ", dt.hour, " | Kuwait: ", kuwaitHour);
   Print("Swing detection: ", SwingBars, " bars | Risk: ", RiskPercent, "%");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageTrades();

   static datetime lastBar = 0;
   datetime currentBar = iTime("XAUUSD", PERIOD_M5, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   if(!IsTradingAllowed()) return;
   if(CountTrades() > 0) return;

   int signal = GetSMTSignal();
   if(signal == 0) return;

   double point = SymbolInfoDouble("XAUUSD", SYMBOL_POINT);

   if(signal == 1) // BUY
   {
      double recentLow = iLow("XAUUSD", PERIOD_M5, SwingBars + 1);
      double ask       = SymbolInfoDouble("XAUUSD", SYMBOL_ASK);
      double sl        = NormalizeDouble(recentLow - SL_Buffer * point, _Digits);
      double tp        = NormalizeDouble(ask + TP3_Points * point, _Digits);
      double slPoints  = (ask - sl) / point;
      double lot       = CalcLotSize(slPoints);

      if(trade.Buy(lot, "XAUUSD", ask, sl, tp, "SMT_BUY"))
         Print("✅ SMT BUY | Lot=", lot, " | Ask=", ask, " | SL=", sl, " | TP=", tp);
   }

   if(signal == -1) // SELL
   {
      double recentHigh = iHigh("XAUUSD", PERIOD_M5, SwingBars + 1);
      double bid        = SymbolInfoDouble("XAUUSD", SYMBOL_BID);
      double sl         = NormalizeDouble(recentHigh + SL_Buffer * point, _Digits);
      double tp         = NormalizeDouble(bid - TP3_Points * point, _Digits);
      double slPoints   = (sl - bid) / point;
      double lot        = CalcLotSize(slPoints);

      if(trade.Sell(lot, "XAUUSD", bid, sl, tp, "SMT_SELL"))
         Print("✅ SMT SELL | Lot=", lot, " | Bid=", bid, " | SL=", sl, " | TP=", tp);
   }
}
