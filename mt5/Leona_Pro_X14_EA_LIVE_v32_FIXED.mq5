#property strict
#property version "3.2"
#property description "Leona Pro X EA LIVE v3.2 - API-connected adaptive synthetic scalper"

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

input group "Trading Parameters"
input double LotSize = 0.01;
input double RiskPercent = 1.0;
input int MaxSpread = 0; // Legacy fixed-point filter disabled by default
input bool UseSmartSpreadFilter = true;
input double MaxSpreadATRPercent = 75.0;
input double MaxSpreadPricePercent = 0.020;
input bool ShowSpreadDiagnostics = true;
input int SL_Points = 150;
input int TP_Points = 250;
input bool UseATRStops = true;
input double ATR_SL_Multiplier = 1.20;
input int ATR_MinSLPoints = 150;
input int ATR_MaxSLPoints = 5000;
input double ATR_RiskReward = 1.80;
input bool EA_Active = true;

input group "Filters"
input int MinVolatility = 60;
input int MaxVolatility = 300;
input bool UseAdaptiveVolatilityFilter = true;
input double MinATRPricePercent = 0.01;
input double MaxATRPricePercent = 1.00;
input double MinSyntheticATRPrice = 0.0;
input double MaxSyntheticATRPrice = 1000000.0;
input double MinTrendStrength = 2.5;
input int AIScoreThreshold = 6; // Minimum AI score required for an entry

input group "Time & Cooldown"
input int CooldownSeconds = 1;
input int MaxTradesPerHour = 100;
input bool TradeDuringNews = false;
input int StartHour = 0;
input int EndHour = 23;

input group "Exit Strategies"
input bool UseTrailingStop = true;
input int TrailingStart = 80;
input int TrailingStep = 20;
input bool UseBreakEven = true;
input int BreakEvenTrigger = 50;

input group "Risk Management"
input double MaxDailyLoss = 3.0;
input double MaxDrawdown = 10.0;
input bool UseEquityProtection = true;
input int MaxConsecutiveLosses = 10;

input group "Remote Control"
input string ApiBaseUrl = "https://leona-pro-x-api.onrender.com";
input string DeviceId = "";
input string EaToken = "";
input int RemotePollSeconds = 5;
input bool EnableRemoteControl = true;
input bool RequireSupportedBroker = true;
input string AllowedBrokers = "weltrade,deriv";
input bool SyntheticOnly = true;
input bool DebugTrading = true;
input bool AggressiveScalping = true;
input int MaxOpenPositions = 100;
input double MinimumAccountBalance = 2.0;
input int MinimumProfitScalePositions = 5;
input double ProfitRequiredToScale = 0.01;
input double MinimumMarginLevelToAdd = 300.0;
input double MinMarginLevel = 300.0;
input double MaxLotPercentOfBalance = 5.0;
input double BalancePerOpenTrade = 100.0;
input int MaxSlippagePoints = 20;

// Live remote risk settings and bounded adaptive-learning state
double lotSizeLive=0.01;
bool useRiskSizingLive=true;
int learningTrades=0;
int learningWins=0;
int learningLosses=0;
double learningNetProfit=0.0;
double adaptiveThreshold=6.0;
string diagnosticBlocker="STARTING";
double diagnosticSpreadPoints=0.0;
double diagnosticATR=0.0;
int diagnosticScore=0;
double diagnosticADX=0.0;
bool apiHeartbeatOK=false;
datetime lastHeartbeatTime=0;
input bool EnableAdaptiveLearning = true;
input int LearningWindowTrades = 30;
input double AdaptiveThresholdMin = 4.0;
input double AdaptiveThresholdMax = 9.0;
input double LearningStep = 0.25;

CTrade trade;
CAccountInfo accountInfo;

int handleMA = INVALID_HANDLE;
int handleRSI = INVALID_HANDLE;
int handleADX = INVALID_HANDLE;
int handleATR = INVALID_HANDLE;
int handleMACD = INVALID_HANDLE;

datetime lastTradeTime = 0;
int tradesThisHour = 0;
int currentHour = -1;
int consecutiveLosses = 0;
double startingBalance = 0.0;
double equityPeak = 0.0;
datetime lastResetDate = 0;
bool isTradingPaused = false;
bool remoteTradingEnabled = true;
double riskPercentLive = 1.0;
int slPointsLive = 150;
int tpPointsLive = 250;
double maxDailyLossLive = 3.0;
double maxDrawdownLive = 10.0;

string LearningKey(){ return "LeonaPX_Learn_"+IntegerToString((int)ChartID()); }

void LoadLearningState(){ string k=LearningKey(); if(GlobalVariableCheck(k)) adaptiveThreshold=GlobalVariableGet(k); adaptiveThreshold=MathMax(AdaptiveThresholdMin,MathMin(AdaptiveThresholdMax,adaptiveThreshold)); }
void SaveLearningState(){ GlobalVariableSet(LearningKey(),adaptiveThreshold); }

string Url(string path) { return ApiBaseUrl + path; }

int CountLeonaPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetInteger(POSITION_MAGIC)==123456)
         count++;
   }
   return count;
}

void UpdateChartStatus()
{
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   string company=AccountInfoString(ACCOUNT_COMPANY);
   string apiState=apiHeartbeatOK ? "CONNECTED" : "WAITING";
   string runState=(!EA_Active || !remoteTradingEnabled || isTradingPaused) ? "PAUSED" : "ACTIVE";
   int threshold=(int)MathRound(EnableAdaptiveLearning ? adaptiveThreshold : (double)AIScoreThreshold);
   if(AggressiveScalping) threshold=MathMax(1,threshold-1);

   Comment(
      "LEONA PRO X EA LIVE v3.2\n",
      "MODE: ",AggressiveScalping ? "AGGRESSIVE SCALPER" : "STANDARD SCALPER","\n",
      "STATUS: ",runState,"\n",
      "BROKER: ",company,"\n",
      "SYMBOL: ",_Symbol," | M5\n",
      "API: ",apiState," | HEARTBEAT: ",apiHeartbeatOK ? "OK" : "WAITING","\n",
      "AI SCORE: ",diagnosticScore," | THRESHOLD: ",threshold," | ADX: ",DoubleToString(diagnosticADX,1),"\n",
      "POSITIONS: ",CountLeonaPositions(),"/",MaxOpenPositions," | MARGIN LEVEL: ",DoubleToString(marginLevel,1),"%\n",
      "SPREAD: ",DoubleToString(diagnosticSpreadPoints,1)," pts | ATR: ",DoubleToString(diagnosticATR,_Digits),"\n",
      "BALANCE: ",DoubleToString(balance,2)," | EQUITY: ",DoubleToString(equity,2),"\n",
      "BLOCKER: ",diagnosticBlocker
   );
}

bool HttpRequest(string method,string url,string body,string &response,string token="")
{
   char data[], result[];
   string headers="Content-Type: application/json\r\n";
   if(token!="") headers += "X-EA-Token: "+token+"\r\n";
   string resultHeaders;
   if(body!="") StringToCharArray(body,data,0,StringLen(body),CP_UTF8);
   ResetLastError();
   int code=WebRequest(method,url,headers,10000,data,result,resultHeaders);
   if(code<0) { Print("Leona API WebRequest error: ",GetLastError()); return false; }
   response=CharArrayToString(result,0,-1,CP_UTF8);
   Print("Leona API ",method," HTTP ",code," -> ",url);
   return code>=200 && code<300;
}

void SendHeartbeat()
{
   if(!EnableRemoteControl || EaToken=="") { Print("Leona heartbeat skipped: remote control disabled or EA token missing"); return; }
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double pl=AccountInfoDouble(ACCOUNT_PROFIT);
   double dd=bal>0 ? (bal-eq)/bal*100.0 : 0.0;
   string broker=AccountInfoString(ACCOUNT_COMPANY);
   string symbol=_Symbol;
   StringReplace(broker,"\\","\\\\");
   StringReplace(broker,"\"","\\\"");
   StringReplace(symbol,"\\","\\\\");
   StringReplace(symbol,"\"","\\\"");
   string body=StringFormat("{\"balance\":%.2f,\"equity\":%.2f,\"profit\":%.2f,\"drawdown\":%.2f,\"ea_active\":%s,\"broker\":\"%s\",\"symbol\":\"%s\"}",
      bal,eq,pl,dd,(EA_Active && remoteTradingEnabled && !isTradingPaused)?"true":"false",broker,symbol);
   string response;
   bool ok=HttpRequest("POST",Url("/api/v1/ea/heartbeat"),body,response,EaToken);
   if(ok)
   {
      apiHeartbeatOK=true;
      lastHeartbeatTime=TimeCurrent();
      Print("Leona heartbeat accepted by API");
   }
   else
   {
      apiHeartbeatOK=false;
      Print("Leona heartbeat failed");
   }
}

void ReportCommand(string id,string status,string message)
{
   string safe=message;
   StringReplace(safe,"\\","\\\\");
   StringReplace(safe,"\"","\\\"");
   string body=StringFormat("{\"command_id\":\"%s\",\"status\":\"%s\",\"message\":\"%s\"}",id,status,safe);
   string response;
   HttpRequest("POST",Url("/api/v1/commands/result"),body,response,EaToken);
}

string ExtractString(string json,string key,int from=0)
{
   string needle="\""+key+"\":\"";
   int p=StringFind(json,needle,from);
   if(p<0) return "";
   p+=StringLen(needle);
   int e=StringFind(json,"\"",p);
   if(e<0) return "";
   return StringSubstr(json,p,e-p);
}

bool ExtractNumber(string json,string key,double &value)
{
   string needle="\"" + key + "\":";
   int p=StringFind(json,needle);
   if(p<0) return false;
   p+=StringLen(needle);
   int e=p;
   int n=StringLen(json);
   while(e<n)
   {
      ushort ch=StringGetCharacter(json,e);
      if((ch>='0' && ch<='9') || ch=='-' || ch=='+' || ch=='.' || ch=='e' || ch=='E') e++;
      else break;
   }
   if(e<=p) return false;
   value=StringToDouble(StringSubstr(json,p,e-p));
   return true;
}

bool ApplyRiskSettings(string json)
{
   double v;
   bool any=false;
   if(ExtractNumber(json,"risk_percent",v) && v>=0.01 && v<=10.0) { riskPercentLive=v; any=true; }
   if(ExtractNumber(json,"lot_size",v) && v>=0.001 && v<=100.0) { lotSizeLive=v; any=true; }
   string sizing=ExtractString(json,"sizing_mode");
   if(sizing=="RISK") { useRiskSizingLive=true; any=true; }
   else if(sizing=="FIXED_LOT") { useRiskSizingLive=false; any=true; }
   if(ExtractNumber(json,"sl_points",v) && v>=1 && v<=100000) { slPointsLive=(int)v; any=true; }
   if(ExtractNumber(json,"tp_points",v) && v>=1 && v<=100000) { tpPointsLive=(int)v; any=true; }
   if(ExtractNumber(json,"max_daily_loss",v) && v>=0.1 && v<=50.0) { maxDailyLossLive=v; any=true; }
   if(ExtractNumber(json,"max_drawdown",v) && v>=0.1 && v<=90.0) { maxDrawdownLive=v; any=true; }
   return any;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   long magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(magic!=123456) return;
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   double pnl=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)
             +HistoryDealGetDouble(trans.deal,DEAL_SWAP)
             +HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   if(pnl<0) consecutiveLosses++;
   else if(pnl>0) consecutiveLosses=0;
   learningTrades++;
   learningNetProfit+=pnl;
   if(pnl>0) learningWins++; else if(pnl<0) learningLosses++;
   if(EnableAdaptiveLearning && learningTrades>=LearningWindowTrades)
   {
      double winRate=(double)learningWins/(double)MathMax(learningTrades,1);
      if(winRate<0.40) adaptiveThreshold=MathMin(AdaptiveThresholdMax,adaptiveThreshold+LearningStep);
      else if(winRate>0.60) adaptiveThreshold=MathMax(AdaptiveThresholdMin,adaptiveThreshold-LearningStep);
      learningTrades=0; learningWins=0; learningLosses=0; learningNetProfit=0.0;
      SaveLearningState();
      Print("Leona Learning: adjusted entry threshold to ",DoubleToString(adaptiveThreshold,2));
   }
   Print("Leona: closed trade P/L=",DoubleToString(pnl,2)," consecutive losses=",consecutiveLosses);
}

void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
      {
         long magic=PositionGetInteger(POSITION_MAGIC);
         string symbol=PositionGetString(POSITION_SYMBOL);
         if(magic!=123456) continue;
         if(!trade.PositionClose(ticket))
            Print("Leona: failed to close EA ticket ",ticket," symbol=",symbol," retcode=",trade.ResultRetcode());
      }
   }
}

void ProcessRemoteCommands()
{
   if(!EnableRemoteControl || DeviceId=="" || EaToken=="") return;
   string response;
   if(!HttpRequest("GET",Url("/api/v1/devices/"+DeviceId+"/commands"),"",response,EaToken)) return;

   int pos=0;
   while(true)
   {
      string id=ExtractString(response,"command_id",pos);
      if(id=="") break;
      int idEnd=StringFind(response,"\"command_id\":\""+id+"\"",pos);
      string cmd=ExtractString(response,"command",idEnd);
      bool ok=true;
      string msg="Command executed";

      if(cmd=="SET_INSTRUMENT")
      {
         string targetBroker=ExtractString(response,"broker",idEnd);
         string targetSymbol=ExtractString(response,"symbol",idEnd);
         if(targetBroker=="" || targetSymbol=="")
         {
            ok=false;
            msg="Missing broker or symbol";
         }
         else
         {
            string checkSymbol=targetSymbol;
            StringToLower(checkSymbol);
            bool synthetic=StringFind(checkSymbol,"vol")>=0 || StringFind(checkSymbol,"volatility")>=0;
            string checkBroker=targetBroker;
            StringToLower(checkBroker);
            if((checkBroker!="weltrade" && checkBroker!="deriv") || !synthetic)
            {
               ok=false;
               msg="Unsupported synthetic broker or symbol";
            }
            else if(!SymbolSelect(targetSymbol,true))
            {
               ok=false;
               msg="Symbol is not available in this MT5 account: "+targetSymbol;
            }
            else
            {
               msg="Switching chart to "+targetBroker+" / "+targetSymbol;
               Print("Leona: switching instrument to ",targetBroker," / ",targetSymbol);
               ReportCommand(id,"COMPLETED",msg);
               ChartSetSymbolPeriod(0,targetSymbol,PERIOD_M5);
               return;
            }
         }
      }
      else if(cmd=="START_ROBOT") { remoteTradingEnabled=true; GlobalVariableSet("LEONA_EA_ACTIVE",1.0); }
      else if(cmd=="STOP_ROBOT") { remoteTradingEnabled=false; GlobalVariableSet("LEONA_EA_ACTIVE",0.0); }
      else if(cmd=="CLOSE_ALL") CloseAllPositions();
      else if(cmd=="UPDATE_RISK")
      {
         if(ApplyRiskSettings(response))
            msg=StringFormat("Sizing applied: %s, lot %.2f, risk %.2f%%, SL %d, TP %d, daily loss %.2f%%, drawdown %.2f%%",useRiskSizingLive?"RISK":"FIXED_LOT",lotSizeLive,riskPercentLive,slPointsLive,tpPointsLive,maxDailyLossLive,maxDrawdownLive);
         else { ok=false; msg="Invalid or missing risk settings"; }
      }
      else { ok=false; msg="Unsupported command"; }

      ReportCommand(id,ok?"COMPLETED":"FAILED",msg);
      pos++;
   }
}

bool BrokerAndSymbolOK()
{
   if(RequireSupportedBroker)
   {
      string company=AccountInfoString(ACCOUNT_COMPANY);
      StringToLower(company);
      bool brokerOk=false;
      string allowed=AllowedBrokers;
      StringToLower(allowed);
      string parts[];
      int count=StringSplit(allowed,',',parts);
      for(int i=0;i<count;i++)
      {
         string name=parts[i];
         StringTrimLeft(name);
         StringTrimRight(name);
         if(name!="" && StringFind(company,name)>=0)
         {
            brokerOk=true;
            break;
         }
      }
      if(!brokerOk) return false;
   }

   if(!SyntheticOnly) return true;

   string symbol=_Symbol;
   StringToLower(symbol);
   bool synthetic=
      StringFind(symbol,"vol")>=0 ||
      StringFind(symbol,"volatility")>=0;

   return synthetic;
}

bool SpreadOK()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0 || tick.bid<=0 || tick.ask<=0)
      return false;

   double spreadPrice=tick.ask-tick.bid;
   double spreadPoints=spreadPrice/point;
   diagnosticSpreadPoints=spreadPoints;

   double atr=BufferValue(handleATR,0,0);
   diagnosticATR=(atr==EMPTY_VALUE ? 0.0 : atr);

   // Optional legacy guard. Zero means disabled.
   if(MaxSpread>0 && spreadPoints>MaxSpread)
      return false;

   if(!UseSmartSpreadFilter)
      return true;

   if(atr<=0)
      return false;

   double allowedByATR=atr*(MaxSpreadATRPercent/100.0);
   double allowedByPrice=tick.bid*(MaxSpreadPricePercent/100.0);
   double allowedPrice=0.0;

   if(allowedByATR>0 && allowedByPrice>0)
      allowedPrice=MathMin(allowedByATR,allowedByPrice);
   else if(allowedByATR>0)
      allowedPrice=allowedByATR;
   else
      allowedPrice=allowedByPrice;

   bool ok=(allowedPrice>0 && spreadPrice<=allowedPrice);

   if(ShowSpreadDiagnostics)
   {
      static datetime lastLog=0;
      if(TimeCurrent()!=lastLog)
      {
         lastLog=TimeCurrent();
         PrintFormat("Leona SPREAD %s | spread=%.1f points (%.5f price) | ATR=%.5f | ATR%%=%.1f | allowed=%.5f",
                     ok ? "OK" : "BLOCKED",
                     spreadPoints,spreadPrice,atr,
                     atr>0 ? spreadPrice/atr*100.0 : 0.0,
                     allowedPrice);
      }
   }

   return ok;
}

bool TimeOK()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(StartHour<=EndHour) return t.hour>=StartHour && t.hour<=EndHour;
   return t.hour>=StartHour || t.hour<=EndHour;
}

void ResetDaily()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   datetime day=StringToTime(StringFormat("%04d.%02d.%02d",t.year,t.mon,t.day));
   if(lastResetDate!=day)
   {
      lastResetDate=day;
      startingBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      consecutiveLosses=0;
      isTradingPaused=false;
   }
}

bool RiskManagementOK()
{
   // Risk-management blocking has been intentionally disabled for the
   // aggressive scalping build. Trading is no longer stopped by daily loss,
   // drawdown, consecutive-loss, equity, margin, balance, position-count,
   // or hourly-trade risk gates.
   return true;
}
double BufferValue(int handle,int buffer,int shift)
{
   double a[];
   ArraySetAsSeries(a,true);
   if(CopyBuffer(handle,buffer,shift,1,a)!=1) return EMPTY_VALUE;
   return a[0];
}

int AIScore()
{
   double ma=BufferValue(handleMA,0,0);
   double maPrev=BufferValue(handleMA,0,1);
   double rsi=BufferValue(handleRSI,0,0);
   double rsiPrev=BufferValue(handleRSI,0,1);
   double macd=BufferValue(handleMACD,0,0);
   double signal=BufferValue(handleMACD,1,0);
   double macdPrev=BufferValue(handleMACD,0,1);
   double signalPrev=BufferValue(handleMACD,1,1);
   double adx=BufferValue(handleADX,0,0);
   double atr=BufferValue(handleATR,0,0);

   if(ma==EMPTY_VALUE || rsi==EMPTY_VALUE || macd==EMPTY_VALUE || signal==EMPTY_VALUE || adx==EMPTY_VALUE || atr==EMPTY_VALUE) return 0;

   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int score=0;
   score += price>ma ? 2 : -2;
   score += ma>maPrev ? 1 : -1;
   score += rsi>50 && rsi>rsiPrev ? 1 : -1;
   if(macd>signal && macdPrev<=signalPrev) score+=3;
   else if(macd<signal && macdPrev>=signalPrev) score-=3;
   if(adx>25) score += price>ma ? 2 : -2;
   if(adx>40) score += price>ma ? 1 : -1;
   if(atr>100*_Point) score += price>ma ? 1 : -1;
   if(atr>150*_Point) score += price>ma ? 1 : -1;

   double o1=iOpen(_Symbol,PERIOD_M5,1),c1=iClose(_Symbol,PERIOD_M5,1);
   double o2=iOpen(_Symbol,PERIOD_M5,2),c2=iClose(_Symbol,PERIOD_M5,2);
   if(c1>o1 && c2<o2 && c1>o2 && o1<c2) score+=2;
   if(c1<o1 && c2>o2 && c1<o2 && o1>c2) score-=2;

   return score;
}

bool VolatilityOK()
{
   double atr=BufferValue(handleATR,0,0);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(atr==EMPTY_VALUE || atr<=0 || bid<=0) return false;

   // Synthetic indices can have large price-unit ATR values, so using
   // forex-style fixed points (ATR/_Point) can incorrectly block valid markets.
   if(UseAdaptiveVolatilityFilter)
   {
      double atrPercent=(atr/bid)*100.0;
      bool percentOK=(atrPercent>=MinATRPricePercent && atrPercent<=MaxATRPricePercent);
      bool absoluteOK=(atr>=MinSyntheticATRPrice && atr<=MaxSyntheticATRPrice);
      if(DebugTrading)
      {
         static datetime lastVolLog=0;
         if(TimeCurrent()!=lastVolLog)
         {
            lastVolLog=TimeCurrent();
            PrintFormat("Leona VOLATILITY %s | ATR=%.5f | ATR%%=%.4f | range=%.4f-%.4f%%",
                        (percentOK && absoluteOK) ? "OK" : "BLOCKED",
                        atr,atrPercent,MinATRPricePercent,MaxATRPricePercent);
         }
      }
      return percentOK && absoluteOK;
   }

   // Legacy fixed-point mode remains available for symbols where it is appropriate.
   double points=atr/_Point;
   return points>=MinVolatility && points<=MaxVolatility;
}

bool MultiTimeframeConfirm(bool buy)
{
   ENUM_TIMEFRAMES frames[3]={PERIOD_M5,PERIOD_M15,PERIOD_H1};
   int confirmed=0;
   for(int i=0;i<3;i++)
   {
      int h=iMA(_Symbol,frames[i],20,0,MODE_SMA,PRICE_CLOSE);
      if(h==INVALID_HANDLE) continue;
      double b[];
      ArraySetAsSeries(b,true);
      if(CopyBuffer(h,0,0,1,b)==1)
      {
         double p=iClose(_Symbol,frames[i],0);
         if((buy && p>b[0]) || (!buy && p<b[0])) confirmed++;
      }
      IndicatorRelease(h);
   }
   // Aggressive mode needs only one of M5/M15/H1 aligned;
   // standard mode keeps the stronger 2-of-3 confirmation.
   return AggressiveScalping ? confirmed>=1 : confirmed>=2;
}


bool MarginAllowsNewTrade(ENUM_ORDER_TYPE orderType,double volume,double price)
{
   // Keep only the broker's fundamental free-margin requirement.
   // The previous 300% future-margin gate prevented aggressive scaling.
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin<=0) return false;

   double required=0.0;
   if(!OrderCalcMargin(orderType,_Symbol,volume,price,required) || required<=0)
      return false;

   return required < freeMargin;
}

double CalculateLotSize(double stopDistancePrice=0.0)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0) minLot=0.01;
   if(maxLot<=0) maxLot=100.0;
   if(step<=0) step=minLot;

   if(!useRiskSizingLive)
   {
      double lot=MathMax(minLot,MathMin(maxLot,lotSizeLive));
      lot=MathFloor(lot/step)*step;
      return NormalizeDouble(MathMax(minLot,lot),2);
   }

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney=balance*MathMax(0.01,riskPercentLive)/100.0;
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double distance=(stopDistancePrice>0 ? stopDistancePrice : slPointsLive*_Point);

   if(tickValue<=0 || tickSize<=0 || distance<=0)
      return NormalizeDouble(MathMax(minLot,MathMin(maxLot,LotSize)),2);

   double valuePerPriceUnit=tickValue/tickSize;
   double lot=riskMoney/(distance*valuePerPriceUnit);
   lot=MathMax(minLot,MathMin(maxLot,lot));
   lot=MathFloor(lot/step)*step;
   return NormalizeDouble(MathMax(minLot,lot),2);
}

void OpenBuy()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double atr=BufferValue(handleATR,0,0);
   if(atr==EMPTY_VALUE || atr<=0) return;

   double slDistance=UseATRStops ? atr*ATR_SL_Multiplier : slPointsLive*_Point;
   slDistance=MathMax(slDistance,ATR_MinSLPoints*_Point);
   slDistance=MathMin(slDistance,ATR_MaxSLPoints*_Point);

   double tpDistance=UseATRStops ? slDistance*ATR_RiskReward : tpPointsLive*_Point;
   double lot=CalculateLotSize(slDistance);

   if(!MarginAllowsNewTrade(ORDER_TYPE_BUY,lot,ask)) { if(DebugTrading) Print("Leona DEBUG: BUY blocked by available margin."); return; }

   double sl=NormalizeDouble(ask-slDistance,_Digits);
   double tp=NormalizeDouble(ask+tpDistance,_Digits);
   bool sent=trade.Buy(lot,_Symbol,ask,sl,tp,"Leona Pro X BUY");
   uint rc=trade.ResultRetcode();
   if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED))
   {
      lastTradeTime=TimeCurrent(); tradesThisHour++;
      diagnosticBlocker="BUY EXECUTED";
      Print("Leona BUY EXECUTED. lot=",lot," SL=",sl," TP=",tp," retcode=",rc);
   }
   else
   {
      diagnosticBlocker="BUY REJECTED";
      Print("Leona BUY REJECTED. sent=",sent," retcode=",rc," description=",trade.ResultRetcodeDescription(),
            " lot=",lot," spread=",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD));
   }
}

void OpenSell()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double atr=BufferValue(handleATR,0,0);
   if(atr==EMPTY_VALUE || atr<=0) return;

   double slDistance=UseATRStops ? atr*ATR_SL_Multiplier : slPointsLive*_Point;
   slDistance=MathMax(slDistance,ATR_MinSLPoints*_Point);
   slDistance=MathMin(slDistance,ATR_MaxSLPoints*_Point);

   double tpDistance=UseATRStops ? slDistance*ATR_RiskReward : tpPointsLive*_Point;
   double lot=CalculateLotSize(slDistance);

   if(!MarginAllowsNewTrade(ORDER_TYPE_SELL,lot,bid)) { if(DebugTrading) Print("Leona DEBUG: SELL blocked by available margin."); return; }

   double sl=NormalizeDouble(bid+slDistance,_Digits);
   double tp=NormalizeDouble(bid-tpDistance,_Digits);
   bool sent=trade.Sell(lot,_Symbol,bid,sl,tp,"Leona Pro X SELL");
   uint rc=trade.ResultRetcode();
   if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED))
   {
      lastTradeTime=TimeCurrent(); tradesThisHour++;
      diagnosticBlocker="SELL EXECUTED";
      Print("Leona SELL EXECUTED. lot=",lot," SL=",sl," TP=",tp," retcode=",rc);
   }
   else
   {
      diagnosticBlocker="SELL REJECTED";
      Print("Leona SELL REJECTED. sent=",sent," retcode=",rc," description=",trade.ResultRetcodeDescription(),
            " lot=",lot," spread=",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD));
   }
}

void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=123456) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol!=_Symbol) continue;

      long type=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double price=type==POSITION_TYPE_BUY?SymbolInfoDouble(symbol,SYMBOL_BID):SymbolInfoDouble(symbol,SYMBOL_ASK);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0) point=_Point;
      double profitPoints=(type==POSITION_TYPE_BUY?(price-open):(open-price))/point;

      if(UseBreakEven && profitPoints>=BreakEvenTrigger)
      {
         double newSL=NormalizeDouble(open,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
         if((type==POSITION_TYPE_BUY && (sl<newSL || sl==0)) || (type==POSITION_TYPE_SELL && (sl>newSL || sl==0)))
            trade.PositionModify(ticket,newSL,tp);
      }

      if(UseTrailingStop && profitPoints>=TrailingStart)
      {
         double newSL=type==POSITION_TYPE_BUY?price-TrailingStep*point:price+TrailingStep*point;
         newSL=NormalizeDouble(newSL,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
         if((type==POSITION_TYPE_BUY && newSL>sl) || (type==POSITION_TYPE_SELL && (newSL<sl || sl==0)))
            trade.PositionModify(ticket,newSL,tp);
      }
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(123456);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   handleMA=iMA(_Symbol,PERIOD_M5,20,0,MODE_SMA,PRICE_CLOSE);
   handleRSI=iRSI(_Symbol,PERIOD_M5,14,PRICE_CLOSE);
   handleADX=iADX(_Symbol,PERIOD_M5,14);
   handleATR=iATR(_Symbol,PERIOD_M5,14);
   handleMACD=iMACD(_Symbol,PERIOD_M5,12,26,9,PRICE_CLOSE);

   if(handleMA==INVALID_HANDLE || handleRSI==INVALID_HANDLE || handleADX==INVALID_HANDLE || handleATR==INVALID_HANDLE || handleMACD==INVALID_HANDLE)
      return INIT_FAILED;

   startingBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   equityPeak=AccountInfoDouble(ACCOUNT_EQUITY);
   riskPercentLive=RiskPercent;
   slPointsLive=SL_Points;
   tpPointsLive=TP_Points;
   maxDailyLossLive=MaxDailyLoss;
   maxDrawdownLive=MaxDrawdown;
   remoteTradingEnabled=EA_Active;
   adaptiveThreshold=MathMax(AdaptiveThresholdMin,MathMin(AdaptiveThresholdMax,(double)AIScoreThreshold));
   LoadLearningState();
   EventSetTimer(MathMax(1,RemotePollSeconds));
   diagnosticBlocker="INITIALIZED - WAITING FOR MARKET";
   UpdateChartStatus();
   Print("Leona Pro X initialized. DeviceId set=",DeviceId!=""," Token set=",EaToken!=""," Timer=",MathMax(1,RemotePollSeconds),"s");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   EventKillTimer();
   IndicatorRelease(handleMA); IndicatorRelease(handleRSI); IndicatorRelease(handleADX);
   IndicatorRelease(handleATR); IndicatorRelease(handleMACD);
}

void OnTimer()
{
   SendHeartbeat();
   ProcessRemoteCommands();
   UpdateChartStatus();
}

void OnTick()
{
   ManagePositions();

   diagnosticScore=0;
   diagnosticADX=0.0;

   if(!EA_Active || !remoteTradingEnabled || isTradingPaused)
   {
      diagnosticBlocker="ROBOT PAUSED";
      UpdateChartStatus();
      return;
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      diagnosticBlocker="MT5 AUTO TRADING DISABLED";
      if(DebugTrading) Print("Leona DEBUG: automated trading permission is disabled in terminal, EA settings, or account.");
      UpdateChartStatus();
      return;
   }


   if(!BrokerAndSymbolOK())
   {
      diagnosticBlocker="BROKER/SYMBOL FILTER";
      if(DebugTrading) Print("Leona DEBUG: blocked by broker/symbol filter. Company=",AccountInfoString(ACCOUNT_COMPANY)," Symbol=",_Symbol);
      UpdateChartStatus();
      return;
   }

   if(!SpreadOK())
   {
      diagnosticBlocker="SPREAD TOO HIGH";
      if(DebugTrading)
         PrintFormat("Leona DEBUG: blocked by smart spread. spread=%.1f points ATR=%.5f",
                     diagnosticSpreadPoints,diagnosticATR);
      UpdateChartStatus();
      return;
   }

   if(!TimeOK())
   {
      diagnosticBlocker="OUTSIDE TRADING HOURS";
      if(DebugTrading) Print("Leona DEBUG: blocked by trading hours.");
      UpdateChartStatus();
      return;
   }

   if(!RiskManagementOK())
   {
      diagnosticBlocker="RISK/MARGIN PROTECTION";
      if(DebugTrading) Print("Leona DEBUG: blocked by risk management.");
      UpdateChartStatus();
      return;
   }

   if(!VolatilityOK())
   {
      diagnosticBlocker="VOLATILITY FILTER";
      if(DebugTrading)
      {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double atrPct=(bid>0 && diagnosticATR>0) ? (diagnosticATR/bid)*100.0 : 0.0;
         PrintFormat("Leona DEBUG: blocked by volatility. ATR=%.5f ATR%%=%.4f allowed=%.4f-%.4f%%",
                     diagnosticATR,atrPct,MinATRPricePercent,MaxATRPricePercent);
      }
      UpdateChartStatus();
      return;
   }

   if(TimeCurrent()-lastTradeTime<CooldownSeconds)
   {
      diagnosticBlocker="COOLDOWN";
      UpdateChartStatus();
      return;
   }

   double adx=BufferValue(handleADX,0,0);
   diagnosticADX=(adx==EMPTY_VALUE ? 0.0 : adx);
   // ADX is retained as an informational/AI input, but is no longer a hard
   // entry blocker for the aggressive scalping build.

   int score=AIScore();
   diagnosticScore=score;
   int threshold=(int)MathRound(EnableAdaptiveLearning ? adaptiveThreshold : (double)AIScoreThreshold);
   if(AggressiveScalping) threshold=MathMax(2,threshold-2);

   bool buyConfirm=MultiTimeframeConfirm(true);
   bool sellConfirm=MultiTimeframeConfirm(false);

   if(score>=threshold && buyConfirm)
   {
      diagnosticBlocker="BUY SIGNAL - SENDING";
      if(DebugTrading) Print("Leona DEBUG: BUY signal score=",score," threshold=",threshold," ADX=",adx);
      OpenBuy();
   }
   else if(score<=-threshold && sellConfirm)
   {
      diagnosticBlocker="SELL SIGNAL - SENDING";
      if(DebugTrading) Print("Leona DEBUG: SELL signal score=",score," threshold=",threshold," ADX=",adx);
      OpenSell();
   }
   else if(score>=threshold || score<=-threshold)
   {
      diagnosticBlocker="AI SCORE OK - MTF CONFIRMATION";
   }
   else
   {
      diagnosticBlocker="WAITING FOR AI SCORE";
   }

   UpdateChartStatus();
}
