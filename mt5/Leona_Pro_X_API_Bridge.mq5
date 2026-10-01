#property strict
#property version   "1.0"
#property description "Leona Pro X EA - MT5 API Bridge"

#include <Trade/Trade.mqh>

input string ApiBaseUrl = "https://leona-pro-x-api.onrender.com";
input string DeviceId = "";
input string EaToken = "";
input int PollSeconds = 5;
input bool EnableRemoteCommands = true;

CTrade Trade;

string Url(string path)
{
   return ApiBaseUrl + path;
}

string JsonNumber(double value)
{
   return DoubleToString(value, 2);
}

bool HttpRequest(string method, string url, string body, string &response, string token = "")
{
   char data[];
   char result[];
   string headers = "Content-Type: application/json\r\n";
   if(token != "") headers += "X-EA-Token: " + token + "\r\n";
   string result_headers;

   if(body != "")
   {
      StringToCharArray(body, data, 0, StringLen(body), CP_UTF8);
   }

   ResetLastError();
   int code = WebRequest(method, url, headers, 10000, data, result, result_headers);
   if(code < 0)
   {
      Print("Leona Pro X WebRequest failed. Error: ", GetLastError());
      return false;
   }

   response = CharArrayToString(result, 0, -1, CP_UTF8);
   return code >= 200 && code < 300;
}

bool SendHeartbeat()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit  = AccountInfoDouble(ACCOUNT_PROFIT);
   double drawdown = balance > 0.0 ? (balance - equity) / balance * 100.0 : 0.0;

   string body = StringFormat(
      "{\"balance\":%s,\"equity\":%s,\"profit\":%s,\"drawdown\":%s,\"ea_active\":true}",
      JsonNumber(balance),
      JsonNumber(equity),
      JsonNumber(profit),
      JsonNumber(drawdown)
   );

   string response;
   return HttpRequest(
      "POST",
      Url("/api/v1/ea/heartbeat"),
      body,
      response,
      EaToken
   );
}

string JsonStringValue(string json, string key)
{
   string needle = "\"" + key + "\":\"";
   int start = StringFind(json, needle);
   if(start < 0) return "";

   start += StringLen(needle);
   int end = StringFind(json, "\"", start);
   if(end < 0) return "";

   return StringSubstr(json, start, end - start);
}

void ReportCommand(string commandId, string status, string message)
{
   string safeMessage = message;
   StringReplace(safeMessage, "\\", "\\\\");
   StringReplace(safeMessage, "\"", "\\\"");

   string body = StringFormat(
      "{\"command_id\":\"%s\",\"status\":\"%s\",\"message\":\"%s\"}",
      commandId,
      status,
      safeMessage
   );

   string response;
   HttpRequest(
      "POST",
      Url("/api/v1/commands/result"),
      body,
      response,
      EaToken
   );
}

void ProcessCommands()
{
   if(!EnableRemoteCommands || DeviceId == "" || EaToken == "")
      return;

   string response;
   string headers = "Content-Type: application/json\r\nX-EA-Token: " + EaToken + "\r\n";
   char data[];
   char result[];
   string resultHeaders;

   ResetLastError();
   int code = WebRequest(
      "GET",
      Url("/api/v1/devices/" + DeviceId + "/commands"),
      headers,
      10000,
      data,
      result,
      resultHeaders
   );

   if(code < 200 || code >= 300)
      return;

   response = CharArrayToString(result, 0, -1, CP_UTF8);

   int pos = 0;
   while(true)
   {
      int idPos = StringFind(response, "\"command_id\":\"", pos);
      if(idPos < 0) break;

      int idStart = idPos + StringLen("\"command_id\":\"");
      int idEnd = StringFind(response, "\"", idStart);
      if(idEnd < 0) break;

      string commandId = StringSubstr(response, idStart, idEnd - idStart);

      int cmdPos = StringFind(response, "\"command\":\"", idEnd);
      if(cmdPos < 0) break;

      int cmdStart = cmdPos + StringLen("\"command\":\"");
      int cmdEnd = StringFind(response, "\"", cmdStart);
      if(cmdEnd < 0) break;

      string command = StringSubstr(response, cmdStart, cmdEnd - cmdStart);
      bool success = true;
      string message = "Command executed";

      if(command == "START_ROBOT")
      {
         GlobalVariableSet("LEONA_EA_ACTIVE", 1.0);
      }
      else if(command == "STOP_ROBOT")
      {
         GlobalVariableSet("LEONA_EA_ACTIVE", 0.0);
      }
      else if(command == "CLOSE_ALL")
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
               if(!Trade.PositionClose(ticket))
               {
                  success = false;
                  message = "Failed to close one or more positions";
               }
            }
         }
      }
      else if(command == "UPDATE_RISK")
      {
         message = "Risk update received; connect this command to strategy inputs before live use";
      }
      else
      {
         success = false;
         message = "Unsupported command";
      }

      ReportCommand(
         commandId,
         success ? "COMPLETED" : "FAILED",
         message
      );

      pos = cmdEnd + 1;
   }
}

int OnInit()
{
   if(ApiBaseUrl == "")
   {
      Print("Leona Pro X: ApiBaseUrl is empty.");
      return INIT_PARAMETERS_INCORRECT;
   }

   EventSetTimer(MathMax(1, PollSeconds));
   Print("Leona Pro X API bridge initialized.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   if(EaToken != "")
      SendHeartbeat();

   ProcessCommands();
}
