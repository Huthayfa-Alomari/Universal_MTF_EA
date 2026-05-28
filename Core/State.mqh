//+------------------------------------------------------------------+
//| Core/State.mqh                                                   |
//+------------------------------------------------------------------+
#ifndef __STATE_MQH__
#define __STATE_MQH__

#include "Config.mqh"

struct EAState
{
   double dailyPnL;
   double weeklyPnL;
   double totalOpenRisk;
   int consecutiveLosses;
   int totalTradesToday;
   int totalTradesWeek;
   bool dailyLimitHit;
   bool weeklyLimitHit;
   bool consecLossHalted;
   bool spreadHalted;
   datetime circuitBreakerUntil;
   string circuitBreakerReason;
   ENUM_BIAS currentBias;
   ENUM_REGIME currentRegime;
   ENUM_PATTERN lastPattern;
   bool volumeConfirmed;
   bool isBarClosedHTF;
   bool isBarClosedMTF;
   bool isBarClosedLTF;
   datetime lastHTFBarTime;
   datetime lastMTFBarTime;
   datetime lastLTFBarTime;
   VWAPState vwapState;
   double swingHigh;
   double swingLow;
   bool bosBullish;
   bool bosBearish;
   AssetProfile assetProfile;
   int openPositions;
   double equityAtStart;
   double equityAtWeekStart;
   datetime lastTradeClose;
   ENUM_EXIT_REASON lastExitReason;
   double lastTradePnL;
   string logDirectory;
   bool loggerReady;
   datetime lastDashboardUpdate;
};

class CSessionManager
{
private:
   datetime m_lastSessionCheck;
   int m_serverOffset;

   datetime GetGMTTime() const
   {
      return TimeGMT();
   }

public:
   CSessionManager() : m_lastSessionCheck(0), m_serverOffset(0) {}

   bool Init()
   {
      datetime serverNow = TimeCurrent();
      datetime gmtNow = TimeGMT();
      m_serverOffset = (int)((serverNow - gmtNow) / 3600);
      if(InpDebugMode)
         Print("[SessionManager] Server-GMT offset: ", m_serverOffset, " hours");
      return true;
   }

   bool IsSessionValid(const AssetProfile &profile) const
   {
      if(profile.trade24_7) return true;
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      int currentHour = dt.hour;
      int currentDay = dt.day_of_week;
      if(profile.skipWeekend && (currentDay == 0 || currentDay == 6))
         return false;
      if(profile.assetClass == ASSET_METAL && currentDay == 5 && currentHour >= 21)
         return false;
      if(profile.assetClass == ASSET_METAL && currentDay == 1 && currentHour < 1)
         return false;
      if(currentHour >= profile.sessionStartHour && currentHour < profile.sessionEndHour)
         return true;
      return false;
   }

   bool IsNewSession(const AssetProfile &profile) const
   {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      if((profile.assetClass == ASSET_FOREX_MAJOR || profile.assetClass == ASSET_FOREX_CROSS ||
          profile.assetClass == ASSET_METAL) && dt.hour == 8 && dt.min == 0)
         return true;
      if(profile.assetClass == ASSET_INDEX && dt.hour == 13 && dt.min == 30)
         return true;
      if(profile.assetClass == ASSET_CRYPTO && dt.hour == 0 && dt.min == 0)
         return true;
      return false;
   }

   datetime GetSessionStart(const AssetProfile &profile) const
   {
      datetime gmtNow = TimeGMT();
      MqlDateTime dt;
      TimeToStruct(gmtNow, dt);
      datetime sessionStart = 0;
      if(profile.assetClass == ASSET_INDEX)
      {
         if(dt.hour < 13 || (dt.hour == 13 && dt.min < 30))
            sessionStart = StringToTime(StringFormat("%04d.%02d.%02d 13:30:00", dt.year, dt.mon, dt.day)) - 86400;
         else
            sessionStart = StringToTime(StringFormat("%04d.%02d.%02d 13:30:00", dt.year, dt.mon, dt.day));
      }
      else
      {
         if(dt.hour < 8)
            sessionStart = StringToTime(StringFormat("%04d.%02d.%02d 08:00:00", dt.year, dt.mon, dt.day)) - 86400;
         else
            sessionStart = StringToTime(StringFormat("%04d.%02d.%02d 08:00:00", dt.year, dt.mon, dt.day));
      }
      return sessionStart + (m_serverOffset * 3600);
   }

   bool IsRolloverTime() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if((dt.hour == 23 && dt.min >= 50) || (dt.hour == 0 && dt.min <= 10))
         return true;
      return false;
   }
};

EAState g_state;
CSessionManager g_session;

#endif // __STATE_MQH__
