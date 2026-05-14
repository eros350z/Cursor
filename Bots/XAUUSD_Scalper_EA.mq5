//+------------------------------------------------------------------+
//|                                       XAUUSD_Scalper_EA.mq5     |
//|                                  Scalping EA for XAUUSD M5      |
//+------------------------------------------------------------------+
#property copyright "AI Trading"
#property version   "2.0"
#property strict

#include <Trade\Trade.mqh>

input double   RiskPercent     = 1.0;    // Risk % per trade
input int      RSI_Period      = 14;     // RSI Period
input int      EMA_Fast        = 21;     // EMA Fast
input int      EMA_Slow        = 50;     // EMA Slow
input double   TP1_Points      = 1000;   // TP1 (10 pip)
input double   TP2_Points      = 2000;   // TP2 (20 pip)
input double   TP3_Points      = 3000;   // TP3 (30 pip)
input double   TP1_ClosePerc   = 25;     // % close at TP1
input double   TP2_ClosePerc   = 25;     // % close at TP2
input double   TP3_ClosePerc   = 25;     // % close at TP3
input double   Trailing_Points = 1500;   // Trailing (15 pip)
input double   SL_Points       = 1500;   // SL (15 pip)
input int      ServerOffset    = 3;      // Server to Kuwait offset
input int      MagicNumber     = 123456;

CTrade trade;
int rsiHandle, emaFastHandle, emaSlowHandle;

struct TradeState { ulong ticket; bool tp1Hit; bool tp2Hit; bool tp3Hit; };
TradeState tradeStates[];

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

double CalcLotSize(double slPoints)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100.0;
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(slPoints <= 0 || tickValue <= 0) return minLot;
   double slMoney = slPoints * point / tickSize * tickValue;
   double lot     = riskAmount / slMoney;
   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return NormalizeDouble(lot, 2);
}

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
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   return count;
}

void PartialClose(ulong ticket, double closePercent, double totalLot)
{
   double closeLot = NormalizeDouble(totalLot * closePercent / 100.0, 2);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   closeLot = MathFloor(closeLot / lotStep) * lotStep;
   if(closeLot < minLot) return;
   trade.PositionClosePartial(ticket, closeLot);
}

void ManageTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      int    type      = (int)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double lot       = PositionGetDouble(POSITION_VOLUME);
      double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      int    idx    = GetStateIndex(ticket);
      double profit = (type == POSITION_TYPE_BUY) ?
                      (bid - openPrice) / point :
                      (openPrice - ask) / point;

      if(profit >= TP1_Points && !tradeStates[idx].tp1Hit)
      {
         PartialClose(ticket, TP1_ClosePerc, lot);
         trade.PositionModify(ticket, openPrice, currentTP);
         tradeStates[idx].tp1Hit = true;
         Print("TP1 ✅ 25% + Breakeven | Ticket=", ticket);
      }
      if(profit >= TP2_Points && !tradeStates[idx].tp2Hit)
      {
         PartialClose(ticket, TP2_ClosePerc, lot);
         tradeStates[idx].tp2Hit = true;
         Print("TP2 ✅ 25% | Ticket=", ticket);
      }
      if(profit >= TP3_Points && !tradeStates[idx].tp3Hit)
      {
         PartialClose(ticket, TP3_ClosePerc, lot);
         tradeStates[idx].tp3Hit = true;
         Print("TP3 ✅ 25% + Trailing | Ticket=", ticket);
      }
      if(tradeStates[idx].tp3Hit)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double newSL = NormalizeDouble(bid - Trailing_Points * point, _Digits);
            if(newSL > currentSL) trade.PositionModify(ticket, newSL, currentTP);
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

int OnInit()
{
   rsiHandle     = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   emaFastHandle = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   if(rsiHandle == INVALID_HANDLE || emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE)
   {
      Print("❌ Error creating indicators");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int kuwaitHour = (dt.hour + ServerOffset) % 24;
   Print("✅ Scalper EA v2.0 | Server: ", dt.hour, " | Kuwait: ", kuwaitHour);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(rsiHandle);
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
}

void OnTick()
{
   ManageTrades();

   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   if(!IsTradingAllowed()) return;
   if(CountTrades() >= 3) return;

   double rsi[2], emaFast[2], emaSlow[2];
   if(CopyBuffer(rsiHandle,     0, 1, 2, rsi)     < 2) return;
   if(CopyBuffer(emaFastHandle, 0, 1, 2, emaFast) < 2) return;
   if(CopyBuffer(emaSlowHandle, 0, 1, 2, emaSlow) < 2) return;

   double currentRSI  = rsi[0];
   double prevRSI     = rsi[1];
   double fastEMA     = emaFast[0];
   double slowEMA     = emaSlow[0];
   double point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // BUY: EMA21 > EMA50 (uptrend) + RSI crossed above 50 from below
   if(fastEMA > slowEMA && prevRSI < 50 && currentRSI >= 50)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - SL_Points * point, _Digits);
      double tp  = NormalizeDouble(ask + TP3_Points * point, _Digits);
      double lot = CalcLotSize(SL_Points);
      if(trade.Buy(lot, _Symbol, ask, sl, tp, "SCALP_BUY"))
         Print("✅ BUY | RSI=", DoubleToString(currentRSI,1), " | EMA21>EMA50");
   }

   // SELL: EMA21 < EMA50 (downtrend) + RSI crossed below 50 from above
   if(fastEMA < slowEMA && prevRSI > 50 && currentRSI <= 50)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + SL_Points * point, _Digits);
      double tp  = NormalizeDouble(bid - TP3_Points * point, _Digits);
      double lot = CalcLotSize(SL_Points);
      if(trade.Sell(lot, _Symbol, bid, sl, tp, "SCALP_SELL"))
         Print("✅ SELL | RSI=", DoubleToString(currentRSI,1), " | EMA21<EMA50");
   }
}
