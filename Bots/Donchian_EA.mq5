//+------------------------------------------------------------------+
//|  Donchian Breakout EA                                            |
//|  استراتيجية كسر القناة - بدون AI                                |
//+------------------------------------------------------------------+
#property copyright "Trading Bot"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ==========================================
// إعدادات
// ==========================================
input string   BOT_TOKEN     = "8764834987:AAHZ_dC1TmEfTO-Pbmd1AyZQcuHsNFQZy64";
input string   CHAT_ID       = "6652508619";
input int      DonchianPeriod = 20;   // فترة القناة
input int      SLPeriod       = 10;   // فترة الـ SL
input double   RiskPercent    = 1.0;  // نسبة المخاطرة
input double   MaxDailyLoss   = 2.0;  // أقصى خسارة يومية %
input double   TrailPoints    = 50;   // Trailing Stop بالنقاط
input int      MagicNumber    = 20250101;
input bool     TradeXAUUSD    = true;
input bool     TradeBTCUSD    = true;
input bool     TradeETHUSD    = true;
input bool     TradeUSDJPY    = true;
input bool     TradeUSTEC     = true;
input bool     TradeUSOIL     = true;

// ==========================================
// متغيرات
// ==========================================
CTrade trade;
string symbols[];
double dayStartBalance = 0;
datetime lastDay       = 0;
datetime lastReport    = 0;
bool     stoppedToday  = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   // بناء قائمة الأزواج
   int count = 0;
   ArrayResize(symbols, 6);
   if(TradeXAUUSD) { symbols[count] = "XAUUSD"; count++; }
   if(TradeBTCUSD) { symbols[count] = "BTCUSD"; count++; }
   if(TradeETHUSD) { symbols[count] = "ETHUSD"; count++; }
   if(TradeUSDJPY) { symbols[count] = "USDJPY"; count++; }
   if(TradeUSTEC)  { symbols[count] = "USTEC";  count++; }
   if(TradeUSOIL)  { symbols[count] = "USOIL";  count++; }
   ArrayResize(symbols, count);

   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDay = TimeCurrent();

   SendTelegram("✅ Donchian EA Started\nSymbols: " + GetSymbolList() +
                "\nBalance: $" + DoubleToString(dayStartBalance, 2) +
                "\nRisk: " + DoubleToString(RiskPercent, 1) + "%");

   Print("✅ Donchian EA started | Symbols: ", count);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // تصفير يوم جديد
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   MqlDateTime dtLast;
   TimeToStruct(lastDay, dtLast);

   if(dt.day != dtLast.day)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double pnl = ((balance - dayStartBalance) / dayStartBalance) * 100;

      SendTelegram("📊 Daily Report\nDate: " + TimeToString(TimeCurrent(), TIME_DATE) +
                   "\nStart: $" + DoubleToString(dayStartBalance, 2) +
                   "\nEnd: $" + DoubleToString(balance, 2) +
                   "\nP&L: " + (pnl >= 0 ? "+" : "") + DoubleToString(pnl, 2) + "%");

      dayStartBalance = balance;
      lastDay = TimeCurrent();
      stoppedToday = false;
      Print("📅 New day reset | Balance: $", balance);
   }

   // تحقق من الخسارة اليومية
   if(!stoppedToday)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double dailyPnl = ((balance - dayStartBalance) / dayStartBalance) * 100;
      if(dailyPnl <= -MaxDailyLoss)
      {
         stoppedToday = true;
         SendTelegram("🛑 Daily loss limit reached: " + DoubleToString(dailyPnl, 2) + "%\nStopped for today.");
         Print("🛑 Daily loss limit reached: ", dailyPnl, "%");
         return;
      }
   }

   if(stoppedToday) return;

   // إدارة الصفقات المفتوحة (Trailing Stop)
   ManagePositions();

   // تحليل وتداول
   for(int i = 0; i < ArraySize(symbols); i++)
      AnalyzeAndTrade(symbols[i]);
}

//+------------------------------------------------------------------+
// التحليل والتداول
//+------------------------------------------------------------------+
void AnalyzeAndTrade(string symbol)
{
   // تحقق إذا في صفقة مفتوحة
   if(HasOpenPosition(symbol)) return;

   // جلب بيانات الشموع
   MqlRates rates[];
   int copied = CopyRates(symbol, PERIOD_H1, 0, DonchianPeriod + 5, rates);
   if(copied < DonchianPeriod + 2) return;

   int total = ArraySize(rates);

   // حساب Donchian Channel (آخر DonchianPeriod شمعة مغلقة)
   double highest = -DBL_MAX;
   double lowest  =  DBL_MAX;
   for(int i = 1; i <= DonchianPeriod; i++)
   {
      if(rates[total - 1 - i].high > highest) highest = rates[total - 1 - i].high;
      if(rates[total - 1 - i].low  < lowest)  lowest  = rates[total - 1 - i].low;
   }

   // حساب SL من آخر SLPeriod شمعة
   double slHigh = -DBL_MAX;
   double slLow  =  DBL_MAX;
   for(int i = 1; i <= SLPeriod; i++)
   {
      if(rates[total - 1 - i].high > slHigh) slHigh = rates[total - 1 - i].high;
      if(rates[total - 1 - i].low  < slLow)  slLow  = rates[total - 1 - i].low;
   }

   // حساب ATR كفلتر
   double atr[];
   if(CopyBuffer(iATR(symbol, PERIOD_H1, 14), 0, 1, 20, atr) < 20) return;
   double currentATR = atr[0];
   double avgATR = 0;
   for(int i = 0; i < 20; i++) avgATR += atr[i];
   avgATR /= 20;

   // فلتر: ATR لازم فوق المتوسط
   if(currentATR < avgATR * 0.8) return;

   // السعر الحالي
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   // إشارة BUY - كسر الأعلى
   if(ask > highest)
   {
      double sl = NormalizeDouble(slLow, digits);
      double slDist = ask - sl;
      if(slDist <= 0) return;

      double tp = NormalizeDouble(ask + slDist * 2, digits);
      double lot = CalcLot(symbol, slDist);
      if(lot <= 0) return;

      // تحقق من minimum stops
      double minStop = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(ask - sl < minStop) sl = NormalizeDouble(ask - minStop * 1.5, digits);
      if(tp - ask < minStop) tp = NormalizeDouble(ask + minStop * 3, digits);

      if(trade.Buy(lot, symbol, ask, sl, tp, "Donchian BUY"))
      {
         string msg = "🟢 Donchian BUY\nSymbol: " + symbol +
                      "\nLot: " + DoubleToString(lot, 2) +
                      "\nEntry: " + DoubleToString(ask, digits) +
                      "\nSL: " + DoubleToString(sl, digits) +
                      "\nTP: " + DoubleToString(tp, digits) +
                      "\nATR: " + DoubleToString(currentATR, digits);
         SendTelegram(msg);
         Print("🟢 BUY | ", symbol, " | Lot:", lot, " | Entry:", ask, " | SL:", sl, " | TP:", tp);
      }
   }

   // إشارة SELL - كسر الأدنى
   else if(bid < lowest)
   {
      double sl = NormalizeDouble(slHigh, digits);
      double slDist = sl - bid;
      if(slDist <= 0) return;

      double tp = NormalizeDouble(bid - slDist * 2, digits);
      double lot = CalcLot(symbol, slDist);
      if(lot <= 0) return;

      double minStop = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(sl - bid < minStop) sl = NormalizeDouble(bid + minStop * 1.5, digits);
      if(bid - tp < minStop) tp = NormalizeDouble(bid - minStop * 3, digits);

      if(trade.Sell(lot, symbol, bid, sl, tp, "Donchian SELL"))
      {
         string msg = "🔴 Donchian SELL\nSymbol: " + symbol +
                      "\nLot: " + DoubleToString(lot, 2) +
                      "\nEntry: " + DoubleToString(bid, digits) +
                      "\nSL: " + DoubleToString(sl, digits) +
                      "\nTP: " + DoubleToString(tp, digits) +
                      "\nATR: " + DoubleToString(currentATR, digits);
         SendTelegram(msg);
         Print("🔴 SELL | ", symbol, " | Lot:", lot, " | Entry:", bid, " | SL:", sl, " | TP:", tp);
      }
   }
}

//+------------------------------------------------------------------+
// حساب الـ Lot
//+------------------------------------------------------------------+
double CalcLot(string symbol, double slDistance)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100.0);
   double tickValue  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0 || slDistance <= 0) return 0;

   double lot = riskAmount / ((slDistance / tickSize) * tickValue);

   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(lot, maxLot));
   lot = MathMin(lot, 2.0); // حد أقصى 2.0

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
// Trailing Stop
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string sym    = PositionGetString(POSITION_SYMBOL);
      double price  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      int    type   = (int)PositionGetInteger(POSITION_TYPE);
      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      double trail  = TrailPoints * point;

      if(type == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(price - trail, digits);
         if(newSL > sl + point)
            trade.PositionModify(ticket, newSL, tp);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double newSL = NormalizeDouble(price + trail, digits);
         if(newSL < sl - point || sl == 0)
            trade.PositionModify(ticket, newSL, tp);
      }
   }
}

//+------------------------------------------------------------------+
// تحقق من صفقة مفتوحة
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// إرسال Telegram
//+------------------------------------------------------------------+
void SendTelegram(string message)
{
   string url  = "https://api.telegram.org/bot" + BOT_TOKEN + "/sendMessage";
   string body = "{\"chat_id\":\"" + CHAT_ID + "\",\"text\":\"" + message + "\"}";

   char data[], result[];
   StringToCharArray(body, data, 0, StringLen(body));
   string headers = "Content-Type: application/json\r\n";
   string responseHeaders;
   int res = WebRequest("POST", url, headers, 5000, data, result, responseHeaders);
   if(res == 200)
      Print("✅ Telegram sent");
   else
      Print("❌ Telegram error: ", GetLastError());
}

//+------------------------------------------------------------------+
string GetSymbolList()
{
   string list = "";
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      if(i > 0) list += ", ";
      list += symbols[i];
   }
   return list;
}
//+------------------------------------------------------------------+
