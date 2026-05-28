//+------------------------------------------------------------------+
//| Core/Logger.mqh                                                  |
//+------------------------------------------------------------------+
#ifndef __LOGGER_MQH__
#define __LOGGER_MQH__

#include "Config.mqh"
#include "State.mqh"

extern EAState g_state;

class CLogger
{
private:
   string m_logPath;
   string m_label;
   ulong m_magic;
   int m_fileTrade;
   int m_fileSignal;
   int m_fileError;
   bool m_initialized;
   string m_panelName;
   string m_objects[];
   int m_objCount;

   string TimeStampMicro() const
   {
      datetime t = TimeCurrent();
      long msec = GetTickCount() % 1000;
      return TimeToString(t, TIME_DATE|TIME_SECONDS) + "." + IntegerToString(msec, 3, '0');
   }

   bool EnsureDirectory(string path)
   {
      string dirs[];
      int count = StringSplit(path, '\\', dirs);
      string current = "";
      for(int i = 0; i < count; i++)
      {
         if(i > 0) current += "\\";
         current += dirs[i];
         if(current == "") continue;
         if(!FolderCreate(current, 0))
         {
            int err = GetLastError();
            if(err != 183 && err != 0) return false;  // 183 = already exists
         }
      }
      return true;
   }

   int OpenLogFile(string filename, string header)
   {
      string filepath = m_logPath + filename;
      bool exists = FileIsExist(filepath);
      int handle = FileOpen(filepath, FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI, ',');
      if(handle == INVALID_HANDLE) return INVALID_HANDLE;
      FileSeek(handle, 0, SEEK_END);
      if(!exists || FileTell(handle) == 0)
      {
         FileWrite(handle, header);
         FileFlush(handle);
      }
      return handle;
   }

   void WriteCSV(int handle, string data)
   {
      if(handle == INVALID_HANDLE) return;
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, data + "\r\n");
      FileFlush(handle);
   }

   void CreatePanel()
   {
      m_panelName = "MTF_Dashboard_" + IntegerToString((int)m_magic);
      ObjectCreate(0, m_panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, m_panelName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, m_panelName, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, m_panelName, OBJPROP_XSIZE, 320);
      ObjectSetInteger(0, m_panelName, OBJPROP_YSIZE, 280);
      ObjectSetInteger(0, m_panelName, OBJPROP_BGCOLOR, C'20,20,30');
      ObjectSetInteger(0, m_panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, m_panelName, OBJPROP_COLOR, C'60,60,80');

      CreateLabel("Title", 15, 35, "Universal MTF EA v2.0", 12, clrWhite, true);
      CreateLabel("Section1", 15, 55, "=== MARKET STATE ===", 10, C'150,150,170');
      CreateLabel("BiasLabel", 15, 72, "HTF Bias:", 9, clrSilver);
      CreateLabel("BiasValue", 120, 72, "NEUTRAL", 9, clrYellow);
      CreateLabel("RegimeLabel", 15, 88, "Regime:", 9, clrSilver);
      CreateLabel("RegimeValue", 120, 88, "RANGE", 9, clrYellow);
      CreateLabel("MLLabel", 15, 104, "ML Confidence:", 9, clrSilver);
      CreateLabel("MLValue", 120, 104, "0.00", 9, clrYellow);
      CreateLabel("Section2", 15, 122, "=== PERFORMANCE ===", 10, C'150,150,170');
      CreateLabel("DailyLabel", 15, 139, "Daily PnL:", 9, clrSilver);
      CreateLabel("DailyValue", 120, 139, "0.00", 9, clrWhite);
      CreateLabel("WeeklyLabel", 15, 155, "Weekly PnL:", 9, clrSilver);
      CreateLabel("WeeklyValue", 120, 155, "0.00", 9, clrWhite);
      CreateLabel("TradesLabel", 15, 171, "Trades Today:", 9, clrSilver);
      CreateLabel("TradesValue", 120, 171, "0", 9, clrWhite);
      CreateLabel("Section3", 15, 189, "=== RISK STATUS ===", 10, C'150,150,170');
      CreateLabel("OpenPosLabel", 15, 206, "Open Positions:", 9, clrSilver);
      CreateLabel("OpenPosValue", 120, 206, "0", 9, clrWhite);
      CreateLabel("RiskLabel", 15, 222, "Total Risk:", 9, clrSilver);
      CreateLabel("RiskValue", 120, 222, "0.00%", 9, clrWhite);
      CreateLabel("StatusLabel", 15, 238, "Status:", 9, clrSilver);
      CreateLabel("StatusValue", 120, 238, "ACTIVE", 9, clrLime);
      CreateLabel("Section4", 15, 256, "=== NEWS ===", 10, C'150,150,170');
      CreateLabel("NewsLabel", 15, 273, "Next Event:", 9, clrSilver);
      CreateLabel("NewsValue", 120, 273, "None", 9, clrWhite);
      m_initialized = true;
   }

   void CreateLabel(string name, int x, int y, string text, int fontSize, color clr, bool bold = false)
   {
      string fullName = m_panelName + "_" + name;
      ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, fullName, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
      ObjectSetString(0, fullName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
      int idx = ArraySize(m_objects);
      ArrayResize(m_objects, idx + 1);
      m_objects[idx] = fullName;
   }

   void UpdateLabel(string name, string text, color clr)
   {
      string fullName = m_panelName + "_" + name;
      if(ObjectFind(0, fullName) >= 0)
      {
         ObjectSetString(0, fullName, OBJPROP_TEXT, text);
         ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
      }
   }

public:
   CLogger() : m_fileTrade(INVALID_HANDLE), m_fileSignal(INVALID_HANDLE),
               m_fileError(INVALID_HANDLE), m_initialized(false), m_objCount(0) {}

   bool Init(string basePath, string label, ulong magic)
   {
      m_label = label; m_magic = magic; m_logPath = basePath;
      if(StringLen(m_logPath) > 0 && StringSubstr(m_logPath, StringLen(m_logPath)-1) != "\\")
         m_logPath += "\\";
      m_logPath += label + "_" + IntegerToString((int)magic) + "\\";
      if(!EnsureDirectory(m_logPath)) m_logPath = "";

      string tradeHeader = "Timestamp,Symbol,Direction,EntryPrice,SL,TP1,TP2,Lot,RiskPercent,ATR_Value,Regime,HTF_Bias,Pattern,ExitPrice,ExitReason,PnL_USD,PnL_Percent,Duration_Minutes";
      m_fileTrade = OpenLogFile("TradeJournal.csv", tradeHeader);
      string signalHeader = "Timestamp,Symbol,HTF_Bias,MTF_Regime,LTF_Pattern,IsValid,RejectionReason";
      m_fileSignal = OpenLogFile("SignalLog.csv", signalHeader);
      string errorHeader = "Timestamp,Function,ErrorCode,ErrorMessage,RetryCount,Resolution";
      m_fileError = OpenLogFile("ErrorLog.csv", errorHeader);

      m_initialized = (m_fileTrade != INVALID_HANDLE && m_fileSignal != INVALID_HANDLE && m_fileError != INVALID_HANDLE);
      if(m_initialized)
      {
         Print("[Logger] Audit trail active. Path: ", m_logPath);
         CreatePanel();
      }
      return m_initialized;
   }

   void Shutdown()
   {
      if(m_fileTrade != INVALID_HANDLE) { FileClose(m_fileTrade); m_fileTrade = INVALID_HANDLE; }
      if(m_fileSignal != INVALID_HANDLE) { FileClose(m_fileSignal); m_fileSignal = INVALID_HANDLE; }
      if(m_fileError != INVALID_HANDLE) { FileClose(m_fileError); m_fileError = INVALID_HANDLE; }
      for(int i = 0; i < ArraySize(m_objects); i++) ObjectDelete(0, m_objects[i]);
      ObjectDelete(0, m_panelName);
      Print("[Logger] Log files closed and dashboard cleared.");
   }

   void LogEvent(string category, string message)
   {
      if(InpDebugMode) Print("[", category, "] ", message);
   }

   void LogSignal(const SignalData &signal, const EAState &state)
   {
      if(m_fileSignal == INVALID_HANDLE) return;
      string line = StringFormat("%s,%s,%s,%s,%s,%s,%s",
                     TimeStampMicro(), _Symbol, EnumToString(state.currentBias),
                     EnumToString(state.currentRegime), signal.patternName,
                     signal.isValid ? "YES" : "NO", signal.rejectionReason);
      WriteCSV(m_fileSignal, line);
   }

   void LogError(string function, int code, string message, int retryCount)
   {
      if(m_fileError == INVALID_HANDLE) return;
      string line = StringFormat("%s,%s,%d,%s,%d,%s",
                     TimeStampMicro(), function, code, message, retryCount, "PENDING");
      WriteCSV(m_fileError, line);
   }

   void LogTradeOpen(const SignalData &signal, const TradeParams &params, ulong ticket)
   {
      if(m_fileTrade == INVALID_HANDLE) return;
      string dir = signal.isBuy ? "BUY" : "SELL";
      string line = StringFormat("%s,%s,%s,%.5f,%.5f,%.5f,%.5f,%.2f,%.2f,%.5f,%s,%s,%s,%s,%.2f,%.2f,%d",
                     TimeStampMicro(), _Symbol, dir, signal.entryPrice, signal.slPrice,
                     signal.tp1Price, signal.tp2Price, params.lotSize, params.riskPercent,
                     signal.atrValue, EnumToString(g_state.currentRegime),
                     EnumToString(g_state.currentBias), signal.patternName, "", "", 0, 0, 0);
      WriteCSV(m_fileTrade, line);
   }

   void LogTradeClose(const EAState &state)
   {
      if(m_fileTrade == INVALID_HANDLE) return;
      string line = StringFormat("%s,%s,,%s,,,,,,,,,%.2f,%s,%.2f,%.0f",
                     TimeStampMicro(), _Symbol, EnumToString(state.lastExitReason),
                     state.lastTradePnL, EnumToString(state.lastExitReason),
                     (state.lastTradePnL / AccountInfoDouble(ACCOUNT_EQUITY)) * 100.0,
                     (TimeCurrent() - state.lastTradeClose) / 60.0);
      WriteCSV(m_fileTrade, line);
   }

   void UpdateDashboard(const EAState &state)
   {
      color biasClr = clrYellow;
      string biasText = EnumToString(state.currentBias);
      if(state.currentBias == BIAS_BULL) biasClr = clrLime;
      else if(state.currentBias == BIAS_BEAR) biasClr = clrRed;
      UpdateLabel("BiasValue", biasText, biasClr);

      color regimeClr = clrYellow;
      string regimeText = EnumToString(state.currentRegime);
      if(state.currentRegime == REGIME_TREND) regimeClr = clrLime;
      else if(state.currentRegime == REGIME_CHOP) regimeClr = clrRed;
      UpdateLabel("RegimeValue", regimeText, regimeClr);

      color dailyClr = state.dailyPnL >= 0 ? clrLime : clrRed;
      UpdateLabel("DailyValue", StringFormat("%.2f", state.dailyPnL), dailyClr);

      color weeklyClr = state.weeklyPnL >= 0 ? clrLime : clrRed;
      UpdateLabel("WeeklyValue", StringFormat("%.2f", state.weeklyPnL), weeklyClr);

      UpdateLabel("TradesValue", IntegerToString(state.totalTradesToday), clrWhite);
      UpdateLabel("OpenPosValue", IntegerToString(state.openPositions), state.openPositions > 0 ? clrLime : clrWhite);

      color riskClr = state.totalOpenRisk > InpMaxTotalRisk * 0.8 ? clrRed : 
                      state.totalOpenRisk > InpMaxTotalRisk * 0.5 ? clrYellow : clrWhite;
      UpdateLabel("RiskValue", StringFormat("%.2f%%", state.totalOpenRisk), riskClr);

      string status = "ACTIVE";
      color statusClr = clrLime;
      if(state.dailyLimitHit) { status = "DAILY LIMIT"; statusClr = clrRed; }
      else if(state.weeklyLimitHit) { status = "WEEKLY LIMIT"; statusClr = clrRed; }
      else if(state.consecLossHalted) { status = "CONSEC LOSS"; statusClr = clrRed; }
      else if(state.circuitBreakerUntil > TimeCurrent()) { status = "HALTED"; statusClr = clrRed; }
      UpdateLabel("StatusValue", status, statusClr);

      string dash = StringFormat(
         "\n=== Universal_MTF_EA v2.0 | %s ===\n"
         "Bias: %s | Regime: %s | Volume: %s\n"
         "Daily PnL: %.2f | Weekly PnL: %.2f\n"
         "Open Pos: %d | Total Risk: %.2f%%\n"
         "Last Trade: %.2f (%s)\n"
         "Status: %s\n"
         "====================",
         _Symbol, EnumToString(state.currentBias), EnumToString(state.currentRegime),
         state.volumeConfirmed ? "OK" : "LOW", state.dailyPnL, state.weeklyPnL,
         state.openPositions, state.totalOpenRisk, state.lastTradePnL,
         EnumToString(state.lastExitReason), status);
      Comment(dash);
   }
};

#endif // __LOGGER_MQH__
