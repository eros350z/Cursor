//+------------------------------------------------------------------+
//|                                      SMC_Fibonacci_EA.mq5      |
//|              SMC + Fibonacci Expert Advisor                     |
//|         Order Block + BOS + Fib 61.8% = Perfect Entry Signal   |
//+------------------------------------------------------------------+
#property copyright   "SMC_Fibonacci_EA"
#property version     "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== SMC Settings ==="
input int    SwingLookback  = 50;
input int    OB_Lookback    = 8;
input int    BOS_Lookback   = 15;

input group "=== Fibonacci Settings ==="
input int    FibLookback    = 100;
input double FibEntryMin    = 0.50;
input double FibEntryMax    = 0.786;

input group "=== Notifications ==="
input bool   SendTelegram   = true;
input bool   SendPush       = false;
input int    Cooldown_H     = 4;
input string BotToken       = "8764834987:AAHZ_dC1TmEfTO-Pbmd1AyZQcuHsNFQZy64";
input string ChatID         = "6652508619";

input group "=== Display Settings ==="
input bool   ShowPanel      = true;
input int    PanelX         = 20;
input int    PanelY         = 30;

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string   pfx       = "SMCFEA_";
datetime lastAlert = 0;
datetime lastBarTime = 0;

double swingHigh = 0, swingLow = 0;
int    highBar = 0, lowBar = 0;
bool   isUptrend = true;

double fib0, fib382, fib50, fib618, fib786, fib100, fib1272, fib1618;

string   lastType  = "";
double   lastEntry = 0, lastSL = 0;
double   lastTP1   = 0, lastTP2 = 0, lastTP3 = 0;
datetime lastTime  = 0;

//+------------------------------------------------------------------+
//| TELEGRAM                                                          |
//+------------------------------------------------------------------+
bool SendToTelegram(string msg)
  {
   if(!SendTelegram) return false;

   // Encode message
   string encoded = msg;
   StringReplace(encoded, "\n", "%0A");
   StringReplace(encoded, "\n", "%0A");
   string url  = "https://api.telegram.org/bot"+BotToken+"/sendMessage";
   string hdrs = "Content-Type: application/x-www-form-urlencoded\r\n";
   string body = "chat_id="+ChatID+"&text="+encoded;
   char req[], res[]; string resH;
   StringToCharArray(body, req, 0, StringLen(body));
   int r = WebRequest("POST", url, hdrs, 5000, req, res, resH);
   if(r==200){ Print("✅ Telegram: Sent OK"); return true; }
   string resStr = CharArrayToString(res);
   Print("❌ Telegram Error: ", r, " | ", resStr);
   return false;
  }

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("✅ SMC_Fibonacci EA Ready | ", _Symbol);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, pfx);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| MAIN TICK                                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Run on All bar new only
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBar == lastBarTime) 
     {
      if(ShowPanel) DrawPanel(SymbolInfoDouble(_Symbol, SYMBOL_BID), false, false);
      return;
     }
   lastBarTime = curBar;

   // Get Data
   int total = FibLookback + 20;
   double high[], low[], close[], open[];
   datetime time[];
   ArraySetAsSeries(high,true); ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true); ArraySetAsSeries(open,true);
   ArraySetAsSeries(time,true);

   if(CopyHigh(_Symbol,PERIOD_CURRENT,0,total,high)<total) return;
   if(CopyLow(_Symbol,PERIOD_CURRENT,0,total,low)<total)   return;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,total,close)<total) return;
   if(CopyOpen(_Symbol,PERIOD_CURRENT,0,total,open)<total)  return;
   if(CopyTime(_Symbol,PERIOD_CURRENT,0,total,time)<total)  return;

   // 1. Find Swing
   FindSwings(high, low);

   //
   CalcFib();

   // 3. Find Order Block
   double obH=0, obL=0;
   int obIdx = FindOB(open, close, high, low, obH, obL);

   // 4. BOS
   bool bos = CheckBOS(close, high, low);

   //
   bool inZone = IsInFibZone(close[1]);
   bool nearOB = IsNearOB(close[1], obH, obL);
   bool trendOK= IsTrendOK(close[1]);

   // 6. Signal
   if(inZone && nearOB && trendOK)
     {
      bool canAlert = (TimeCurrent()-lastAlert) >= (Cooldown_H*3600);
      if(canAlert)
        {
         string sig  = isUptrend ? "BUY" : "SELL";
         string icon = isUptrend ? "🟢" : "🔴";
         string msg  = icon+" SMC+Fib | "+_Symbol+"\n"+
                       "Signal: "+sig+"\n"+
                       "Trend: "+(isUptrend?"UP":"DOWN")+"\n"+
                       "BOS: "+(bos?"OK":"NO")+" | OB: "+(nearOB?"OK":"NO")+"\n"+
                       "---\n"+
                       "Entry: "+DoubleToString(fib618,_Digits)+"\n"+
                       "SL:    "+DoubleToString(fib786,_Digits)+"\n"+
                       "---\n"+
                       "TP1:   "+DoubleToString(fib0,_Digits)+"\n"+
                       "TP2:   "+DoubleToString(fib1272,_Digits)+"\n"+
                       "TP3:   "+DoubleToString(fib1618,_Digits)+"\n"+
                       TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);

         if(SendTelegram) SendToTelegram(msg);
         if(SendPush)     SendNotification(icon+" SMC+Fib: "+sig+" "+_Symbol);
         lastAlert = TimeCurrent();
         lastType  = sig;
         lastEntry = fib618;
         lastSL    = fib786;
         lastTP1   = fib0;
         lastTP2   = fib1272;
         lastTP3   = fib1618;
         lastTime  = TimeCurrent();
         Print(msg);
        }
     }

   // Draw Lines and Panel
   DrawFibLines();
   if(obIdx>0) DrawOB(obH, obL, time[obIdx], time[0]);
   DrawEntryZone(time[0]);
   if(ShowPanel) DrawPanel(close[0], bos, obIdx>0);
  }

//+------------------------------------------------------------------+
//| FIND SWINGS                                                      |
//+------------------------------------------------------------------+
void FindSwings(const double &high[], const double &low[])
  {
   swingHigh=high[0]; swingLow=low[0]; highBar=0; lowBar=0;
   for(int i=1;i<FibLookback;i++)
     {
      if(high[i]>swingHigh){swingHigh=high[i];highBar=i;}
      if(low[i]<swingLow) {swingLow=low[i]; lowBar=i;}
     }
   isUptrend=(lowBar>highBar);
  }

//+------------------------------------------------------------------+
//| CALC FIB                                                         |
//+------------------------------------------------------------------+
void CalcFib()
  {
   double r=swingHigh-swingLow;
   if(isUptrend)
     { fib0=swingHigh;fib382=swingHigh-r*0.382;fib50=swingHigh-r*0.5;
       fib618=swingHigh-r*0.618;fib786=swingHigh-r*0.786;fib100=swingLow;
       fib1272=swingHigh+r*0.272;fib1618=swingHigh+r*0.618; }
   else
     { fib0=swingLow;fib382=swingLow+r*0.382;fib50=swingLow+r*0.5;
       fib618=swingLow+r*0.618;fib786=swingLow+r*0.786;fib100=swingHigh;
       fib1272=swingLow-r*0.272;fib1618=swingLow-r*0.618; }
  }

bool IsInFibZone(double p)
  { return isUptrend?(p>=fib786&&p<=fib50):(p<=fib786&&p>=fib50); }

bool IsNearOB(double p,double obH,double obL)
  { if(obH==0||obL==0)return true;
    double buf=(obH-obL)*0.5;
    return(p>=obL-buf&&p<=obH+buf); }

bool IsTrendOK(double p)
  { int h=iMA(_Symbol,PERIOD_CURRENT,50,0,MODE_EMA,PRICE_CLOSE);
    double e[];ArraySetAsSeries(e,true);
    if(CopyBuffer(h,0,0,1,e)<1){IndicatorRelease(h);return true;}
    bool ok=isUptrend?(p>e[0]):(p<e[0]);
    IndicatorRelease(h);return ok; }

int FindOB(const double &o[],const double &c[],const double &h[],const double &l[],double &obH,double &obL)
  {
   if(isUptrend)
     { for(int i=1;i<OB_Lookback+10;i++)
         if(c[i]<o[i]&&i>1&&c[i-1]>o[i-1]&&c[i-1]>h[i])
           {obH=h[i];obL=l[i];return i;} }
   else
     { for(int i=1;i<OB_Lookback+10;i++)
         if(c[i]>o[i]&&i>1&&c[i-1]<o[i-1]&&c[i-1]<l[i])
           {obH=h[i];obL=l[i];return i;} }
   return 0;
  }

bool CheckBOS(const double &c[],const double &h[],const double &l[])
  {
   if(isUptrend){double pH=0;for(int i=BOS_Lookback;i>=2;i--)if(h[i]>pH)pH=h[i];return c[1]>pH;}
   else{double pL=999999;for(int i=BOS_Lookback;i>=2;i--)if(l[i]<pL)pL=l[i];return c[1]<pL;}
  }

//+------------------------------------------------------------------+
//| DRAW FUNCTIONS                                                   |
//+------------------------------------------------------------------+
void DrawFibLines()
  {
   DHL(pfx+"f0",  fib0,  "0% TP1",   clrGold,       2);
   DHL(pfx+"f50", fib50, "50%",       clrDimGray,    1);
   DHL(pfx+"f62", fib618,"61.8% Entry",clrLimeGreen,  2);
   DHL(pfx+"f78", fib786,"78.6% SL",  clrTomato,     2);
   DHL(pfx+"f100",fib100,"100%",       clrDimGray,    1);
   DHL(pfx+"tp2", fib1272,"127.2% TP2",clrDeepSkyBlue,1);
   DHL(pfx+"tp3", fib1618,"161.8% TP3",clrViolet,    1);
   ChartRedraw();
  }

void DrawOB(double obH,double obL,datetime t1,datetime t2)
  {
   string n=pfx+"ob";
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,obH,t2+PeriodSeconds()*20,obL);
   ObjectSetInteger(0,n,OBJPROP_TIME,0,t1);  ObjectSetDouble(0,n,OBJPROP_PRICE,0,obH);
   ObjectSetInteger(0,n,OBJPROP_TIME,1,t2+PeriodSeconds()*20); ObjectSetDouble(0,n,OBJPROP_PRICE,1,obL);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clrOrange);
   ObjectSetInteger(0,n,OBJPROP_FILL,true); ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetString(0,n,OBJPROP_TEXT,"OB"); ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ChartRedraw();
  }

void DrawEntryZone(datetime t)
  {
   string n=pfx+"zone";
   double zH=isUptrend?fib50:fib786, zL=isUptrend?fib786:fib50;
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE,0,iTime(_Symbol,PERIOD_CURRENT,FibLookback),zH,t+PeriodSeconds()*20,zL);
   ObjectSetInteger(0,n,OBJPROP_TIME,0,iTime(_Symbol,PERIOD_CURRENT,FibLookback));
   ObjectSetDouble(0,n,OBJPROP_PRICE,0,zH);
   ObjectSetInteger(0,n,OBJPROP_TIME,1,t+PeriodSeconds()*20);
   ObjectSetDouble(0,n,OBJPROP_PRICE,1,zL);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clrLimeGreen);
   ObjectSetInteger(0,n,OBJPROP_FILL,true); ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ChartRedraw();
  }

void DrawPanel(double price,bool bos,bool ob)
  {
   int x=PanelX,y=PanelY,w=270,lh=18,h=11*lh+20;
   color tpC=isUptrend?clrLimeGreen:clrTomato;
   bool inZone=IsInFibZone(price);
   PBG(pfx+"bg",x,y,w,h,C'22,22,32',C'55,55,75');
   int cy=y+8;
   PLbl(pfx+"t0","  SMC + Fibonacci EA",x+5,cy,clrGold,9,true); cy+=lh;
   PHL(pfx+"l0",x,cy,w); cy+=5;
   PLbl(pfx+"tr","  Trend: "+(isUptrend?"UP":"DOWN"),x+5,cy,tpC,9,true); cy+=lh;
   string zStr=inZone?"✅ In Zone!":"⏳ Wait";
   color  zC=inZone?clrLimeGreen:clrGray;
   PLbl(pfx+"c1","  BOS:"+(bos?"✅":"❌")+"  OB:"+(ob?"✅":"❌")+"  Fib:"+zStr,x+5,cy,zC,9); cy+=lh;
   PHL(pfx+"l1",x,cy,w); cy+=4;
   PR(pfx+"f62","  61.8% Entry:",DoubleToString(fib618,_Digits),x,cy,w,clrWhite,clrLimeGreen,9); cy+=lh;
   PR(pfx+"f78","  78.6% SL:",  DoubleToString(fib786,_Digits),x,cy,w,clrWhite,clrTomato,   9); cy+=lh;
   PR(pfx+"f0", "  0.0%  TP1:", DoubleToString(fib0,  _Digits),x,cy,w,clrWhite,clrGold,     9); cy+=lh;
   PR(pfx+"tp2","  127.2% TP2:",DoubleToString(fib1272,_Digits),x,cy,w,clrWhite,clrDeepSkyBlue,9); cy+=lh;
   PR(pfx+"tp3","  161.8% TP3:",DoubleToString(fib1618,_Digits),x,cy,w,clrWhite,clrViolet,  9); cy+=lh;
   if(lastEntry>0)
     { PHL(pfx+"l2",x,cy,w); cy+=4;
       PLbl(pfx+"ls","  Last Signal: "+lastType+" | "+TimeToString(lastTime,TIME_MINUTES),x+5,cy,tpC,9); }
   ChartRedraw();
  }

void PO(string n,ENUM_OBJECT t){if(ObjectFind(0,n)<0)ObjectCreate(0,n,t,0,0,0);}

void PLbl(string n,string txt,int x,int y,color c,int fs,bool bold=false)
  { PO(n,OBJ_LABEL);
    ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
    ObjectSetString(0,n,OBJPROP_TEXT,txt);ObjectSetInteger(0,n,OBJPROP_COLOR,c);
    ObjectSetInteger(0,n,OBJPROP_FONTSIZE,fs);ObjectSetString(0,n,OBJPROP_FONT,bold?"Arial Bold":"Arial");
    ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
    ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,n,OBJPROP_BACK,false); }

void PR(string p,string lbl,string val,int x,int y,int w,color lc,color vc,int fs)
  {PLbl(p+"l",lbl,x+5,y,lc,fs);PLbl(p+"v",val,x+w-90,y,vc,fs,true);}

void PHL(string n,int x,int y,int w)
  { PO(n,OBJ_RECTANGLE_LABEL);
    ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
    ObjectSetInteger(0,n,OBJPROP_XSIZE,w);ObjectSetInteger(0,n,OBJPROP_YSIZE,1);
    ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C'55,55,75');
    ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
    ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
    ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); }

void PBG(string n,int x,int y,int w,int h,color bg,color border)
  { PO(n,OBJ_RECTANGLE_LABEL);
    ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
    ObjectSetInteger(0,n,OBJPROP_XSIZE,w);ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
    ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,n,OBJPROP_COLOR,border);
    ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
    ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
    ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,n,OBJPROP_BACK,false); }

void DHL(string n,double p,string lbl,color c,int w)
  { if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_HLINE,0,0,p);
    ObjectSetDouble(0,n,OBJPROP_PRICE,p);ObjectSetInteger(0,n,OBJPROP_COLOR,c);
    ObjectSetInteger(0,n,OBJPROP_WIDTH,w);ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DASH);
    ObjectSetString(0,n,OBJPROP_TEXT,lbl);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); }
//+------------------------------------------------------------------+