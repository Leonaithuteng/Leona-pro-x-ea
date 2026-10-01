#property strict
#property version "1.0"
#property description "Leona Pro X EA - M5 AI Scalper with remote control"

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

input group "Trading Parameters"
input double LotSize = 0.01;
input double RiskPercent = 1.0;
input int MaxSpread = 30;
input int SL_Points = 150;
input int TP_Points = 250;
input bool EA_Active = true;

input group "Filters"
input int MinVolatility = 60;
input int MaxVolatility = 300;
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
input int MaxOpenPositions = 100;
input double MinimumAccountBalance = 2.0;
input int MinimumProfitScalePositions = 5;
input double ProfitRequiredToScale = 0.01;
input double MinimumMarginLevelToAdd = 300.0;
input double MinMarginLevel = 300.0;
input double MaxLotPercentOfBalance = 5.0;
input double BalancePerOpenTrade = 100.0;
input int MaxSlippagePoints = 20;
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

string Url(string path) { return ApiBaseUrl + path; }

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
   if(ok) Print("Leona heartbeat accepted by API");
   else Print("Leona heartbeat failed");
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
   long spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   return spread<=MaxSpread;
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
   ResetDaily();
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(startingBalance<=0) startingBalance=AccountInfoDouble(ACCOUNT_BALANCE);

   double dailyPL=(equity-startingBalance)/startingBalance*100.0;
   if(dailyPL<=-maxDailyLossLive) return false;

   if(equity>equityPeak) equityPeak=equity;
   if(equityPeak>0 && (equityPeak-equity)/equityPeak*100.0>=maxDrawdownLive) return false;

   if(consecutiveLosses>=MaxConsecutiveLosses) return false;
   if(UseEquityProtection && equity<AccountInfoDouble(ACCOUNT_BALANCE)*0.95) return false;
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel>0 && marginLevel<MinMarginLevel) return false;
   int openCount=0;
   double basketProfit=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC)==123456)
      {
         openCount++;
         basketProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance<MinimumAccountBalance) return false;
   bool scalingProfit=basketProfit>=ProfitRequiredToScale;
   int profitScaledLimit=scalingProfit ? MathMax(MinimumProfitScalePositions,MaxOpenPositions) : MathMin(MaxOpenPositions,MathMax(1,MinimumProfitScalePositions));
   if(openCount>=profitScaledLimit) return false;

   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(currentHour!=t.hour) { currentHour=t.hour; tradesThisHour=0; }
   return tradesThisHour<MaxTradesPerHour;
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
   if(atr==EMPTY_VALUE) return false;
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
   return confirmed>=2;
}


bool MarginAllowsNewTrade(ENUM_ORDER_TYPE orderType,double volume,double price)
{
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin<=0) return false;
   double required=0.0;
   if(!OrderCalcMargin(orderType,_Symbol,volume,price,required) || required<=0) return false;
   if(required>=freeMargin) return false;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double currentMargin=AccountInfoDouble(ACCOUNT_MARGIN);
   double futureMargin=currentMargin+required;
   if(futureMargin<=0) return true;
   double futureLevel=equity/futureMargin*100.0;
   double brokerStopOut=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   long stopMode=AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   if(stopMode==ACCOUNT_STOPOUT_MODE_PERCENT && brokerStopOut>0)
      return futureLevel>MathMax(MinimumMarginLevelToAdd,brokerStopOut+50.0);
   return futureLevel>=MinimumMarginLevelToAdd;
}

double CalculateLotSize()
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
      double maxLotByBalance=AccountInfoDouble(ACCOUNT_BALANCE)*MaxLotPercentOfBalance/100.0;
      if(maxLotByBalance>0) lot=MathMin(lot,maxLotByBalance);
      lot=MathMax(minLot,lot);
      lot=MathFloor(lot/step)*step;
      return NormalizeDouble(lot,2);
   }
   if(riskPercentLive<=0) return MathMax(LotSize,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney=balance*riskPercentLive/100.0;
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0 || tickSize<=0 || slPointsLive<=0) return LotSize;
   double valuePerPoint=tickValue*_Point/tickSize;
   double lot=riskMoney/(slPointsLive*valuePerPoint);
   lot=MathMax(minLot,MathMin(maxLot,lot));
   double maxLotByBalance=AccountInfoDouble(ACCOUNT_BALANCE)*MaxLotPercentOfBalance/100.0;
   if(maxLotByBalance>0) lot=MathMin(lot,maxLotByBalance);
   lot=MathMax(minLot,lot);
   if(step>0) lot=MathFloor(lot/step)*step;
   return NormalizeDouble(lot,2);
}

void OpenBuy()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double lot=CalculateLotSize();
   if(!MarginAllowsNewTrade(ORDER_TYPE_BUY,lot,ask)) { if(DebugTrading) Print("Leona DEBUG: BUY blocked by available margin."); return; }
   double sl=NormalizeDouble(ask-slPointsLive*_Point,_Digits);
   double tp=NormalizeDouble(ask+tpPointsLive*_Point,_Digits);
   if(trade.Buy(lot,_Symbol,ask,sl,tp,"Leona Pro X BUY"))
   {
      lastTradeTime=TimeCurrent(); tradesThisHour++;
      Print("Leona BUY opened. lot=",lot," SL=",sl," TP=",tp);
   }
   else
      Print("Leona BUY rejected. retcode=",trade.ResultRetcode()," description=",trade.ResultRetcodeDescription()," lot=",lot," spread=",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD));
}

void OpenSell()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double lot=CalculateLotSize();
   if(!MarginAllowsNewTrade(ORDER_TYPE_SELL,lot,bid)) { if(DebugTrading) Print("Leona DEBUG: SELL blocked by available margin."); return; }
   double sl=NormalizeDouble(bid+slPointsLive*_Point,_Digits);
   double tp=NormalizeDouble(bid-tpPointsLive*_Point,_Digits);
   if(trade.Sell(lot,_Symbol,bid,sl,tp,"Leona Pro X SELL"))
   {
      lastTradeTime=TimeCurrent(); tradesThisHour++;
      Print("Leona SELL opened. lot=",lot," SL=",sl," TP=",tp);
   }
   else
      Print("Leona SELL rejected. retcode=",trade.ResultRetcode()," description=",trade.ResultRetcodeDescription()," lot=",lot," spread=",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD));
}

void ManagePositions()
{
   if(!PositionSelect(_Symbol)) return;
   if((long)PositionGetInteger(POSITION_MAGIC)!=123456) return;

   long type=PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double price=type==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double profitPoints=(type==POSITION_TYPE_BUY?(price-open):(open-price))/_Point;

   if(UseBreakEven && profitPoints>=BreakEvenTrigger)
   {
      double newSL=NormalizeDouble(open,_Digits);
      if((type==POSITION_TYPE_BUY && (sl<newSL || sl==0)) || (type==POSITION_TYPE_SELL && (sl>newSL || sl==0)))
         trade.PositionModify(_Symbol,newSL,tp);
   }

   if(UseTrailingStop && profitPoints>=TrailingStart)
   {
      double newSL=type==POSITION_TYPE_BUY?price-TrailingStep*_Point:price+TrailingStep*_Point;
      newSL=NormalizeDouble(newSL,_Digits);
      if((type==POSITION_TYPE_BUY && newSL>sl) || (type==POSITION_TYPE_SELL && (newSL<sl || sl==0)))
         trade.PositionModify(_Symbol,newSL,tp);
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
   EventSetTimer(MathMax(1,RemotePollSeconds));
   Print("Leona Pro X initialized. DeviceId set=",DeviceId!=""," Token set=",EaToken!=""," Timer=",MathMax(1,RemotePollSeconds),"s");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(handleMA); IndicatorRelease(handleRSI); IndicatorRelease(handleADX);
   IndicatorRelease(handleATR); IndicatorRelease(handleMACD);
}

void OnTimer()
{
   SendHeartbeat();
   ProcessRemoteCommands();
}

void OnTick()
{
   ManagePositions();
   if(!EA_Active || !remoteTradingEnabled || isTradingPaused) return;
   if(!BrokerAndSymbolOK()) { if(DebugTrading) Print("Leona DEBUG: blocked by broker/symbol filter. Company=",AccountInfoString(ACCOUNT_COMPANY)," Symbol=",_Symbol); return; }
   long spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   if(spread>MaxSpread) { if(DebugTrading) Print("Leona DEBUG: blocked by spread. spread=",spread," max=",MaxSpread); return; }
   if(!TimeOK()) { if(DebugTrading) Print("Leona DEBUG: blocked by trading hours."); return; }
   if(!RiskManagementOK()) { if(DebugTrading) Print("Leona DEBUG: blocked by risk management."); return; }
   if(!VolatilityOK()) { if(DebugTrading) Print("Leona DEBUG: blocked by volatility. ATR points outside ",MinVolatility,"-",MaxVolatility); return; }
   if(TimeCurrent()-lastTradeTime<CooldownSeconds) return;

   double adx=BufferValue(handleADX,0,0);
   if(adx==EMPTY_VALUE || adx<MinTrendStrength*10.0) { if(DebugTrading) Print("Leona DEBUG: blocked by ADX. ADX=",adx," minimum=",MinTrendStrength*10.0); return; }

   int score=AIScore();
   int threshold=(int)MathRound(EnableAdaptiveLearning ? adaptiveThreshold : (double)AIScoreThreshold);
   bool buyConfirm=MultiTimeframeConfirm(true);
   bool sellConfirm=MultiTimeframeConfirm(false);
   if(DebugTrading && (score>=threshold || score<=-threshold)) Print("Leona DEBUG: score=",score," threshold=",threshold," ADX=",adx," buyConfirm=",buyConfirm," sellConfirm=",sellConfirm);

   if(score>=threshold && buyConfirm) OpenBuy();
   else if(score<=-threshold && sellConfirm) OpenSell();
}
