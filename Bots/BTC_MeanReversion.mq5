//+------------------------------------------------------------------+
//|  BTC_MeanReversion.mq5                                          |
//|  استراتيجية Mean Reversion على BTCUSDm                          |
//|  MA=20 | Z-Score=2.0 | SL×2 ATR | TP×1 ATR | Dynamic Lot      |
//+------------------------------------------------------------------+
#property strict

//── إعدادات المستخدم ──────────────────────────────────────────────
input double RiskPercent   = 1.0;   // نسبة المخاطرة لكل صفقة (%)
input int    MA_Period     = 20;    // فترة المتوسط المتحرك
input double ZScore_Entry  = 2.0;   // حد الدخول (انحراف معياري)
input int    ATR_Period    = 14;    // فترة ATR
input double SL_ATR_Mult   = 2.0;   // مضاعف ATR للـ Stop Loss
input double TP_ATR_Mult   = 1.0;   // مضاعف ATR للـ Take Profit
input double MinATR        = 200.0; // حد أدنى للـ ATR (تجنب الأسواق الهادئة)
input int    MagicNumber   = 20250001;

//── متغيرات داخلية ───────────────────────────────────────────────
string   sym;
int      atr_handle;
int      last_bar = -1;

//+------------------------------------------------------------------+
int OnInit()
{
   // اكتشاف الرمز تلقائياً
   string candidates[3] = {"BTCUSDm","BTCUSD","BTCUSDM"};
   sym = "";
   for(int c = 0; c < 3; c++)
   {
      if(SymbolSelect(candidates[c], true))
      {
         double pt = SymbolInfoDouble(candidates[c], SYMBOL_POINT);
         if(pt > 0){ sym = candidates[c]; break; }
      }
   }
   if(sym == "")
   {
      Print("❌ لم يتم إيجاد رمز BTC — تحقق من Market Watch");
      return INIT_FAILED;
   }

   atr_handle = iATR(sym, PERIOD_H1, ATR_Period);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("❌ خطأ في إنشاء مؤشر ATR");
      return INIT_FAILED;
   }

   Print("✅ BTC Mean Reversion EA — شغال على: ", sym);
   Print("   Risk:", RiskPercent, "% | MA:", MA_Period, " | Z:", ZScore_Entry);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // تنفيذ مرة واحدة لكل شمعة H1 جديدة فقط
   datetime bar_time = iTime(sym, PERIOD_H1, 0);
   if(bar_time == last_bar) return;
   last_bar = (int)bar_time;

   // لا تفتح صفقة جديدة إذا في صفقة مفتوحة
   if(HasOpenPosition()) return;

   // جلب ATR
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(atr_handle, 0, 1, 1, atr_buf) < 1) return;
   double atr = atr_buf[0];
   if(atr < MinATR) return;

   // حساب Z-Score
   double closes[];
   ArraySetAsSeries(closes, true);
   if(CopyClose(sym, PERIOD_H1, 1, MA_Period + 1, closes) < MA_Period + 1) return;

   double ma  = CalcMean(closes, MA_Period);
   double std = CalcStd(closes, MA_Period, ma);
   if(std <= 0) return;

   double current_close = closes[0];
   double zscore = (current_close - ma) / std;

   // حجم اللوت الديناميكي
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amt = balance * (RiskPercent / 100.0);
   double sl_dist  = atr * SL_ATR_Mult;
   double tp_dist  = atr * TP_ATR_Mult;
   double lot      = NormalizeLot(risk_amt / sl_dist);

   // إشارة الدخول
   if(zscore < -ZScore_Entry)
      OpenTrade(ORDER_TYPE_BUY, lot, sl_dist, tp_dist);
   else if(zscore > ZScore_Entry)
      OpenTrade(ORDER_TYPE_SELL, lot, sl_dist, tp_dist);
}

//+------------------------------------------------------------------+
//  دوال مساعدة
//+------------------------------------------------------------------+

bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
      if(PositionSelectByTicket(PositionGetTicket(i)))
         if(PositionGetString(POSITION_SYMBOL) == sym &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
   return false;
}

void OpenTrade(ENUM_ORDER_TYPE type, double lot, double sl_dist, double tp_dist)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(sym, SYMBOL_ASK)
                  : SymbolInfoDouble(sym, SYMBOL_BID);

   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = sym;
   req.volume    = lot;
   req.type      = type;
   req.price     = price;
   req.sl        = sl;
   req.tp        = tp;
   req.magic     = MagicNumber;
   req.comment   = "MeanRev_BTC";
   req.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(req, res))
      Print("❌ خطأ في الدخول: ", res.retcode, " — ", res.comment);
   else
      Print("✅ دخول ", (type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " | Lot:", lot, " | SL:", sl, " | TP:", tp,
            " | Z-Score:", DoubleToString((iClose(sym,PERIOD_H1,1)-0)/1, 2));
}

double NormalizeLot(double raw_lot)
{
   double min_lot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lot = MathFloor(raw_lot / lot_step) * lot_step;
   lot = MathMax(min_lot, MathMin(max_lot, lot));
   return NormalizeDouble(lot, 2);
}

double CalcMean(double &arr[], int period)
{
   double sum = 0;
   for(int i = 0; i < period; i++) sum += arr[i];
   return sum / period;
}

double CalcStd(double &arr[], int period, double mean)
{
   double sum = 0;
   for(int i = 0; i < period; i++) sum += MathPow(arr[i] - mean, 2);
   return MathSqrt(sum / period);
}
