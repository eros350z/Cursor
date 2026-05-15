//+------------------------------------------------------------------+
//|                       Crypto_SMT_Pro.mq5                         |
//|    BTC + ETH  Smart Money Trap (SMT) Divergence                  |
//|    24/7 Crypto | 4-Phase Partial Profit | ATR-Adaptive Trailing   |
//|    إصدار 1.0 - مايو 2026                                         |
//+------------------------------------------------------------------+
//|  الاستراتيجية:                                                   |
//|  1. SMT Divergence بين BTC و ETH على H1                         |
//|     - Bullish: BTC يعمل Low أدنى لكن ETH يعمل Low أعلى          |
//|       → الدببة محاصرون على BTC → ارتداد صاعد                   |
//|     - Bearish: BTC يعمل High أعلى لكن ETH يعمل High أدنى        |
//|       → الثيران محاصرون على BTC → ارتداد هابط                  |
//|  2. فلتر ترند H4 EMA200 + ADX                                    |
//|  3. فلتر نسبة ETH/BTC (leading indicator فريد)                  |
//|  4. نظام 4-مراحل لإغلاق جزئي واحتجاز الـ Runner                 |
//|     TP1=1.5R (20%) → Breakeven                                   |
//|     TP2=3.0R (30%) → Trailing ATR×2                             |
//|     TP3=5.0R (30%) → Trailing ATR×0.5 (Runner)                  |
//|     الـ 20% الأخيرة تبقى حتى يوقفها الـ Trailing                |
//|  5. نظام Volatility Regime تلقائي                                |
//+------------------------------------------------------------------+
#property copyright "Crypto SMT Pro v1.0"
#property version   "1.00"
#property description "BTCUSD+ETHUSD | SMT Divergence | 4-Phase Profit | Adaptive Trailing"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//|                       INPUT PARAMETERS                           |
//+------------------------------------------------------------------+
input group "=== الأزواج ==="
input string   Sym_BTC          = "BTCUSD";   // رمز البيتكوين
input string   Sym_ETH          = "ETHUSD";   // رمز الإيثيريوم
input string   Sym_Trade        = "BTCUSD";   // الزوج المتداول (BTC أو ETH)

input group "=== إدارة المخاطر ==="
input double   RiskPercent      = 1.0;        // نسبة المخاطرة % per trade
input double   MaxLotSize       = 1.0;        // أقصى حجم لوت
input double   MaxDailyLossPct  = 3.0;        // أقصى خسارة يومية %
input double   MaxTotalDDPct    = 10.0;       // أقصى drawdown كلي %

input group "=== ATR والإطارات الزمنية ==="
input ENUM_TIMEFRAMES TF_Entry   = PERIOD_H1; // إطار الدخول
input ENUM_TIMEFRAMES TF_Trend   = PERIOD_H4; // إطار الترند
input int      ATR_Period        = 14;         // فترة ATR
input double   ATR_SL_Multi      = 1.5;        // SL = ATR × 1.5
input int      ATR_Avg_Period    = 20;         // فترة حساب متوسط ATR (Regime)
input double   VolHigh_Ratio     = 1.6;        // High Vol: ATR > متوسط × 1.6
input double   VolLow_Ratio      = 0.6;        // Low Vol: ATR < متوسط × 0.6
input double   VolSpike_Ratio    = 2.5;        // Spike: ATR > متوسط × 2.5 → تجنب

input group "=== SMT Divergence ==="
input int      SwingBars         = 8;          // أشرطة Swing من كل جانب
input int      SMT_LookBack      = 60;         // البحث في آخر X شمعة H1
input double   MinDivPct         = 0.20;       // أدنى انحراف % للـ SMT

input group "=== فلاتر الترند ==="
input int      EMA_Trend_Period  = 200;        // EMA الترند H4
input int      EMA_Entry_Period  = 21;         // EMA الدخول H1
input int      ADX_Period        = 14;         // فترة ADX
input double   ADX_Min           = 20.0;       // ADX أدنى للدخول

input group "=== فلتر نسبة ETH/BTC (Leading Indicator) ==="
input bool     UseRatioFilter    = true;       // تفعيل فلتر نسبة ETH/BTC
input int      RatioBars         = 6;          // حساب تغير النسبة خلال X ساعات
input double   RatioThreshold    = 0.30;       // حد الانحراف % لتأكيد الاتجاه

input group "=== 4-Phase Partial Profit ==="
input double   TP1_R             = 1.5;        // TP1 = SL × 1.5R  → 20% إغلاق
input double   TP2_R             = 3.0;        // TP2 = SL × 3.0R  → 30% إغلاق
input double   TP3_R             = 5.0;        // TP3 = SL × 5.0R  → 30% إغلاق
input double   TP1_ClosePct      = 20.0;       // إغلاق % عند TP1 + Breakeven
input double   TP2_ClosePct      = 30.0;       // إغلاق % عند TP2 + Trail×2 ATR
input double   TP3_ClosePct      = 30.0;       // إغلاق % عند TP3 + Trail×0.5 Runner
// الـ 20% الباقية: Runner مع ATR×0.5 حتى يوقفها الـ Trailing

input group "=== Trailing Multipliers ==="
input double   Trail_Phase2      = 2.0;        // Trailing بعد TP2 = ATR × 2.0
input double   Trail_Runner      = 0.5;        // Trailing الـ Runner = ATR × 0.5

input group "=== حماية الكريبتو 24/7 ==="
input double   MaxSpreadBTC      = 100.0;      // أقصى سبريد BTC بالدولار
input double   MaxSpreadETH      = 10.0;       // أقصى سبريد ETH بالدولار
input bool     AvoidSundayOpen   = true;       // تجنب أول ساعتين الأحد (00-02 GMT)
input bool     AvoidVolSpike     = true;       // تجنب الدخول عند ATR Spike

input group "=== إعدادات EA ==="
input int      MagicNumber       = 20260515;
input int      Slippage          = 300;        // تمرير للكريبتو (≈3$)

//+------------------------------------------------------------------+
//|                      GLOBAL VARIABLES                            |
//+------------------------------------------------------------------+

// Indicator handles
int h_ATR_Entry, h_ATR_Trend;
int h_EMA_Trend_BTC, h_EMA_Trend_ETH;
int h_EMA_Entry;
int h_ADX;

// Per-trade state management
struct TradeState {
   ulong  ticket;
   double slDistance;   // SL distance at entry (for calculating R multiples)
   bool   tp1Hit;       // TP1 (1.5R) reached → Breakeven set
   bool   tp2Hit;       // TP2 (3.0R) reached → Trail Phase2 active
   bool   tp3Hit;       // TP3 (5.0R) reached → Runner mode active
   int    trailPhase;   // 0=none, 1=BE only, 2=Trail×2, 3=Trail×0.5 Runner
};
TradeState tradeStates[];

// Drawdown protection
double   startEquity    = 0;
double   dayStartEq     = 0;
datetime lastDayReset   = 0;
bool     protectionHit  = false;

// Bar tracking (entry logic only runs on new H1 bar)
datetime lastBarEntry   = 0;

// Dashboard object name prefix
string PRE = "CSMT_";

//+------------------------------------------------------------------+
//|                           OnInit                                 |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Add symbols to Market Watch
   SymbolSelect(Sym_BTC,   true);
   SymbolSelect(Sym_ETH,   true);
   SymbolSelect(Sym_Trade, true);
   Sleep(300);

   // Validate symbols exist
   if(SymbolInfoDouble(Sym_BTC, SYMBOL_POINT) == 0 ||
      SymbolInfoDouble(Sym_ETH, SYMBOL_POINT) == 0) {
      Print("ERROR: Symbol not found. Check: ", Sym_BTC, " / ", Sym_ETH);
      return INIT_FAILED;
   }

   // Create indicator handles on the traded symbol
   h_ATR_Entry      = iATR(Sym_Trade, TF_Entry,  ATR_Period);
   h_ATR_Trend      = iATR(Sym_Trade, TF_Trend,  ATR_Period);
   h_EMA_Trend_BTC  = iMA(Sym_BTC,   TF_Trend,  EMA_Trend_Period, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Trend_ETH  = iMA(Sym_ETH,   TF_Trend,  EMA_Trend_Period, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Entry      = iMA(Sym_Trade,  TF_Entry,  EMA_Entry_Period, 0, MODE_EMA, PRICE_CLOSE);
   h_ADX            = iADX(Sym_Trade, TF_Entry,  ADX_Period);

   if(h_ATR_Entry     == INVALID_HANDLE || h_ATR_Trend    == INVALID_HANDLE ||
      h_EMA_Trend_BTC == INVALID_HANDLE || h_EMA_Trend_ETH == INVALID_HANDLE ||
      h_EMA_Entry     == INVALID_HANDLE || h_ADX          == INVALID_HANDLE) {
      Print("ERROR: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   startEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStartEq   = startEquity;
   lastDayReset = 0;

   CreateDashboard();

   Print("=========================================================");
   Print(" CRYPTO SMT PRO v1.0 - STARTED");
   Print(" BTC: ", Sym_BTC, "  |  ETH: ", Sym_ETH, "  |  Trading: ", Sym_Trade);
   Print(" Risk: ", RiskPercent, "%  |  SL: ", ATR_SL_Multi, "×ATR");
   Print(" SMT: SwingBars=", SwingBars, "  LookBack=", SMT_LookBack, "  MinDiv=", MinDivPct, "%");
   Print(" 4-Phase: TP1=", TP1_R, "R(", TP1_ClosePct, "%)  TP2=", TP2_R,
         "R(", TP2_ClosePct, "%)  TP3=", TP3_R, "R(", TP3_ClosePct,
         "%)  Runner=", 100 - TP1_ClosePct - TP2_ClosePct - TP3_ClosePct, "%");
   Print(" Trailing: Phase2=ATR×", Trail_Phase2, "  Runner=ATR×", Trail_Runner);
   Print("=========================================================");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|                          OnDeinit                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   IndicatorRelease(h_ATR_Entry);
   IndicatorRelease(h_ATR_Trend);
   IndicatorRelease(h_EMA_Trend_BTC);
   IndicatorRelease(h_EMA_Trend_ETH);
   IndicatorRelease(h_EMA_Entry);
   IndicatorRelease(h_ADX);
   ObjectsDeleteAll(0, PRE);
}

//+------------------------------------------------------------------+
//|                           OnTick                                 |
//+------------------------------------------------------------------+
void OnTick() {
   // Circuit breaker: check drawdown protection every tick
   if(!DrawdownCheck()) return;

   // Position management runs on every tick (trailing, partial closes)
   ManageOpenTrades();

   // Entry logic only on a new H1 bar
   datetime curBar = iTime(Sym_Trade, TF_Entry, 0);
   if(curBar == lastBarEntry) {
      UpdateDashboard();
      return;
   }
   lastBarEntry = curBar;

   // Only one active position at a time
   if(HasOpenPosition()) {
      UpdateDashboard();
      return;
   }

   // --- Crypto-specific filters ---
   if(AvoidSundayOpen && IsSundayOpen()) {
      UpdateDashboard();
      return;
   }

   if(!SpreadOK()) {
      UpdateDashboard();
      return;
   }

   // Volatility regime check
   int regime = GetVolatilityRegime();
   if(AvoidVolSpike && regime == 3) {
      Print("Vol spike detected (ATR×", DoubleToString(VolSpike_Ratio, 1), ") - skipping entry");
      UpdateDashboard();
      return;
   }

   // ETH/BTC ratio filter (optional leading indicator)
   int ratioSig = 0;
   if(UseRatioFilter) ratioSig = GetETHBTCRatioSignal();

   // Main SMT divergence signal
   int smtSig = GetSMTSignal();
   if(smtSig == 0) {
      UpdateDashboard();
      return;
   }

   // If ratio filter gives opposing signal, skip
   if(UseRatioFilter && ratioSig != 0 && ratioSig != smtSig) {
      Print("SMT signal BLOCKED by ETH/BTC ratio filter | SMT:", smtSig, " Ratio:", ratioSig);
      UpdateDashboard();
      return;
   }

   // Open the trade
   OpenTrade(smtSig, regime);
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//|   SMT DIVERGENCE SIGNAL DETECTION                                |
//|                                                                  |
//|   Bullish SMT: BTC makes a Lower Low  but ETH makes Higher Low  |
//|   → Smart money trapped bears on BTC → bounce expected          |
//|                                                                  |
//|   Bearish SMT: BTC makes a Higher High but ETH makes Lower High |
//|   → Smart money trapped bulls on BTC → drop expected            |
//+------------------------------------------------------------------+
int GetSMTSignal() {
   // --- Filter 1: H4 EMA200 Trend ---
   double btcTrEMA[], ethTrEMA[];
   ArraySetAsSeries(btcTrEMA, true);
   ArraySetAsSeries(ethTrEMA, true);
   if(CopyBuffer(h_EMA_Trend_BTC, 0, 0, 3, btcTrEMA) < 3) return 0;
   if(CopyBuffer(h_EMA_Trend_ETH, 0, 0, 3, ethTrEMA) < 3) return 0;

   double btcH4Close = iClose(Sym_BTC, TF_Trend, 1);
   double ethH4Close = iClose(Sym_ETH, TF_Trend, 1);

   bool btcBull = (btcH4Close > btcTrEMA[0]);
   bool btcBear = (btcH4Close < btcTrEMA[0]);
   bool ethBull = (ethH4Close > ethTrEMA[0]);
   bool ethBear = (ethH4Close < ethTrEMA[0]);

   // --- Filter 2: ADX momentum ---
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(h_ADX, 0, 0, 3, adxBuf) < 3) return 0;
   bool adxOK = (adxBuf[0] >= ADX_Min);

   // --- Filter 3: H1 EMA21 context ---
   double emaEntry[];
   ArraySetAsSeries(emaEntry, true);
   if(CopyBuffer(h_EMA_Entry, 0, 0, 5, emaEntry) < 5) return 0;
   double tradeClose = iClose(Sym_Trade, TF_Entry, 1);

   // --- Scan Swing Lows for Bullish SMT ---
   double btcLow1 = 0, btcLow2 = 0;
   double ethLow1 = 0, ethLow2 = 0;

   for(int i = SwingBars + 1; i <= SMT_LookBack; i++) {
      double sl = GetSwingLow(Sym_BTC, TF_Entry, i);
      if(sl > 0) {
         if(btcLow1 == 0) {
            btcLow1 = sl;
            ethLow1 = iLow(Sym_ETH, TF_Entry, i);
         } else if(btcLow2 == 0) {
            btcLow2 = sl;
            ethLow2 = iLow(Sym_ETH, TF_Entry, i);
            break;
         }
      }
   }

   // --- Scan Swing Highs for Bearish SMT ---
   double btcHigh1 = 0, btcHigh2 = 0;
   double ethHigh1 = 0, ethHigh2 = 0;

   for(int i = SwingBars + 1; i <= SMT_LookBack; i++) {
      double sh = GetSwingHigh(Sym_BTC, TF_Entry, i);
      if(sh > 0) {
         if(btcHigh1 == 0) {
            btcHigh1 = sh;
            ethHigh1 = iHigh(Sym_ETH, TF_Entry, i);
         } else if(btcHigh2 == 0) {
            btcHigh2 = sh;
            ethHigh2 = iHigh(Sym_ETH, TF_Entry, i);
            break;
         }
      }
   }

   // ============================================================
   // BULLISH SMT
   // BTC: newer low < older low  (Lower Low)
   // ETH: at BTC low1 bar, ETH was HIGHER than at BTC low2 bar
   // → Divergence = smart money defending ETH while BTC fakes lower
   // ============================================================
   if(btcLow1 > 0 && btcLow2 > 0 && ethLow1 > 0 && ethLow2 > 0) {
      bool btcLowerLow  = (btcLow1 < btcLow2);
      bool ethHigherLow = (ethLow1 > ethLow2);
      double divPct     = MathAbs(btcLow1 - btcLow2) / btcLow2 * 100.0;

      if(btcLowerLow && ethHigherLow && divPct >= MinDivPct) {
         bool trendOK = (btcBull || ethBull);
         // Price should still be near EMA21 (not already far from it)
         bool priceOK = (tradeClose > emaEntry[1] * 0.992);

         if(trendOK && adxOK && priceOK) {
            Print("BULLISH SMT | BTC Lows: ", DoubleToString(btcLow1, 0),
                  " < ", DoubleToString(btcLow2, 0),
                  "  |  ETH Lows: ", DoubleToString(ethLow1, 2),
                  " > ", DoubleToString(ethLow2, 2),
                  "  |  Div: ", DoubleToString(divPct, 2), "%");
            return 1;
         }
      }
   }

   // ============================================================
   // BEARISH SMT
   // BTC: newer high > older high  (Higher High)
   // ETH: at BTC high1 bar, ETH was LOWER than at BTC high2 bar
   // → Divergence = smart money distributing on BTC while ETH fails
   // ============================================================
   if(btcHigh1 > 0 && btcHigh2 > 0 && ethHigh1 > 0 && ethHigh2 > 0) {
      bool btcHigherHigh = (btcHigh1 > btcHigh2);
      bool ethLowerHigh  = (ethHigh1 < ethHigh2);
      double divPct      = MathAbs(btcHigh1 - btcHigh2) / btcHigh2 * 100.0;

      if(btcHigherHigh && ethLowerHigh && divPct >= MinDivPct) {
         bool trendOK = (btcBear || ethBear);
         bool priceOK = (tradeClose < emaEntry[1] * 1.008);

         if(trendOK && adxOK && priceOK) {
            Print("BEARISH SMT | BTC Highs: ", DoubleToString(btcHigh1, 0),
                  " > ", DoubleToString(btcHigh2, 0),
                  "  |  ETH Highs: ", DoubleToString(ethHigh1, 2),
                  " < ", DoubleToString(ethHigh2, 2),
                  "  |  Div: ", DoubleToString(divPct, 2), "%");
            return -1;
         }
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//|   ETH/BTC RATIO SIGNAL (Unique Leading Indicator)                |
//|                                                                  |
//|   When ETH outperforms BTC over the last N hours:               |
//|     → Crypto market is Risk-ON → bullish bias for BTC           |
//|   When ETH underperforms BTC:                                    |
//|     → Crypto market is Risk-OFF → bearish bias for BTC          |
//|                                                                  |
//|   This is the only bot in the collection using this concept.    |
//+------------------------------------------------------------------+
int GetETHBTCRatioSignal() {
   int need = RatioBars + 2;

   double ethCl[], btcCl[];
   ArraySetAsSeries(ethCl, true);
   ArraySetAsSeries(btcCl, true);

   if(CopyClose(Sym_ETH, TF_Entry, 1, need, ethCl) < need) return 0;
   if(CopyClose(Sym_BTC, TF_Entry, 1, need, btcCl) < need) return 0;

   if(btcCl[0] <= 0 || btcCl[RatioBars] <= 0) return 0;

   // ETH/BTC ratio: ETH price as fraction of BTC price
   double ratioNow  = ethCl[0] / btcCl[0];
   double ratioThen = ethCl[RatioBars] / btcCl[RatioBars];
   double changePct = (ratioNow - ratioThen) / ratioThen * 100.0;

   if(changePct >  RatioThreshold) return  1;  // ETH leading → Risk-On → BUY bias
   if(changePct < -RatioThreshold) return -1;  // ETH lagging → Risk-Off → SELL bias
   return 0;
}

//+------------------------------------------------------------------+
//|   VOLATILITY REGIME                                              |
//|   0 = Low Vol (range)  1 = Normal  2 = High Vol  3 = Spike      |
//+------------------------------------------------------------------+
int GetVolatilityRegime() {
   int bufSize = ATR_Avg_Period + 3;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR_Entry, 0, 0, bufSize, atr) < bufSize) return 1;

   double currentATR = atr[1];
   double sum = 0;
   for(int i = 1; i <= ATR_Avg_Period; i++) sum += atr[i];
   double avgATR = sum / ATR_Avg_Period;

   if(avgATR <= 0) return 1;
   double ratio = currentATR / avgATR;

   if(ratio >= VolSpike_Ratio) return 3;  // Dangerous spike
   if(ratio >= VolHigh_Ratio)  return 2;  // High volatility
   if(ratio <= VolLow_Ratio)   return 0;  // Low volatility range
   return 1;                               // Normal
}

//+------------------------------------------------------------------+
//|   SWING HIGH / LOW DETECTION                                     |
//+------------------------------------------------------------------+
double GetSwingHigh(string symbol, ENUM_TIMEFRAMES tf, int shift) {
   double high = iHigh(symbol, tf, shift);
   for(int i = 1; i <= SwingBars; i++) {
      if(iHigh(symbol, tf, shift + i) >= high) return 0;
      if(iHigh(symbol, tf, shift - i) >= high) return 0;
   }
   return high;
}

double GetSwingLow(string symbol, ENUM_TIMEFRAMES tf, int shift) {
   double low = iLow(symbol, tf, shift);
   for(int i = 1; i <= SwingBars; i++) {
      if(iLow(symbol, tf, shift + i) <= low) return 0;
      if(iLow(symbol, tf, shift - i) <= low) return 0;
   }
   return low;
}

//+------------------------------------------------------------------+
//|   OPEN TRADE                                                     |
//+------------------------------------------------------------------+
void OpenTrade(int direction, int regime) {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR_Entry, 0, 0, 3, atr) < 3) return;
   double atrVal = atr[1];
   if(atrVal <= 0) return;

   // Widen SL slightly in high-vol conditions to avoid ATR hunting
   double slMulti = ATR_SL_Multi;
   if(regime == 2) slMulti *= 1.25;

   double ask    = SymbolInfoDouble(Sym_Trade, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(Sym_Trade, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(Sym_Trade, SYMBOL_DIGITS);

   double slDist  = atrVal * slMulti;
   double tp3Dist = slDist * TP3_R;

   double price, sl, tp;
   if(direction == 1) {         // BUY
      price = ask;
      sl    = NormalizeDouble(price - slDist, digits);
      tp    = NormalizeDouble(price + tp3Dist, digits);
   } else {                     // SELL
      price = bid;
      sl    = NormalizeDouble(price + slDist, digits);
      tp    = NormalizeDouble(price - tp3Dist, digits);
   }

   double lot = CalcLot(slDist);
   if(lot <= 0) return;

   string comment = (direction == 1) ? "CSMT_BUY" : "CSMT_SELL";
   bool ok = (direction == 1)
             ? trade.Buy( lot, Sym_Trade, price, sl, tp, comment)
             : trade.Sell(lot, Sym_Trade, price, sl, tp, comment);

   if(ok) {
      ulong newTicket = trade.ResultOrder();

      // Register trade state
      int idx = ArraySize(tradeStates);
      ArrayResize(tradeStates, idx + 1);
      tradeStates[idx].ticket     = newTicket;
      tradeStates[idx].slDistance = slDist;
      tradeStates[idx].tp1Hit     = false;
      tradeStates[idx].tp2Hit     = false;
      tradeStates[idx].tp3Hit     = false;
      tradeStates[idx].trailPhase = 0;

      string regimeTxt[] = {"LOW VOL", "NORMAL", "HIGH VOL", "SPIKE"};
      string dir         = (direction == 1) ? "BUY" : "SELL";

      Print("┌─── CRYPTO SMT PRO ─────────────────────────────────");
      Print("│ ", dir, " | ", Sym_Trade,
            " | Lot: ", DoubleToString(lot, 2),
            " | Regime: ", regimeTxt[MathMin(regime, 3)]);
      Print("│ Entry: @", DoubleToString(price, digits),
            "  SL: @", DoubleToString(sl, digits));
      Print("│ TP1(", TP1_R, "R): @",
            DoubleToString(direction == 1 ? price + slDist * TP1_R : price - slDist * TP1_R, digits),
            "  → Close ", TP1_ClosePct, "% + Breakeven");
      Print("│ TP2(", TP2_R, "R): @",
            DoubleToString(direction == 1 ? price + slDist * TP2_R : price - slDist * TP2_R, digits),
            "  → Close ", TP2_ClosePct, "% + Trail×", Trail_Phase2, " ATR");
      Print("│ TP3(", TP3_R, "R): @", DoubleToString(tp, digits),
            "  → Close ", TP3_ClosePct, "% + Runner ATR×", Trail_Runner);
      Print("│ Runner(", 100 - TP1_ClosePct - TP2_ClosePct - TP3_ClosePct, "%): Trail×",
            Trail_Runner, " until stopped");
      Print("└──────────────────────────────────────────────────────");
   } else {
      Print("TRADE FAILED [", comment, "]: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//|   CALCULATE LOT                                                  |
//+------------------------------------------------------------------+
double CalcLot(double slDist) {
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt  = equity * (RiskPercent / 100.0);
   double tickVal  = SymbolInfoDouble(Sym_Trade, SYMBOL_TRADE_TICK_VALUE);
   double tickSz   = SymbolInfoDouble(Sym_Trade, SYMBOL_TRADE_TICK_SIZE);
   double lotStep  = SymbolInfoDouble(Sym_Trade, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(Sym_Trade, SYMBOL_VOLUME_MIN);
   double maxLot   = MathMin(SymbolInfoDouble(Sym_Trade, SYMBOL_VOLUME_MAX), MaxLotSize);

   if(tickVal <= 0 || tickSz <= 0 || slDist <= 0) return minLot;

   double valPerLot = (slDist / tickSz) * tickVal;
   if(valPerLot <= 0) return minLot;

   double lot = riskAmt / valPerLot;
   lot = MathFloor(lot / lotStep) * lotStep;
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lot)), 2);
}

//+------------------------------------------------------------------+
//|   GET STATE INDEX                                                |
//+------------------------------------------------------------------+
int GetStateIdx(ulong ticket) {
   for(int i = 0; i < ArraySize(tradeStates); i++)
      if(tradeStates[i].ticket == ticket) return i;
   return -1;
}

//+------------------------------------------------------------------+
//   MANAGE OPEN TRADES
//   4-Phase Partial Close + Adaptive Trailing Stop
//
//   Phase 0 (entry to TP1): Normal SL, no trailing
//   Phase 1 (after TP1):    20% closed, SL moved to Breakeven
//   Phase 2 (after TP2):    30% closed, trail at ATR × 2.0
//   Phase 3 (after TP3):    30% closed, runner trail at ATR × 0.5
//   Runner remains until trail stop is hit (catches big moves)
//+------------------------------------------------------------------+
void ManageOpenTrades() {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR_Entry, 0, 0, 3, atr) < 3) return;
   double atrVal = atr[1];
   if(atrVal <= 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol()     != Sym_Trade)  continue;
      if((int)posInfo.Magic() != MagicNumber) continue;

      ulong  ticket  = posInfo.Ticket();
      double entry   = posInfo.PriceOpen();
      double curSL   = posInfo.StopLoss();
      double curTP   = posInfo.TakeProfit();
      double lot     = posInfo.Volume();
      int    digits  = (int)SymbolInfoInteger(Sym_Trade, SYMBOL_DIGITS);
      bool   isBuy   = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double bid     = SymbolInfoDouble(Sym_Trade, SYMBOL_BID);
      double ask     = SymbolInfoDouble(Sym_Trade, SYMBOL_ASK);
      double price   = isBuy ? bid : ask;

      // --- Restore state after EA restart ---
      int idx = GetStateIdx(ticket);
      if(idx < 0) {
         idx = ArraySize(tradeStates);
         ArrayResize(tradeStates, idx + 1);
         tradeStates[idx].ticket     = ticket;
         double calcSL = MathAbs(entry - curSL);
         tradeStates[idx].slDistance = (calcSL > 0) ? calcSL : atrVal * ATR_SL_Multi;
         // Detect if BE was already set
         bool beSet = (isBuy ? curSL >= entry - _Point : (curSL > 0 && curSL <= entry + _Point));
         tradeStates[idx].tp1Hit     = beSet;
         tradeStates[idx].tp2Hit     = false;
         tradeStates[idx].tp3Hit     = false;
         tradeStates[idx].trailPhase = beSet ? 1 : 0;
      }

      double slDist  = tradeStates[idx].slDistance;
      if(slDist <= 0) slDist = MathAbs(entry - curSL);
      if(slDist <= 0) slDist = atrVal * ATR_SL_Multi;

      double profit  = isBuy ? (price - entry) : (entry - price);
      double profitR = (slDist > 0) ? profit / slDist : 0;

      // ==========================================================
      // PHASE 1: TP1 hit → close TP1_ClosePct% + Breakeven
      // ==========================================================
      if(!tradeStates[idx].tp1Hit && profitR >= TP1_R) {
         double closeLot = GetPartialLot(lot, TP1_ClosePct);
         if(closeLot > 0 && trade.PositionClosePartial(ticket, closeLot)) {
            double beSL = NormalizeDouble(entry, digits);
            if(isBuy && beSL > curSL)
               trade.PositionModify(ticket, beSL, curTP);
            else if(!isBuy && (curSL == 0 || beSL < curSL))
               trade.PositionModify(ticket, beSL, curTP);

            tradeStates[idx].tp1Hit     = true;
            tradeStates[idx].trailPhase = 1;

            Print("TP1 HIT +", DoubleToString(profitR, 2), "R | Closed ", TP1_ClosePct,
                  "% | Breakeven set @ ", DoubleToString(entry, digits),
                  " | Ticket #", ticket);
         }
      }

      // ==========================================================
      // PHASE 2: TP2 hit → close TP2_ClosePct% + Trail ATR×2
      // ==========================================================
      if(tradeStates[idx].tp1Hit && !tradeStates[idx].tp2Hit && profitR >= TP2_R) {
         double closeLot = GetPartialLot(lot, TP2_ClosePct);
         if(closeLot > 0 && trade.PositionClosePartial(ticket, closeLot)) {
            tradeStates[idx].tp2Hit     = true;
            tradeStates[idx].trailPhase = 2;

            Print("TP2 HIT +", DoubleToString(profitR, 2), "R | Closed ", TP2_ClosePct,
                  "% | Trail ATR×", Trail_Phase2, " activated | Ticket #", ticket);
         }
      }

      // ==========================================================
      // PHASE 3: TP3 hit → close TP3_ClosePct% + Runner ATR×0.5
      // ==========================================================
      if(tradeStates[idx].tp2Hit && !tradeStates[idx].tp3Hit && profitR >= TP3_R) {
         double closeLot = GetPartialLot(lot, TP3_ClosePct);
         if(closeLot > 0 && trade.PositionClosePartial(ticket, closeLot)) {
            tradeStates[idx].tp3Hit     = true;
            tradeStates[idx].trailPhase = 3;

            // Remove fixed TP on the runner so it can run freely
            trade.PositionModify(ticket, curSL, 0);

            Print("TP3 HIT +", DoubleToString(profitR, 2), "R | Closed ", TP3_ClosePct,
                  "% | RUNNER mode ATR×", Trail_Runner, " | Ticket #", ticket);
         }
      }

      // ==========================================================
      // TRAILING STOP APPLICATION
      // ==========================================================
      double trailMulti = 0;
      if(tradeStates[idx].trailPhase == 2) trailMulti = Trail_Phase2;
      if(tradeStates[idx].trailPhase == 3) trailMulti = Trail_Runner;

      if(trailMulti > 0) {
         if(isBuy) {
            double newSL = NormalizeDouble(bid - atrVal * trailMulti, digits);
            // Only move SL up (tighten), never below entry after BE
            double floorSL = tradeStates[idx].tp1Hit ? entry : 0;
            if(newSL > curSL && newSL >= floorSL)
               trade.PositionModify(ticket, newSL, curTP);
         } else {
            double newSL = NormalizeDouble(ask + atrVal * trailMulti, digits);
            // Only move SL down (tighten), never above entry after BE
            double ceilSL = tradeStates[idx].tp1Hit ? entry : DBL_MAX;
            if((curSL == 0 || newSL < curSL) && newSL <= ceilSL)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//|   PARTIAL LOT CALCULATION                                        |
//+------------------------------------------------------------------+
double GetPartialLot(double totalLot, double pct) {
   double lotStep = SymbolInfoDouble(Sym_Trade, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(Sym_Trade, SYMBOL_VOLUME_MIN);
   double partial = MathFloor((totalLot * pct / 100.0) / lotStep) * lotStep;
   if(partial < minLot) return 0;
   // Always keep at least minLot as the runner
   return MathMin(partial, totalLot - minLot);
}

//+------------------------------------------------------------------+
//|   DRAWDOWN PROTECTION                                            |
//+------------------------------------------------------------------+
bool DrawdownCheck() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(
      IntegerToString(dt.year) + "." +
      IntegerToString(dt.mon)  + "." +
      IntegerToString(dt.day));

   if(today > lastDayReset) {
      lastDayReset  = today;
      dayStartEq    = AccountInfoDouble(ACCOUNT_EQUITY);
      protectionHit = false;
      Print("New Day | Starting Equity: $", DoubleToString(dayStartEq, 2));
   }

   if(protectionHit) return false;

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = (dayStartEq > 0) ? (equity - dayStartEq) / dayStartEq * 100.0 : 0;
   double totalDD   = (startEquity > 0) ? (equity - startEquity) / startEquity * 100.0 : 0;

   if(dailyLoss <= -MaxDailyLossPct) {
      protectionHit = true;
      CloseAll();
      Print("DAILY LOSS LIMIT HIT: ", DoubleToString(dailyLoss, 2),
            "% | Trading paused until tomorrow");
      return false;
   }
   if(totalDD <= -MaxTotalDDPct) {
      protectionHit = true;
      CloseAll();
      Print("MAX DRAWDOWN HIT: ", DoubleToString(totalDD, 2),
            "% | EA stopped - review settings");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//|   HELPERS                                                        |
//+------------------------------------------------------------------+
void CloseAll() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == Sym_Trade && (int)posInfo.Magic() == MagicNumber)
         trade.PositionClose(posInfo.Ticket());
   }
}

bool HasOpenPosition() {
   for(int i = 0; i < PositionsTotal(); i++) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == Sym_Trade && (int)posInfo.Magic() == MagicNumber)
         return true;
   }
   return false;
}

bool SpreadOK() {
   double sBTC = SymbolInfoDouble(Sym_BTC, SYMBOL_ASK) - SymbolInfoDouble(Sym_BTC, SYMBOL_BID);
   double sETH = SymbolInfoDouble(Sym_ETH, SYMBOL_ASK) - SymbolInfoDouble(Sym_ETH, SYMBOL_BID);
   if(sBTC > MaxSpreadBTC) {
      Print("BTC spread too high: $", DoubleToString(sBTC, 0));
      return false;
   }
   if(sETH > MaxSpreadETH) {
      Print("ETH spread too high: $", DoubleToString(sETH, 2));
      return false;
   }
   return true;
}

bool IsSundayOpen() {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   // Sunday 00:00–02:00 GMT: highest crypto volatility opening spike risk
   return (dt.day_of_week == 0 && dt.hour < 2);
}

//+------------------------------------------------------------------+
//|   DASHBOARD                                                      |
//+------------------------------------------------------------------+
void CreateDashboard() {
   CreateBox(PRE + "BG", 10, 30, 310, 265, C'8, 12, 22', C'0, 150, 220');

   CreateLabel(PRE + "TITLE",   "  CRYPTO SMT PRO  v1.0",   20, 40,  10, C'0, 200, 255');
   CreateLabel(PRE + "SUB",     Sym_BTC + " x " + Sym_ETH + "  |  24/7", 20, 58, 8, C'60, 110, 150');
   CreateLabel(PRE + "LINE1",   "────────────────────────────────", 20, 70, 8, C'15, 35, 55');

   CreateLabel(PRE + "L_REG",   "Vol Regime:", 20, 82,  8, C'90, 115, 145');
   CreateLabel(PRE + "V_REG",   "...",         165, 82,  8, clrGray);

   CreateLabel(PRE + "L_RATIO", "ETH/BTC Ratio:", 20, 97,  8, C'90, 115, 145');
   CreateLabel(PRE + "V_RATIO", "...",            165, 97,  8, clrGray);

   CreateLabel(PRE + "L_SMT",   "SMT Signal:", 20, 112, 8, C'90, 115, 145');
   CreateLabel(PRE + "V_SMT",   "Scanning...",  165, 112, 8, clrGray);

   CreateLabel(PRE + "LINE2",   "────────────────────────────────", 20, 124, 8, C'15, 35, 55');

   CreateLabel(PRE + "L_BTCP",  "BTC:",   20,  136, 8, C'90, 115, 145');
   CreateLabel(PRE + "V_BTCP",  "...",    80,  136, 9, C'255, 200, 50');
   CreateLabel(PRE + "L_ETHP",  "ETH:",   175, 136, 8, C'90, 115, 145');
   CreateLabel(PRE + "V_ETHP",  "...",    230, 136, 9, C'180, 100, 255');

   CreateLabel(PRE + "LINE3",   "────────────────────────────────", 20, 148, 8, C'15, 35, 55');

   CreateLabel(PRE + "L_TRADE", "Position:", 20,  160, 8, C'90, 115, 145');
   CreateLabel(PRE + "V_TRADE", "No trade",  165, 160, 8, clrGray);

   CreateLabel(PRE + "L_PHASE", "Phase:",    20,  175, 8, C'90, 115, 145');
   CreateLabel(PRE + "V_PHASE", "—",         165, 175, 8, clrGray);

   CreateLabel(PRE + "LINE4",   "────────────────────────────────", 20, 187, 8, C'15, 35, 55');

   CreateLabel(PRE + "L_EQ",    "Equity:",   20,  199, 8, C'90, 115, 145');
   CreateLabel(PRE + "V_EQ",    "$...",      165, 199, 8, clrWhite);

   CreateLabel(PRE + "L_DAY",   "Daily P&L:", 20, 214, 8, C'90, 115, 145');
   CreateLabel(PRE + "V_DAY",   "0.00%",      165, 214, 8, clrGray);

   CreateLabel(PRE + "L_STAT",  "Status:",   20,  229, 8, C'90, 115, 145');
   CreateLabel(PRE + "V_STAT",  "Active",    165, 229, 8, C'0, 200, 100');

   CreateLabel(PRE + "FOOT",    "[ S ] Status | 24/7 No Session Filter", 20, 248, 7, C'40, 70, 100');

   ChartRedraw(0);
}

void UpdateDashboard() {
   static datetime lastUpd = 0;
   if(TimeCurrent() - lastUpd < 3) return;
   lastUpd = TimeCurrent();

   // Regime
   int    regime      = GetVolatilityRegime();
   string regText[]   = {"LOW VOL", "NORMAL", "HIGH VOL", "VOL SPIKE!"};
   color  regColor[]  = {C'220,190,0', C'0,200,100', C'255,140,0', C'255,50,50'};
   SetLbl(PRE + "V_REG", regText[MathMin(regime,3)], regColor[MathMin(regime,3)]);

   // ETH/BTC Ratio
   int    ratio       = UseRatioFilter ? GetETHBTCRatioSignal() : 0;
   string ratText     = (ratio ==  1) ? "Risk-On  (BUY bias)"  :
                        (ratio == -1) ? "Risk-Off (SELL bias)" : "Neutral";
   color  ratColor    = (ratio ==  1) ? C'0,200,100' :
                        (ratio == -1) ? C'255,80,80'  : clrGray;
   SetLbl(PRE + "V_RATIO", ratText, ratColor);

   // Prices
   double btcBid = SymbolInfoDouble(Sym_BTC, SYMBOL_BID);
   double ethBid = SymbolInfoDouble(Sym_ETH, SYMBOL_BID);
   SetLbl(PRE + "V_BTCP", DoubleToString(btcBid, 0), C'255,200,50');
   SetLbl(PRE + "V_ETHP", DoubleToString(ethBid, 2),  C'180,100,255');

   // Open trade info
   if(HasOpenPosition()) {
      for(int i = 0; i < PositionsTotal(); i++) {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Symbol() != Sym_Trade || (int)posInfo.Magic() != MagicNumber) continue;

         bool   isBuy  = (posInfo.PositionType() == POSITION_TYPE_BUY);
         double pnl    = posInfo.Profit();
         color  pClr   = (pnl >= 0) ? C'0,200,100' : C'255,80,80';
         SetLbl(PRE + "V_TRADE",
                (isBuy ? "BUY " : "SELL ") + "$" + DoubleToString(pnl, 0), pClr);

         int idx = GetStateIdx(posInfo.Ticket());
         if(idx >= 0) {
            string ph = "Targeting TP1";
            if(tradeStates[idx].tp3Hit)       ph = "RUNNER  Trail×" + DoubleToString(Trail_Runner, 1) + " ATR";
            else if(tradeStates[idx].tp2Hit)  ph = "TP2 done  Trail×" + DoubleToString(Trail_Phase2, 1) + " ATR";
            else if(tradeStates[idx].tp1Hit)  ph = "TP1 done  Breakeven set";
            SetLbl(PRE + "V_PHASE", ph, C'0,180,255');
         }
         break;
      }
   } else {
      SetLbl(PRE + "V_TRADE", "No position", clrGray);
      SetLbl(PRE + "V_PHASE", "—",           clrGray);
      SetLbl(PRE + "V_SMT",   "Scanning...", clrGray);
   }

   // Equity & daily P&L
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPct   = (dayStartEq > 0) ? (equity - dayStartEq) / dayStartEq * 100.0 : 0;
   SetLbl(PRE + "V_EQ", "$" + DoubleToString(equity, 0), clrWhite);
   color dayClr = (dayPct >= 0) ? C'0,200,100' : C'255,80,80';
   SetLbl(PRE + "V_DAY",
          (dayPct >= 0 ? "+" : "") + DoubleToString(dayPct, 2) + "%", dayClr);

   // Status
   string status;
   color  statClr;
   if(protectionHit)
      { status = "PROTECTION - Paused"; statClr = C'255,50,50'; }
   else if(AvoidSundayOpen && IsSundayOpen())
      { status = "Sunday Open - Waiting"; statClr = C'255,180,0'; }
   else
      { status = "Active - Scanning H1"; statClr = C'0,200,100'; }
   SetLbl(PRE + "V_STAT", status, statClr);

   ChartRedraw(0);
}

void CreateBox(string name, int x, int y, int w, int h, color bg, color border) {
   if(ObjectFind(0, name) >= 0) return;
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       border);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       2);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
}

void CreateLabel(string name, string text, int x, int y, int sz, color clr) {
   if(ObjectFind(0, name) >= 0) return;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   sz);
   ObjectSetString(0,  name, OBJPROP_FONT,       "Segoe UI");
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void SetLbl(string name, string text, color clr) {
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//|   OnTrade - Deal Logging                                         |
//+------------------------------------------------------------------+
void OnTrade() {
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
   double profit    = HistoryDealGetDouble(ticket, DEAL_PROFIT);
   double swap      = HistoryDealGetDouble(ticket, DEAL_SWAP);
   double comm      = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   double net       = profit + swap + comm;
   double price     = HistoryDealGetDouble(ticket, DEAL_PRICE);
   double lot       = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   string dir       = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
   int    digits    = (int)SymbolInfoInteger(Sym_Trade, SYMBOL_DIGITS);

   if(dealEntry == DEAL_ENTRY_IN) {
      Print("┌─────────────────────────────────────────────");
      Print("│ OPENED | ", dir, " | ", Sym_Trade,
            " | Lot: ", DoubleToString(lot, 2),
            " | @", DoubleToString(price, digits));
      Print("│ Balance: $", DoubleToString(balance, 2));
      Print("└─────────────────────────────────────────────");
   }

   if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT) {
      string result = (net > 0) ? "WIN  +" : (net < 0) ? "LOSS " : "BE   ";
      Print("┌─────────────────────────────────────────────");
      Print("│ CLOSED | ", result, DoubleToString(net, 2),
            "$ | Lot: ", DoubleToString(lot, 2));
      Print("│ Balance: $", DoubleToString(balance, 2),
            "  |  Equity: $", DoubleToString(equity, 2));
      Print("└─────────────────────────────────────────────");
   }
}

//+------------------------------------------------------------------+
//|   OnChartEvent – Press S for full status                         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam,
                  const double& dparam, const string& sparam) {
   if(id != CHARTEVENT_KEYDOWN || lparam != 83) return;  // S key

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double dayPct   = (dayStartEq  > 0) ? (equity - dayStartEq)  / dayStartEq  * 100.0 : 0;
   double totalPct = (startEquity > 0) ? (equity - startEquity) / startEquity * 100.0 : 0;

   int    regime   = GetVolatilityRegime();
   int    ratio    = GetETHBTCRatioSignal();
   string regTxt[] = {"LOW VOL", "NORMAL", "HIGH VOL", "VOL SPIKE"};
   string ratTxt   = (ratio ==  1) ? "Risk-On (BUY bias)"   :
                     (ratio == -1) ? "Risk-Off (SELL bias)"  : "Neutral";

   Print("╔══════════════════════════════════════════════╗");
   Print("║       CRYPTO SMT PRO v1.0  -  STATUS         ║");
   Print("╠══════════════════════════════════════════════╣");
   Print("║ Traded    : ", Sym_Trade, "  (BTC+ETH analysis)");
   Print("║ Balance   : $", DoubleToString(balance,  2));
   Print("║ Equity    : $", DoubleToString(equity,   2));
   Print("║ Daily P&L : ", (dayPct   >= 0 ? "+" : ""), DoubleToString(dayPct,   2), "%");
   Print("║ Total DD  : ", (totalPct >= 0 ? "+" : ""), DoubleToString(totalPct, 2), "%");
   Print("╠══════════════════════════════════════════════╣");
   Print("║ Vol Regime: ", regTxt[MathMin(regime, 3)]);
   Print("║ ETH/BTC   : ", ratTxt);
   Print("║ BTC Price : $", DoubleToString(SymbolInfoDouble(Sym_BTC, SYMBOL_BID), 0));
   Print("║ ETH Price : $", DoubleToString(SymbolInfoDouble(Sym_ETH, SYMBOL_BID), 2));
   Print("║ Position  : ", HasOpenPosition() ? "ACTIVE" : "None");
   Print("║ Protection: ", protectionHit ? "ACTIVE - Trading Paused" : "OK");
   Print("╚══════════════════════════════════════════════╝");
}
//+------------------------------------------------------------------+
