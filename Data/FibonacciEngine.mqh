//+------------------------------------------------------------------+
//| Data/FibonacciEngine.mqh                                         |
//| Fibonacci Retracement & Extension Analysis                       |
//| Identifies key S/R levels: 0.236, 0.382, 0.5, 0.618, 0.786      |
//| Uses swing highs/lows for accurate level placement              |
//+------------------------------------------------------------------+
#ifndef __FIBONACCI_ENGINE_MQH__
#define __FIBONACCI_ENGINE_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Data/PriceEngine.mqh"

class CFibonacciEngine
{
private:
   ENUM_TIMEFRAMES m_tf;
   double m_levels[7];     // 0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0
   double m_levelValues[7];
   bool m_levelsValid;
   double m_swingHigh;
   double m_swingLow;
   datetime m_swingHighTime;
   datetime m_swingLowTime;

public:
   CFibonacciEngine() : m_levelsValid(false), m_swingHigh(0), m_swingLow(0) {}

   bool Init(ENUM_TIMEFRAMES tf)
   {
      m_tf = tf;
      m_levels[0] = 0.0;
      m_levels[1] = 0.236;
      m_levels[2] = 0.382;
      m_levels[3] = 0.500;
      m_levels[4] = 0.618;
      m_levels[5] = 0.786;
      m_levels[6] = 1.0;
      Print("[FibonacciEngine] Initialized on ", EnumToString(tf));
      return true;
   }

   void Calculate()
   {
      // Find significant swing high and low
      FindSwingPoints();

      if(m_swingHigh <= m_swingLow || m_swingHigh == 0 || m_swingLow == 0)
      {
         m_levelsValid = false;
         return;
      }

      double range = m_swingHigh - m_swingLow;
      for(int i = 0; i < 7; i++)
      {
         m_levelValues[i] = m_swingHigh - (range * m_levels[i]);
      }
      m_levelsValid = true;
   }

   // Check if price is near a key fibonacci level (for entries)
   bool IsNearFibLevel(double price, double tolerance, int &nearestLevel)
   {
      if(!m_levelsValid) return false;

      nearestLevel = -1;
      double minDist = DBL_MAX;

      // Most important levels for entries: 0.382, 0.5, 0.618, 0.786
      int keyLevels[] = {2, 3, 4, 5};

      for(int i = 0; i < ArraySize(keyLevels); i++)
      {
         int idx = keyLevels[i];
         double dist = MathAbs(price - m_levelValues[idx]);
         if(dist < minDist)
         {
            minDist = dist;
            nearestLevel = idx;
         }
      }

      double atr = iATR(_Symbol, m_tf, 14);
      if(atr == 0) atr = _Point * 50;

      return (minDist <= tolerance * atr);
   }

   // Get the strongest level (0.618 golden ratio)
   double GetGoldenRatioLevel() const
   {
      if(!m_levelsValid) return 0;
      return m_levelValues[4]; // 0.618
   }

   // Get 0.786 level (deep retracement - final support/resistance)
   double GetDeepLevel() const
   {
      if(!m_levelsValid) return 0;
      return m_levelValues[5]; // 0.786
   }

   // Check if price broke a fib level (trend continuation signal)
   bool DidBreakLevel(double prevClose, double currClose, int levelIdx)
   {
      if(!m_levelsValid || levelIdx < 0 || levelIdx >= 7) return false;

      double level = m_levelValues[levelIdx];
      return ((prevClose < level && currClose > level) || 
              (prevClose > level && currClose < level));
   }

   // Get fibonacci extension for TP calculation
   double GetExtension(double multiplier)
   {
      if(!m_levelsValid) return 0;
      double range = m_swingHigh - m_swingLow;
      return m_swingHigh + (range * multiplier);
   }

   string GetLevelName(int idx) const
   {
      if(idx < 0 || idx >= 7) return "Invalid";
      string names[] = {"0.0", "0.236", "0.382", "0.5", "0.618", "0.786", "1.0"};
      return names[idx];
   }

   bool IsValid() const { return m_levelsValid; }
   double GetSwingHigh() const { return m_swingHigh; }
   double GetSwingLow() const { return m_swingLow; }

private:
   void FindSwingPoints()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(_Symbol, m_tf, 0, 100, rates);
      if(copied < 20) { m_levelsValid = false; return; }

      // Find swing high (highest high in last 50 bars)
      m_swingHigh = 0;
      m_swingHighTime = 0;
      int highIdx = iHighest(_Symbol, m_tf, MODE_HIGH, 50, 1);
      if(highIdx >= 0)
      {
         m_swingHigh = iHigh(_Symbol, m_tf, highIdx);
         m_swingHighTime = iTime(_Symbol, m_tf, highIdx);
      }

      // Find swing low (lowest low in last 50 bars)
      m_swingLow = DBL_MAX;
      m_swingLowTime = 0;
      int lowIdx = iLowest(_Symbol, m_tf, MODE_LOW, 50, 1);
      if(lowIdx >= 0)
      {
         m_swingLow = iLow(_Symbol, m_tf, lowIdx);
         m_swingLowTime = iTime(_Symbol, m_tf, lowIdx);
      }
   }
};

#endif // __FIBONACCI_ENGINE_MQH__
