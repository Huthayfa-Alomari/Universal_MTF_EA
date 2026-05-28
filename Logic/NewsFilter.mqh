//+------------------------------------------------------------------+
//| Logic/NewsFilter.mqh                                             |
//| Economic News Filter                                             |
//+------------------------------------------------------------------+
#ifndef __NEWS_FILTER_MQH__
#define __NEWS_FILTER_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Core/Logger.mqh"

extern CLogger g_logger;

class CNewsFilter
{
private:
   string m_currency;
   int m_minutesBefore;
   int m_minutesAfter;
   bool m_initialized;

   struct NewsEvent
   {
      datetime time;
      string currency;
      string event;
      int impact;
   };

   NewsEvent m_events[];
   datetime m_lastCalendarUpdate;

public:
   CNewsFilter() : m_minutesBefore(30), m_minutesAfter(15), m_initialized(false) {}

   bool Init(int minutesBefore = 30, int minutesAfter = 15)
   {
      m_minutesBefore = minutesBefore;
      m_minutesAfter = minutesAfter;
      string sym = _Symbol;
      if(StringFind(sym, "USD") >= 0) m_currency = "USD";
      else if(StringFind(sym, "EUR") >= 0) m_currency = "EUR";
      else if(StringFind(sym, "GBP") >= 0) m_currency = "GBP";
      else if(StringFind(sym, "JPY") >= 0) m_currency = "JPY";
      else if(StringFind(sym, "AUD") >= 0) m_currency = "AUD";
      else if(StringFind(sym, "CAD") >= 0) m_currency = "CAD";
      else if(StringFind(sym, "CHF") >= 0) m_currency = "CHF";
      else if(StringFind(sym, "NZD") >= 0) m_currency = "NZD";
      else m_currency = "USD";
      m_initialized = true;
      m_lastCalendarUpdate = 0;
      Print("[NewsFilter] Initialized for ", m_currency);
      return true;
   }

   bool IsTradingAllowed()
   {
      if(!m_initialized) return true;
      datetime now = TimeCurrent();
      if(now - m_lastCalendarUpdate > 3600) { UpdateCalendar(); m_lastCalendarUpdate = now; }
      for(int i = 0; i < ArraySize(m_events); i++)
      {
         if(m_events[i].impact < 3) continue;
         datetime blockStart = m_events[i].time - m_minutesBefore * 60;
         datetime blockEnd = m_events[i].time + m_minutesAfter * 60;
         if(now >= blockStart && now <= blockEnd)
         {
            g_logger.LogEvent("NEWS", StringFormat("TRADING BLOCKED: %s at %s", m_events[i].event, TimeToString(m_events[i].time)));
            return false;
         }
      }
      return true;
   }

private:
   void UpdateCalendar()
   {
      ArrayResize(m_events, 0);
      string filename = "NewsCalendar_" + m_currency + ".csv";
      if(FileIsExist(filename, FILE_COMMON))
      {
         int handle = FileOpen(filename, FILE_READ|FILE_CSV|FILE_COMMON, ',');
         if(handle != INVALID_HANDLE)
         {
            while(!FileIsEnding(handle))
            {
               string dateStr = FileReadString(handle);
               string timeStr = FileReadString(handle);
               string currency = FileReadString(handle);
               string event = FileReadString(handle);
               string impactStr = FileReadString(handle);
               if(dateStr == "" || timeStr == "") continue;
               datetime eventTime = StringToTime(dateStr + " " + timeStr);
               int impact = (int)StringToInteger(impactStr);
               if(impact >= 3 && (currency == m_currency || currency == "ALL"))
               {
                  int idx = ArraySize(m_events);
                  ArrayResize(m_events, idx + 1);
                  m_events[idx].time = eventTime;
                  m_events[idx].currency = currency;
                  m_events[idx].event = event;
                  m_events[idx].impact = impact;
               }
            }
            FileClose(handle);
         }
      }
      if(ArraySize(m_events) == 0) AddBuiltinEvents();
   }

   void AddBuiltinEvents()
   {
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      for(int monthOffset = 0; monthOffset <= 1; monthOffset++)
      {
         int year = dt.year;
         int month = dt.mon + monthOffset;
         if(month > 12) { month = 1; year++; }
         datetime firstDay = StringToTime(StringFormat("%04d.%02d.01 00:00:00", year, month));
         MqlDateTime firstDt;
         TimeToStruct(firstDay, firstDt);
         int daysToFriday = (5 - firstDt.day_of_week + 7) % 7;
         datetime firstFriday = firstDay + daysToFriday * 86400;
         datetime nfpTime = firstFriday + 13 * 3600 + 30 * 60;
         if(nfpTime > now - 86400)
         {
            int idx = ArraySize(m_events);
            ArrayResize(m_events, idx + 1);
            m_events[idx].time = nfpTime;
            m_events[idx].currency = "USD";
            m_events[idx].event = "Non-Farm Payrolls";
            m_events[idx].impact = 3;
         }
      }
   }
};

#endif // __NEWS_FILTER_MQH__
