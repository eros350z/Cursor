//+------------------------------------------------------------------+
//|                                     BTC_SuperGrid.mq5            |
//|                    BTCUSD - Supertrend + Directional Grid        |
//|              24/7 | يفتح Grid في اتجاه الترند بس               |
//+------------------------------------------------------------------+
#property copyright "BTC SuperGrid EA v1"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//=== الزوج ===
input string   Symbol_BTC    = "BTCUSD";

//=== Supertrend ===
input int      ST_Period     = 10;      // فترة Supertrend
input double   ST_Multiplier = 3.0;    // مضاعف ATR للـ Supertrend
input ENUM_TIMEFRAMES TF     = PERIOD_H4;

//=== إعدادات الشبكة ===
input double   GridSize      = 500.0;  // المسافة بين كل مستوى
input int      GridLevels    = 3;      // عدد المستويات
input double   LotSize       = 0.01;   // حجم اللوت لكل صفقة

//=== إدارة المخاطر ===
input double   MaxDrawdown   = 300.0;  // أقصى خسارة بالدولار
input bool     UseMaxDD      = true;

//=== عام ===
input long     MagicNumber   = 20250418;

string PRE = "BSTG_";

// Supertrend
int    hATR_ST;
double stValue  = 0;
bool   stBullish = true;   // true = صاعد، false = نازل
bool   lastBullish = true;

bool   gridBuilt = false;
double gridBase  = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(100);

    SymbolSelect(Symbol_BTC, true);
    Sleep(300);

    if(SymbolInfoDouble(Symbol_BTC, SYMBOL_POINT) == 0.0)
    {
        Print("❌ الزوج غير موجود: ", Symbol_BTC);
        return INIT_FAILED;
    }

    hATR_ST = iATR(Symbol_BTC, TF, ST_Period);
    if(hATR_ST == INVALID_HANDLE)
    {
        Print("❌ فشل تحميل ATR");
        return INIT_FAILED;
    }

    CreateDashboard();
    Print("✅ BTC SuperGrid شغّال | ", Symbol_BTC);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(hATR_ST);
    ObjectsDeleteAll(0, PRE);
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTick()
{
    // تحقق من حد الخسارة
    if(UseMaxDD && GetTotalProfit() < -MaxDrawdown)
    {
        CloseAllGrid();
        gridBuilt = false;
        Print("🛑 حد الخسارة — الشبكة أُغلقت");
        UpdateDashboard();
        return;
    }

    // احسب Supertrend على بار جديد بس
    static datetime lastBar = 0;
    datetime curBar = iTime(Symbol_BTC, TF, 0);
    if(curBar != lastBar)
    {
        lastBar     = curBar;
        lastBullish = stBullish;
        CalcSupertrend();

        // لو الاتجاه تغير — أغلق الشبكة القديمة وابنِ جديدة
        if(stBullish != lastBullish)
        {
            Print("🔄 الترند تغير — إعادة بناء الشبكة");
            CloseAllGrid();
            gridBuilt = false;
        }
    }

    // ابنِ الشبكة لو مو موجودة
    if(!gridBuilt)
    {
        double ask = SymbolInfoDouble(Symbol_BTC, SYMBOL_ASK);
        if(ask <= 0) return;
        gridBase  = MathRound(ask / GridSize) * GridSize;
        BuildGrid();
        gridBuilt = true;
    }

    // أعد فتح الصفقات اللي وصلت TP
    ManageGrid();
    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| حساب Supertrend يدوياً                                          |
//+------------------------------------------------------------------+
void CalcSupertrend()
{
    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if(CopyBuffer(hATR_ST, 0, 1, 3, atrBuf) < 3) return;

    double high1 = iHigh(Symbol_BTC, TF, 1);
    double low1  = iLow(Symbol_BTC,  TF, 1);
    double close1= iClose(Symbol_BTC, TF, 1);
    double close2= iClose(Symbol_BTC, TF, 2);
    double atr1  = atrBuf[0];

    double hl2       = (high1 + low1) / 2.0;
    double upperBand = hl2 + ST_Multiplier * atr1;
    double lowerBand = hl2 - ST_Multiplier * atr1;

    // تحديد الاتجاه
    if(close1 > upperBand)
        stBullish = true;
    else if(close1 < lowerBand)
        stBullish = false;
    // لو بين البandين — خله زي ما هو

    stValue = stBullish ? lowerBand : upperBand;

    Print("📊 Supertrend | ",
          stBullish ? "🟢 صاعد" : "🔴 نازل",
          " | قيمة: ", DoubleToString(stValue, 0),
          " | BTC: ", DoubleToString(close1, 0));
}

//+------------------------------------------------------------------+
//| بناء الشبكة في اتجاه الترند بس                                 |
//+------------------------------------------------------------------+
void BuildGrid()
{
    Print("🔨 بناء شبكة ", stBullish ? "شراء" : "بيع",
          " حول: ", DoubleToString(gridBase, 0));

    for(int i = 1; i <= GridLevels; i++)
    {
        if(stBullish)
        {
            // شراء تحت السعر الحالي بس
            double buyPrice = NormalizeDouble(gridBase - i * GridSize, 0);
            double buyTP    = NormalizeDouble(buyPrice + GridSize, 0);
            double buySL    = NormalizeDouble(buyPrice - GridSize * 2, 0);

            trade.BuyLimit(LotSize, buyPrice, Symbol_BTC,
                          buySL, buyTP,
                          ORDER_TIME_GTC, 0,
                          "SG_Buy_" + IntegerToString(i));
        }
        else
        {
            // بيع فوق السعر الحالي بس
            double sellPrice = NormalizeDouble(gridBase + i * GridSize, 0);
            double sellTP    = NormalizeDouble(sellPrice - GridSize, 0);
            double sellSL    = NormalizeDouble(sellPrice + GridSize * 2, 0);

            trade.SellLimit(LotSize, sellPrice, Symbol_BTC,
                           sellSL, sellTP,
                           ORDER_TIME_GTC, 0,
                           "SG_Sell_" + IntegerToString(i));
        }
    }

    Print("✅ تم بناء ", GridLevels, " أوردر اتجاه: ",
          stBullish ? "🟢 شراء" : "🔴 بيع");
}

//+------------------------------------------------------------------+
//| إعادة فتح الصفقات المغلقة                                       |
//+------------------------------------------------------------------+
void ManageGrid()
{
    for(int i = 1; i <= GridLevels; i++)
    {
        if(stBullish)
        {
            double buyPrice = NormalizeDouble(gridBase - i * GridSize, 0);
            double buyTP    = NormalizeDouble(buyPrice + GridSize, 0);
            double buySL    = NormalizeDouble(buyPrice - GridSize * 2, 0);

            if(!HasOrderAtLevel(buyPrice, ORDER_TYPE_BUY_LIMIT) &&
               !HasPositionAtLevel(buyPrice, POSITION_TYPE_BUY))
            {
                trade.BuyLimit(LotSize, buyPrice, Symbol_BTC,
                              buySL, buyTP,
                              ORDER_TIME_GTC, 0,
                              "SG_Buy_" + IntegerToString(i));
            }
        }
        else
        {
            double sellPrice = NormalizeDouble(gridBase + i * GridSize, 0);
            double sellTP    = NormalizeDouble(sellPrice - GridSize, 0);
            double sellSL    = NormalizeDouble(sellPrice + GridSize * 2, 0);

            if(!HasOrderAtLevel(sellPrice, ORDER_TYPE_SELL_LIMIT) &&
               !HasPositionAtLevel(sellPrice, POSITION_TYPE_SELL))
            {
                trade.SellLimit(LotSize, sellPrice, Symbol_BTC,
                               sellSL, sellTP,
                               ORDER_TIME_GTC, 0,
                               "SG_Sell_" + IntegerToString(i));
            }
        }
    }
}

//+------------------------------------------------------------------+
bool HasOrderAtLevel(double price, ENUM_ORDER_TYPE type)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL)  != Symbol_BTC)  continue;
        if(OrderGetInteger(ORDER_MAGIC)  != MagicNumber)  continue;
        if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type) continue;
        if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - price) < GridSize * 0.1)
            return true;
    }
    return false;
}

bool HasPositionAtLevel(double price, ENUM_POSITION_TYPE type)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol_BTC)  continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)  continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;
        if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - price) < GridSize * 0.1)
            return true;
    }
    return false;
}

double GetTotalProfit()
{
    double total = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol_BTC)  continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)  continue;
        total += PositionGetDouble(POSITION_PROFIT);
    }
    return total;
}

int CountOrders()
{
    int c = 0;
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(!OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL) == Symbol_BTC &&
           OrderGetInteger(ORDER_MAGIC) == MagicNumber) c++;
    }
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL) == Symbol_BTC &&
           PositionGetInteger(POSITION_MAGIC) == MagicNumber) c++;
    }
    return c;
}

void CloseAllGrid()
{
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol_BTC)  continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)  continue;
        trade.PositionClose(t);
    }
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(!OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL)  != Symbol_BTC)  continue;
        if(OrderGetInteger(ORDER_MAGIC)  != MagicNumber)  continue;
        trade.OrderDelete(t);
    }
}

//+------------------------------------------------------------------+
//|                     D A S H B O A R D                           |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    CreateBox(PRE+"BG", 10, 30, 295, 235, C'15,20,30', C'255,160,0');
    CreateLabel(PRE+"TITLE", "₿  BTC SuperGrid  v1  |  H4",  18, 40, 10, C'255,180,0');
    CreateLabel(PRE+"LINE0", "━━━━━━━━━━━━━━━━━━━━━━━━━━━",  18, 57,  8, C'80,60,0');

    CreateLabel(PRE+"L_TREND","الاتجاه:",     18,  69, 8, C'150,160,180');
    CreateLabel(PRE+"V_TREND","⏳ جاري...",  150,  69, 9, clrGray);

    CreateLabel(PRE+"L_BASE", "مركز الشبكة:", 18, 85, 8, C'150,160,180');
    CreateLabel(PRE+"V_BASE", "—",           150, 85, 8, C'255,200,50');

    CreateLabel(PRE+"L_SIZE", "حجم الشبكة:", 18, 100, 8, C'150,160,180');
    CreateLabel(PRE+"V_SIZE", DoubleToString(GridSize,0)+"$  x"+IntegerToString(GridLevels)+" مستويات",
                150, 100, 8, C'255,200,50');

    CreateLabel(PRE+"LINE1", "━━━━━━━━━━━━━━━━━━━━━━━━━━━", 18, 113, 8, C'80,60,0');

    CreateLabel(PRE+"L_ORD", "الأوردرات:",   18, 125, 8, C'150,160,180');
    CreateLabel(PRE+"V_ORD", "—",           150, 125, 8, clrWhite);

    CreateLabel(PRE+"L_PNL", "P/L:",         18, 140, 8, C'150,160,180');
    CreateLabel(PRE+"V_PNL", "—",           150, 140, 8, clrGray);

    CreateLabel(PRE+"L_DD",  "حد الخسارة:", 18, 155, 8, C'150,160,180');
    CreateLabel(PRE+"V_DD",  "-"+DoubleToString(MaxDrawdown,0)+"$",
                150, 155, 8, C'220,80,80');

    CreateLabel(PRE+"LINE2", "━━━━━━━━━━━━━━━━━━━━━━━━━━━", 18, 168, 8, C'80,60,0');

    CreateLabel(PRE+"L_BAL", "الرصيد:",      18, 180, 8, C'150,160,180');
    CreateLabel(PRE+"V_BAL", "—",           150, 180, 8, clrWhite);

    CreateLabel(PRE+"SES",   "⏳ تهيئة...",  18, 197, 8, C'150,160,180');
    CreateLabel(PRE+"PRICE", "₿ BTC: —",    18, 212, 9, C'255,200,50');

    ChartRedraw(0);
}

void UpdateDashboard()
{
    double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
    double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
    double pnl   = GetTotalProfit();
    double price = SymbolInfoDouble(Symbol_BTC, SYMBOL_BID);
    color  pnlC  = pnl >= 0 ? C'60,200,100' : C'220,70,70';

    string trendTxt = stBullish ? "🟢 صاعد — شراء فقط" : "🔴 نازل — بيع فقط";
    color  trendCol = stBullish ? C'60,200,100' : C'220,70,70';
    ObjectSetString(0,  PRE+"V_TREND", OBJPROP_TEXT,  trendTxt);
    ObjectSetInteger(0, PRE+"V_TREND", OBJPROP_COLOR, trendCol);

    ObjectSetString(0, PRE+"V_BASE", OBJPROP_TEXT,
        gridBuilt ? DoubleToString(gridBase,0)+"$" : "جاري البناء...");

    ObjectSetString(0, PRE+"V_ORD", OBJPROP_TEXT,
        IntegerToString(CountOrders()) + " أوردر");

    ObjectSetString(0,  PRE+"V_PNL", OBJPROP_TEXT,
        (pnl>=0?"+":"") + DoubleToString(pnl,2) + "$");
    ObjectSetInteger(0, PRE+"V_PNL", OBJPROP_COLOR, pnlC);

    ObjectSetString(0, PRE+"V_BAL", OBJPROP_TEXT,
        DoubleToString(bal,2)+"$  Eq:"+DoubleToString(eq,2)+"$");

    string status = gridBuilt ? "🟢 الشبكة نشطة (24/7)" : "⏳ جاري البناء...";
    if(UseMaxDD && pnl < -MaxDrawdown) status = "🛑 موقوف — حد الخسارة";
    ObjectSetString(0, PRE+"SES", OBJPROP_TEXT, status);

    ObjectSetString(0, PRE+"PRICE", OBJPROP_TEXT,
        "₿ BTC: " + DoubleToString(price, 0) + "$");

    ChartRedraw(0);
}

void CreateBox(string name,int x,int y,int w,int h,color bg,color border)
{
    ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
    ObjectSetInteger(0,name,OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0,name,OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0,name,OBJPROP_XSIZE,      w);
    ObjectSetInteger(0,name,OBJPROP_YSIZE,      h);
    ObjectSetInteger(0,name,OBJPROP_BGCOLOR,    bg);
    ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
    ObjectSetInteger(0,name,OBJPROP_COLOR,      border);
    ObjectSetInteger(0,name,OBJPROP_WIDTH,      2);
    ObjectSetInteger(0,name,OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0,name,OBJPROP_BACK,       false);
    ObjectSetInteger(0,name,OBJPROP_SELECTABLE, false);
}

void CreateLabel(string name,string text,int x,int y,int size,color clr)
{
    ObjectCreate(0,name,OBJ_LABEL,0,0,0);
    ObjectSetInteger(0,name,OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0,name,OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
    ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
    ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  size);
    ObjectSetString(0, name,OBJPROP_FONT,      "Segoe UI");
    ObjectSetString(0, name,OBJPROP_TEXT,      text);
    ObjectSetInteger(0,name,OBJPROP_BACK,      false);
    ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
//+------------------------------------------------------------------+
