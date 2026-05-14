//+------------------------------------------------------------------+
//|  MeanReversion_Multi.mq5                                        |
//|  Mean Reversion — BTC + ETH + NASDAQ                            |
//+------------------------------------------------------------------+
#property strict

//── تفعيل/تعطيل الأزواج ───────────────────────────────────────────
input bool   Trade_BTC    = true;   // ✅ تداول BTC
input bool   Trade_ETH    = true;   // ✅ تداول ETH
input bool   Trade_NASDAQ = true;   // ✅ تداول NASDAQ

//── إعدادات الاستراتيجية ─────────────────────────────────────────
input double RiskPercent  = 1.0;    // نسبة المخاطرة لكل صفقة (%)
input int    MA_Period    = 20;     // فترة المتوسط المتحرك
input double ZScore_Entry = 2.0;    // حد الدخول (انحراف معياري)
input int    ATR_Period   = 14;     // فترة ATR
input double SL_ATR_Mult  = 2.0;    // مضاعف ATR للـ Stop Loss
input double TP_ATR_Mult  = 1.0;    // مضاعف ATR للـ Take Profit
input int    MagicNumber  = 20250002;

//── أسماء الأزواج المحتملة ───────────────────────────────────────
string BTC_Names[] = {"BTCUSDm","BTCUSD","BTCUSDM"};
string ETH_Names[] = {"ETHUSDm","ETHUSD","ETHUSDM"};
string NAS_Names[] = {"USTECm","USTEC","NASDAQm","NASDAQ","US100m","US100"};

//── هيكل بيانات كل زوج ───────────────────────────────────────────
struct SymbolData
{
   string   name;
   int      atr_handle;
   datetime last_bar;
   double   min_atr;
};

SymbolData symbols[];

//+------------------------------------------------------------------+
int OnInit()
{
   if(Trade_BTC)    AddSymbol(BTC_Names,  200.0);
   if(Trade_ETH)    AddSymbol(ETH_Names,  5.0);
   if(Trade_NASDAQ) AddSymbol(NAS_Names,  20.0);

   if(ArraySize(symbols) == 0)
   {
      Print("❌ لم يتم تفعيل أي زوج أو لم يتم إيجاده في Market Watch");
      return INIT_FAILED;
   }

   Print("🚀 MeanReversion شغال | Risk:", RiskPercent, "% | Z:", ZScore_Entry);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < ArraySize(symbols); i++)
      if(symbols[i].atr_handle != INVALID_HANDLE)
         IndicatorRelease(symbols[i].atr_handle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   for(int i = 0; i < ArraySize(symbols); i++)
      ProcessSymbol(symbols[i]);
}

//+------------------------------------------------------------------+
void AddSymbol(string &candidates[], double min_atr)
{
   string sym = FindSymbol(candidates);
   if(sym == "") { Print("⚠️ لم يتم إيجاد الزوج في Market Watch"); return; }

   int h = iATR(sym, PERIOD_H1, ATR_Period);
   if(h == INVALID_HANDLE) { Print("⚠️ خطأ ATR: ", sym); return; }

   int idx = ArraySize(symbols);
   ArrayResize(symbols, idx + 1);
   symbols[idx].name       = sym;
   symbols[idx].atr_handle = h;
   symbols[idx].last_bar   = 0;
   symbols[idx].min_atr    = min_atr;

   Print("✅ جاهز: ", sym);
}

//+------------------------------------------------------------------+
void ProcessSymbol(SymbolData &sym)
{
   datetime bar_time = iTime(sym.name, PERIOD_H1, 0);
   if(bar_time == sym.last_bar) return;
   sym.last_bar = bar_time;

   if(HasOpenPosition(sym.name)) return;

   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(sym.atr_handle, 0, 1, 1, atr_buf) < 1) return;
   double atr = atr_buf[0];
   if(atr < sym.min_atr) return;

   double closes[];
   ArraySetAsSeries(closes, true);
   if(CopyClose(sym.name, PERIOD_H1, 1, MA_Period+1, closes) < MA_Period+1) return;

   double ma     = CalcMean(closes, MA_Period);
   double std    = CalcStd(closes, MA_Period, ma);
   if(std <= 0) return;

   double zscore = (closes[0] - ma) / std;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = balance * (RiskPercent / 100.0);
   double sl_dist = atr * SL_ATR_Mult;
   double tp_dist = atr * TP_ATR_Mult;
   double lot     = NormalizeLot(sym.name, risk / sl_dist);

   if(zscore < -ZScore_Entry)
      OpenTrade(sym.name, ORDER_TYPE_BUY, lot, sl_dist, tp_dist);
   else if(zscore > ZScore_Entry)
      OpenTrade(sym.name, ORDER_TYPE_SELL, lot, sl_dist, tp_dist);
}

//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol)
{
   for(int i = 0; i < PositionsTotal(); i++)
      if(PositionSelectByTicket(PositionGetTicket(i)))
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
   return false;
}

//+------------------------------------------------------------------+
void OpenTrade(string symbol, ENUM_ORDER_TYPE type, double lot, double sl_dist, double tp_dist)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   double price  = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol,SYMBOL_ASK) : SymbolInfoDouble(symbol,SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double sl     = NormalizeDouble((type==ORDER_TYPE_BUY) ? price-sl_dist : price+sl_dist, digits);
   double tp     = NormalizeDouble((type==ORDER_TYPE_BUY) ? price+tp_dist : price-tp_dist, digits);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = symbol;
   req.volume       = lot;
   req.type         = type;
   req.price        = price;
   req.sl           = sl;
   req.tp           = tp;
   req.magic        = MagicNumber;
   req.comment      = "MR_" + symbol;
   req.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(req, res))
      Print("❌ خطأ [", symbol, "]: ", res.retcode);
   else
      Print("✅ ", (type==ORDER_TYPE_BUY?"BUY":"SELL"), " [", symbol, "]",
            " | Lot:", lot, " | SL:", sl, " | TP:", tp);
}

//+------------------------------------------------------------------+
string FindSymbol(string &candidates[])
{
   for(int i = 0; i < ArraySize(candidates); i++)
      if(SymbolSelect(candidates[i], true))
         if(SymbolInfoDouble(candidates[i], SYMBOL_POINT) > 0)
            return candidates[i];
   return "";
}

double NormalizeLot(string symbol, double raw)
{
   double mn   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double lot  = MathFloor(raw/step)*step;
   return NormalizeDouble(MathMax(mn, MathMin(mx, lot)), 2);
}

double CalcMean(double &arr[], int period)
{
   double s=0; for(int i=0;i<period;i++) s+=arr[i]; return s/period;
}

double CalcStd(double &arr[], int period, double mean)
{
   double s=0; for(int i=0;i<period;i++) s+=MathPow(arr[i]-mean,2);
   return MathSqrt(s/period);
}
