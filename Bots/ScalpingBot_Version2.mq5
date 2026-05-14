//+------------------------------------------------------------------+
//|                       Scalping Bot MT5                           |
//|                    Gold & Bitcoin Scalper                        |
//|                      by Trading System                           |
//+------------------------------------------------------------------+
#property copyright "Trading System"
#property link      "https://github.com"
#property version   "1.04"
#property strict

// ============ الإعدادات الأساسية ============
input double RiskPercentage = 1.0;           // نسبة المخاطرة من رأس المال (%)
input int RSIPeriod = 14;                    // فترة مؤشر RSI
input int FastMA = 9;                        // المتوسط المتحرك السريع
input int SlowMA = 21;                       // المتوسط المتحرك البطيء
input int RSIOverbought = 70;                // مستوى Overbought للـ RSI
input int RSIOversold = 30;                  // مستوى Oversold للـ RSI
input int ScalpPips = 10;                    // أقل ربح بـ pips
input int MaxOpenPositions = 5;              // أقصى عدد صفقات مفتوحة
input double DailyLossLimit = 5.0;           // حد الخسارة اليومي (%)

// ============ متغيرات عامة ============
double DailyLossAmount = 0;
datetime LastResetTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("✅ بوت Scalping بدأ التشغيل");
    Print("رأس المال: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    Print("نسبة المخاطرة: " + DoubleToString(RiskPercentage, 1) + "%");
    Print("الرمز المتداول: " + _Symbol);
    Print("الفريم: M5");
    
    LastResetTime = TimeCurrent();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("❌ البوت توقف");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // إعادة تعيين الخسائر اليومية (كل 24 ساعة)
    if (TimeCurrent() - LastResetTime > 86400)
    {
        DailyLossAmount = 0;
        LastResetTime = TimeCurrent();
        Print("📅 تم إعادة تعيين الخسائر اليومية");
    }
    
    // التحقق من حد الخسارة اليومي
    double dailyLimitAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (DailyLossLimit / 100);
    if (DailyLossAmount >= dailyLimitAmount)
    {
        Print("⛔ تم الوصول لحد الخسارة اليومي!");
        return;
    }
    
    // معالجة الرمز الحالي
    ProcessScalp(_Symbol);
}

//+------------------------------------------------------------------+
//| دالة معالجة Scalping                                            |
//+------------------------------------------------------------------+
void ProcessScalp(string symbol)
{
    // التحقق من عدد الصفقات المفتوحة
    if (CountOpenPositions(symbol) >= MaxOpenPositions)
    {
        return;
    }
    
    // حساب مؤشرات التداول
    double rsiValues[1];
    double fastMAValues[1];
    double slowMAValues[1];
    
    // الحصول على مؤشر RSI
    int rsiHandle = iRSI(symbol, PERIOD_M5, RSIPeriod, PRICE_CLOSE);
    if (rsiHandle == INVALID_HANDLE)
    {
        return;
    }
    
    // الحصول على المتوسط المتحرك السريع
    int fastMAHandle = iMA(symbol, PERIOD_M5, FastMA, 0, MODE_SMA, PRICE_CLOSE);
    if (fastMAHandle == INVALID_HANDLE)
    {
        ReleasedHandle(rsiHandle);
        return;
    }
    
    // الحصول على المتوسط المتحرك البطيء
    int slowMAHandle = iMA(symbol, PERIOD_M5, SlowMA, 0, MODE_SMA, PRICE_CLOSE);
    if (slowMAHandle == INVALID_HANDLE)
    {
        ReleasedHandle(rsiHandle);
        ReleasedHandle(fastMAHandle);
        return;
    }
    
    // نسخ البيانات من المؤشرات
    if (CopyBuffer(rsiHandle, 0, 0, 1, rsiValues) <= 0)
    {
        ReleasedHandle(rsiHandle);
        ReleasedHandle(fastMAHandle);
        ReleasedHandle(slowMAHandle);
        return;
    }
    
    if (CopyBuffer(fastMAHandle, 0, 0, 1, fastMAValues) <= 0)
    {
        ReleasedHandle(rsiHandle);
        ReleasedHandle(fastMAHandle);
        ReleasedHandle(slowMAHandle);
        return;
    }
    
    if (CopyBuffer(slowMAHandle, 0, 0, 1, slowMAValues) <= 0)
    {
        ReleasedHandle(rsiHandle);
        ReleasedHandle(fastMAHandle);
        ReleasedHandle(slowMAHandle);
        return;
    }
    
    double rsi = rsiValues[0];
    double fastMA = fastMAValues[0];
    double slowMA = slowMAValues[0];
    
    // تحرير المؤشرات
    ReleasedHandle(rsiHandle);
    ReleasedHandle(fastMAHandle);
    ReleasedHandle(slowMAHandle);
    
    // ============ إشارات البيع (SELL) ============
    if (rsi > RSIOverbought && fastMA < slowMA)
    {
        OpenPosition(symbol, ORDER_TYPE_SELL);
    }
    
    // ============ إشارات الشراء (BUY) ============
    if (rsi < RSIOversold && fastMA > slowMA)
    {
        OpenPosition(symbol, ORDER_TYPE_BUY);
    }
    
    // إغلاق الصفقات الرابحة
    CloseWinningPositions(symbol);
}

//+------------------------------------------------------------------+
//| فتح صفقة جديدة                                                  |
//+------------------------------------------------------------------+
void OpenPosition(string symbol, ENUM_ORDER_TYPE orderType)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPercentage / 100);
    
    // حساب اللوت بناءً على رأس المال
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double stopLossDistance = ScalpPips * point * 10;
    double lotSize = CalculateLotSize(symbol, riskAmount, stopLossDistance);
    
    double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    if (lotSize < minVolume)
    {
        lotSize = minVolume;
    }
    
    if (lotSize > maxVolume)
    {
        lotSize = maxVolume;
    }
    
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = lotSize;
    request.price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    request.type = orderType;
    request.deviation = 10;
    request.magic = 123456;
    request.comment = "Scalp " + symbol;
    
    // حساب Stop Loss و Take Profit
    if (orderType == ORDER_TYPE_BUY)
    {
        request.sl = bid - (ScalpPips * point * 10);
        request.tp = ask + (ScalpPips * 2 * point * 10);
    }
    else
    {
        request.sl = ask + (ScalpPips * point * 10);
        request.tp = bid - (ScalpPips * 2 * point * 10);
    }
    
    if (!OrderSend(request, result))
    {
        Print("❌ خطأ في فتح الصفقة على " + symbol + ": " + IntegerToString(result.retcode));
    }
    else
    {
        Print("✅ صفقة جديدة على " + symbol + " | اللوت: " + DoubleToString(lotSize, 2) + 
              " | نوع: " + (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"));
    }
}

//+------------------------------------------------------------------+
//| حساب حجم اللوت الآمن                                            |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double riskAmount, double stopDistance)
{
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if (stopDistance <= 0 || tickValue == 0)
        return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    
    double lotSize = (riskAmount * tickSize) / (stopDistance * tickValue);
    
    return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| إغلاق الصفقات الرابحة                                           |
//+------------------------------------------------------------------+
void CloseWinningPositions(string symbol)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        
        if (ticket == 0)
            continue;
        
        if (!PositionSelectByTicket(ticket))
            continue;
        
        if (PositionGetString(POSITION_SYMBOL) != symbol)
            continue;
        
        double profit = PositionGetDouble(POSITION_PROFIT);
        double volume = PositionGetDouble(POSITION_VOLUME);
        
        // إغلاق إذا وصل الربح للـ Target
        if (profit > 0)
        {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = symbol;
            request.volume = volume;
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                          ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (request.type == ORDER_TYPE_BUY) ? 
                           SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                           SymbolInfoDouble(symbol, SYMBOL_BID);
            request.position = ticket;
            request.magic = 123456;
            request.comment = "Close Win " + symbol;
            
            if (OrderSend(request, result))
            {
                Print("💰 إغلاق صفقة رابحة على " + symbol + ": " + DoubleToString(profit, 2) + " $");
                DailyLossAmount -= profit;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| عد الصفقات المفتوحة للرمز                                       |
//+------------------------------------------------------------------+
int CountOpenPositions(string symbol)
{
    int count = 0;
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        
        if (ticket == 0)
            continue;
        
        if (!PositionSelectByTicket(ticket))
            continue;
        
        if (PositionGetString(POSITION_SYMBOL) == symbol)
            count++;
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| تحرير المؤشرات                                                  |
//+------------------------------------------------------------------+
void ReleasedHandle(int handle)
{
    if (handle != INVALID_HANDLE)
    {
        IndicatorRelease(handle);
    }
}

//+------------------------------------------------------------------+