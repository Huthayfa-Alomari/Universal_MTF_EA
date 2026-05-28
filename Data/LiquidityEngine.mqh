//+------------------------------------------------------------------+
//| Data/LiquidityEngine.mqh                                         |
//| Smart Money Concepts: Order Blocks, Liquidity Sweeps, FVG        |
//| Identifies institutional levels for high-probability entries     |
//+------------------------------------------------------------------+
#ifndef __LIQUIDITY_ENGINE_MQH__
#define __LIQUIDITY_ENGINE_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"

struct OrderBlock
{
   double high;
   double low;
   double open;
   double close;
   datetime time;
   bool isBullish;       // true = bullish OB (buy zone)
   bool isValid;
   int strength;         // 1-3 based on volume and follow-through
};

struct LiquidityPool
{
   double level;
   datetime time;
   bool isBuySide;       // true = buy-side liquidity (equal highs)
   bool isSwept;         // true = liquidity was swept/taken
   int touchCount;       // how many times price touched this level
};

class CLiquidityEngine
{
private:
   ENUM_TIMEFRAMES m_tf;
   OrderBlock m_bullishOBs[];
   OrderBlock m_bearishOBs[];
   LiquidityPool m_pools[];
   int m_maxOBs;
   int m_lookback;

public:
   CLiquidityEngine() : m_maxOBs(5), m_lookback(50) {}

   bool Init(ENUM_TIMEFRAMES tf)
   {
      m_tf = tf;
      ArrayResize(m_bullishOBs, m_maxOBs);
      ArrayResize(m_bearishOBs, m_maxOBs);
      ArrayResize(m_pools, 10);
      Print("[LiquidityEngine] Initialized on ", EnumToString(tf));
      return true;
   }

   void Update()
   {
      FindOrderBlocks();
      FindLiquidityPools();
   }

   // Check if price is at a valid order block
   bool IsAtOrderBlock(double price, bool wantBullish, OrderBlock &outOB)
   {
      if(wantBullish)
      {
         for(int i = 0; i < ArraySize(m_bullishOBs); i++)
         {
            if(!m_bullishOBs[i].isValid) continue;
            if(price >= m_bullishOBs[i].low && price <= m_bullishOBs[i].high)
            {
               outOB = m_bullishOBs[i];
               return true;
            }
         }
      }
      else
      {
         for(int i = 0; i < ArraySize(m_bearishOBs); i++)
         {
            if(!m_bearishOBs[i].isValid) continue;
            if(price >= m_bearishOBs[i].low && price <= m_bearishOBs[i].high)
            {
               outOB = m_bearishOBs[i];
               return true;
            }
         }
      }
      return false;
   }

   // Check for liquidity sweep (stop hunt) - reversal signal
   bool WasLiquiditySwept(int barsBack, bool &sweptBuySide)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, m_tf, 0, barsBack + 5, rates) < barsBack + 5) return false;

      // Check for sweep of equal highs/lows
      double recentHigh = 0, recentLow = DBL_MAX;
      for(int i = 1; i <= barsBack; i++)
      {
         if(rates[i].high > recentHigh) recentHigh = rates[i].high;
         if(rates[i].low < recentLow) recentLow = rates[i].low;
      }

      // Buy-side liquidity sweep (swept highs then reversed down)
      if(rates[0].high > recentHigh && rates[0].close < rates[1].close)
      {
         sweptBuySide = true;
         return true;
      }

      // Sell-side liquidity sweep (swept lows then reversed up)
      if(rates[0].low < recentLow && rates[0].close > rates[1].close)
      {
         sweptBuySide = false;
         return true;
      }

      return false;
   }

   // Check for Fair Value Gap (FVG) - imbalance zone
   bool HasFVG(int barsBack, bool &isBullishFVG, double &fvgTop, double &fvgBottom)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, m_tf, 0, barsBack + 3, rates) < barsBack + 3) return false;

      for(int i = 1; i < barsBack; i++)
      {
         // Bullish FVG: current low > previous high (gap up)
         if(rates[i].low > rates[i+1].high)
         {
            isBullishFVG = true;
            fvgTop = rates[i].low;
            fvgBottom = rates[i+1].high;
            return true;
         }
         // Bearish FVG: current high < previous low (gap down)
         if(rates[i].high < rates[i+1].low)
         {
            isBullishFVG = false;
            fvgTop = rates[i+1].low;
            fvgBottom = rates[i].high;
            return true;
         }
      }
      return false;
   }

   // Get the nearest untapped liquidity level
   double GetNearestLiquidity(double currentPrice, bool above)
   {
      double nearest = 0;
      double minDist = DBL_MAX;

      for(int i = 0; i < ArraySize(m_pools); i++)
      {
         if(m_pools[i].isSwept) continue;

         if(above && m_pools[i].level > currentPrice)
         {
            double dist = m_pools[i].level - currentPrice;
            if(dist < minDist) { minDist = dist; nearest = m_pools[i].level; }
         }
         else if(!above && m_pools[i].level < currentPrice)
         {
            double dist = currentPrice - m_pools[i].level;
            if(dist < minDist) { minDist = dist; nearest = m_pools[i].level; }
         }
      }
      return nearest;
   }

private:
   void FindOrderBlocks()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(_Symbol, m_tf, 0, m_lookback, rates);
      if(copied < 10) return;

      int bullCount = 0, bearCount = 0;

      for(int i = 2; i < copied - 1 && (bullCount < m_maxOBs || bearCount < m_maxOBs); i++)
      {
         // Bullish Order Block: bearish candle before strong bullish move
         if(rates[i].close < rates[i].open && rates[i-1].close > rates[i-1].open * 1.01)
         {
            // Strong bullish follow-through
            if(bullCount < m_maxOBs)
            {
               m_bullishOBs[bullCount].high = rates[i].high;
               m_bullishOBs[bullCount].low = rates[i].low;
               m_bullishOBs[bullCount].open = rates[i].open;
               m_bullishOBs[bullCount].close = rates[i].close;
               m_bullishOBs[bullCount].time = rates[i].time;
               m_bullishOBs[bullCount].isBullish = true;
               m_bullishOBs[bullCount].isValid = true;
               m_bullishOBs[bullCount].strength = CalculateStrength(rates, i);
               bullCount++;
            }
         }

         // Bearish Order Block: bullish candle before strong bearish move
         if(rates[i].close > rates[i].open && rates[i-1].close < rates[i-1].open * 0.99)
         {
            // Strong bearish follow-through
            if(bearCount < m_maxOBs)
            {
               m_bearishOBs[bearCount].high = rates[i].high;
               m_bearishOBs[bearCount].low = rates[i].low;
               m_bearishOBs[bearCount].open = rates[i].open;
               m_bearishOBs[bearCount].close = rates[i].close;
               m_bearishOBs[bearCount].time = rates[i].time;
               m_bearishOBs[bearCount].isBullish = false;
               m_bearishOBs[bearCount].isValid = true;
               m_bearishOBs[bearCount].strength = CalculateStrength(rates, i);
               bearCount++;
            }
         }
      }
   }

   void FindLiquidityPools()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(_Symbol, m_tf, 0, m_lookback, rates);
      if(copied < 20) return;

      int poolCount = 0;

      // Find equal highs (buy-side liquidity)
      for(int i = 5; i < copied - 5 && poolCount < 10; i++)
      {
         double currHigh = rates[i].high;
         bool isEqualHigh = false;

         for(int j = i + 2; j < i + 10 && j < copied; j++)
         {
            if(MathAbs(rates[j].high - currHigh) < _Point * 10)
            {
               isEqualHigh = true;
               break;
            }
         }

         if(isEqualHigh)
         {
            m_pools[poolCount].level = currHigh;
            m_pools[poolCount].time = rates[i].time;
            m_pools[poolCount].isBuySide = true;
            m_pools[poolCount].isSwept = (rates[0].high > currHigh + _Point * 5);
            m_pools[poolCount].touchCount = 2;
            poolCount++;
         }
      }

      // Find equal lows (sell-side liquidity)
      for(int i = 5; i < copied - 5 && poolCount < 10; i++)
      {
         double currLow = rates[i].low;
         bool isEqualLow = false;

         for(int j = i + 2; j < i + 10 && j < copied; j++)
         {
            if(MathAbs(rates[j].low - currLow) < _Point * 10)
            {
               isEqualLow = true;
               break;
            }
         }

         if(isEqualLow)
         {
            m_pools[poolCount].level = currLow;
            m_pools[poolCount].time = rates[i].time;
            m_pools[poolCount].isBuySide = false;
            m_pools[poolCount].isSwept = (rates[0].low < currLow - _Point * 5);
            m_pools[poolCount].touchCount = 2;
            poolCount++;
         }
      }
   }

   int CalculateStrength(MqlRates &rates[], int idx)
   {
      int strength = 1;

      // Volume check
      double avgVol = 0;
      for(int i = idx; i < idx + 5 && i < ArraySize(rates); i++)
         avgVol += (double)rates[i].tick_volume;
      avgVol /= 5.0;

      if(rates[idx].tick_volume > avgVol * 1.5) strength++;
      if(rates[idx].tick_volume > avgVol * 2.0) strength++;

      return MathMin(strength, 3);
   }
};

#endif // __LIQUIDITY_ENGINE_MQH__
