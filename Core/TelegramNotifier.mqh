//+------------------------------------------------------------------+
//| Core/TelegramNotifier.mqh                                        |
//+------------------------------------------------------------------+
#ifndef __TELEGRAM_NOTIFIER_MQH__
#define __TELEGRAM_NOTIFIER_MQH__

#include "Config.mqh"
#include "State.mqh"

class CTelegramNotifier
{
private:
   string m_botToken;
   string m_chatId;
   string m_discordWebhook;
   bool m_useTelegram;
   bool m_useDiscord;
   bool m_initialized;
   int m_timeoutMs;

public:
   CTelegramNotifier() : m_useTelegram(false), m_useDiscord(false), 
                           m_initialized(false), m_timeoutMs(5000) {}

   bool Init(string botToken, string chatId, string discordWebhook = "")
   {
      m_botToken = botToken;
      m_chatId = chatId;
      m_discordWebhook = discordWebhook;
      m_useTelegram = (StringLen(botToken) > 0 && StringLen(chatId) > 0);
      m_useDiscord = (StringLen(discordWebhook) > 0);
      if(!m_useTelegram && !m_useDiscord)
      {
         Print("[TelegramNotifier] No notification channels configured.");
         return true;
      }
      m_initialized = true;
      Print("[TelegramNotifier] Initialized | Telegram: ", m_useTelegram ? "ON" : "OFF",
            " | Discord: ", m_useDiscord ? "ON" : "OFF");
      return true;
   }

   void SendTradeOpen(const SignalData &signal, const TradeParams &params, ulong ticket)
   {
      if(!m_initialized) return;
      string emoji = signal.isBuy ? "BUY" : "SELL";
      string message = StringFormat(
         "*NEW TRADE OPENED*\n\nSymbol: %s\nDirection: %s\nEntry: %.5f\nSL: %.5f\nTP1: %.5f\nTP2: %.5f\nLots: %.2f\nRisk: %.2f%%\nTicket: %llu",
         _Symbol, emoji, signal.entryPrice, signal.slPrice, signal.tp1Price, signal.tp2Price,
         params.lotSize, params.riskPercent, ticket);
      SendMessage(message);
   }

   void SendTradeClose(const EAState &state)
   {
      if(!m_initialized) return;
      string pnlStr = state.lastTradePnL >= 0 ? StringFormat("+%.2f", state.lastTradePnL) : StringFormat("%.2f", state.lastTradePnL);
      string message = StringFormat(
         "*TRADE CLOSED*\n\nSymbol: %s\nPnL: %s USD\nReason: %s",
         _Symbol, pnlStr, EnumToString(state.lastExitReason));
      SendMessage(message);
   }

   void SendCircuitBreaker(const EAState &state)
   {
      if(!m_initialized) return;
      string message = StringFormat(
         "*CIRCUIT BREAKER ACTIVATED*\n\nSymbol: %s\nReason: %s\nDaily PnL: %.2f\nWeekly PnL: %.2f\nResumes: %s",
         _Symbol, state.circuitBreakerReason, state.dailyPnL, state.weeklyPnL,
         TimeToString(state.circuitBreakerUntil, TIME_DATE|TIME_SECONDS));
      SendMessage(message);
   }

   void SendRegimeChange(ENUM_REGIME oldRegime, ENUM_REGIME newRegime)
   {
      if(!m_initialized) return;
      string message = StringFormat(
         "*REGIME CHANGE*\n\nSymbol: %s\nFrom: %s\nTo: %s",
         _Symbol, EnumToString(oldRegime), EnumToString(newRegime));
      SendMessage(message);
   }

   void SendDailySummary(const EAState &state)
   {
      if(!m_initialized) return;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      string message = StringFormat(
         "*DAILY SUMMARY*\n\nSymbol: %s\nDaily PnL: %.2f\nWeekly PnL: %.2f\nTrades: %d\nEquity: %.2f\nStatus: %s",
         _Symbol, state.dailyPnL, state.weeklyPnL, state.totalTradesToday, equity,
         state.circuitBreakerUntil > TimeCurrent() ? "HALTED" : "ACTIVE");
      SendMessage(message);
   }

   void SendMessage(string message)
   {
      if(m_useTelegram) SendTelegram(message);
      if(m_useDiscord) SendDiscord(message);
   }

private:
   void SendTelegram(string message)
   {
      string url = "https://api.telegram.org/bot" + m_botToken + "/sendMessage";
      string headers;
      string data = "chat_id=" + m_chatId + "&text=" + message + "&parse_mode=Markdown";
      char dataChar[];
      StringToCharArray(data, dataChar);
      char result[];
      string resultHeaders;
      int res = WebRequest("POST", url, headers, 5000, dataChar, result, resultHeaders);
      if(res != 200) Print("[TelegramNotifier] Telegram send failed. HTTP: ", res);
   }

   void SendDiscord(string message)
   {
      string headers;
      string jsonPayload = "{\"content\":\"" + message + "\"}";
      char dataChar[];
      StringToCharArray(jsonPayload, dataChar);
      char result[];
      string resultHeaders;
      int res = WebRequest("POST", m_discordWebhook, headers, 5000, dataChar, result, resultHeaders);
      if(res != 200 && res != 204) Print("[TelegramNotifier] Discord send failed. HTTP: ", res);
   }
};

#endif // __TELEGRAM_NOTIFIER_MQH__
