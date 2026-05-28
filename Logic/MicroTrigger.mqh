//+------------------------------------------------------------------+
//| Logic/MicroTrigger.mqh                                           |
//| Enhanced LTF Entry Logic with Fibonacci, Liquidity, Price Action |
//| Higher probability entries using multiple confluences            |
//+------------------------------------------------------------------+
#ifndef __MICRO_TRIGGER_MQH__
#define __MICRO_TRIGGER_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Data/PriceEngine.mqh"
#include "../Data/Volatility.mqh"
#include "../Data/FibonacciEngine.mqh"
#include "../Data/LiquidityEngine.mqh"
#include "../Core/Logger.mqh"

extern CLogger g_logger;
extern CVolatility g_volatility;

class CMicroTrigger
{
private:
   ENUM_TIMEFRAMES m_ltf;
   CPriceEngine *m_price;
   CFibonacciEngine m_fib;
   CLiquidityEngine m_liquidity;

public:
   bool Init(ENUM_TIMEFRAMES ltf, CPriceEngine &price)
   {
      m_ltf = ltf;
      m_price = GetPointer(price);

      if(!m_fib.Init(ltf))
      {
         Print("[MicroTrigger] FibonacciEngine init failed");
         return false;
      }

      if(!m_liquidity.Init(ltf))
      {
         Print("[MicroTrigger] LiquidityEngine init failed");
         return false;
      }

      Print("[MicroTrigger] LTF entry logic initialized on ", EnumToString(ltf), " (with Fib + Liquidity)");
      return true;
   }

   void Release() {}

   void GenerateSignal(SignalData &signal, const EAState &state, CPriceEngine &price)
   {
      signal.isValid = false;
      signal.isBuy = false;
      signal.pattern = PATTERN_NONE;
      signal.rejectionReason = "";
      signal.signalTime = TimeCurrent();
      signal.atrValue = 0;

      // Update fibonacci and liquidity levels
      m_fib.Calculate();
      m_liquidity.Update();

      // Check HTF bias validity
      if(state.currentBias == BIAS_NEUTRAL && state.currentRegime != REGIME_RANGE)
      {
         signal.rejectionReason = "HTF Bias Neutral + Not Range Mode";
         return;
      }

      MqlRates bars[4];
      if(!price.GetClosedBar(m_ltf, 1, bars[1]) || !price.GetClosedBar(m_ltf, 2, bars[2]))
      {
         signal.rejectionReason = "Failed to load LTF closed bars";
         return;
      }

      // === CONFLUENCE SCORING SYSTEM ===
      // Each confluence adds to score. Need minimum score for valid signal.
      int confluenceScore = 0;
      bool isBuy = false;
      ENUM_PATTERN detectedPattern = PATTERN_NONE;
      string patternName = "";

      // 1. Check Price Action Patterns (0-3 points)
      if(CheckPinBar(bars[1], state))
      {
         detectedPattern = PATTERN_PIN_BAR;
         patternName = "Pin Bar";
         isBuy = (bars[1].close > bars[1].open);
         confluenceScore += 2;
      }
      else if(CheckEngulfing(bars[1], bars[2]))
      {
         detectedPattern = PATTERN_ENGULFING;
         patternName = "Engulfing";
         isBuy = (bars[1].close > bars[1].open);
         confluenceScore += 2;
      }
      else if(price.GetClosedBar(m_ltf, 3, bars[3]) && CheckInsideBarBreakout(bars[1], bars[2], bars[3]))
      {
         detectedPattern = PATTERN_INSIDE_BAR;
         patternName = "Inside Bar Breakout";
         isBuy = (bars[1].close > bars[2].high);
         confluenceScore += 1;
      }

      if(confluenceScore == 0)
      {
         signal.rejectionReason = "No valid price action pattern";
         return;
      }

      // 2. Check Fibonacci Level (0-2 points)
      int fibLevel = -1;
      if(m_fib.IsNearFibLevel(bars[1].close, 0.5, fibLevel))
      {
         confluenceScore += 2;
         patternName += " + Fib" + m_fib.GetLevelName(fibLevel);
      }
      else if(m_fib.IsNearFibLevel(bars[1].close, 1.0, fibLevel))
      {
         confluenceScore += 1;
         patternName += " + Fib" + m_fib.GetLevelName(fibLevel);
      }

      // 3. Check Order Block (0-2 points)
      OrderBlock ob;
      if(m_liquidity.IsAtOrderBlock(bars[1].close, isBuy, ob))
      {
         confluenceScore += ob.strength;
         patternName += " + OB";
      }

      // 4. Check Liquidity Sweep (0-3 points) - STRONG signal
      bool sweptBuySide;
      if(m_liquidity.WasLiquiditySwept(3, sweptBuySide))
      {
         // If liquidity was swept and we're trading in opposite direction
         if((isBuy && !sweptBuySide) || (!isBuy && sweptBuySide))
         {
            confluenceScore += 3;
            patternName += " + Liquidity Sweep";
         }
      }

      // 5. Check FVG (Fair Value Gap) (0-1 points)
      bool isBullishFVG;
      double fvgTop, fvgBottom;
      if(m_liquidity.HasFVG(10, isBullishFVG, fvgTop, fvgBottom))
      {
         if((isBuy && isBullishFVG) || (!isBuy && !isBullishFVG))
         {
            confluenceScore += 1;
            patternName += " + FVG";
         }
      }

      // === VALIDATION ===
      // Minimum confluence score required
      int minScore = (state.currentRegime == REGIME_TREND) ? 4 : 3;

      if(confluenceScore < minScore)
      {
         signal.rejectionReason = StringFormat("Confluence score %d < minimum %d", confluenceScore, minScore);
         return;
      }

      // Direction validation
      if(!ValidateDirection(isBuy, state))
      {
         signal.rejectionReason = isBuy ? "Bullish signal rejected (HTF Bias: BEAR)" : "Bearish signal rejected (HTF Bias: BULL)";
         return;
      }

      // Build signal
      signal.isValid = true;
      signal.isBuy = isBuy;
      signal.pattern = detectedPattern;
      signal.patternName = patternName + StringFormat(" [Score:%d]", confluenceScore);

      CalculateLevels(signal, bars[1], state);
   }

private:
   bool ValidateDirection(bool isBuy, const EAState &state)
   {
      if(state.currentRegime == REGIME_RANGE) return true;
      if(state.currentBias == BIAS_BULL && !isBuy) return false;
      if(state.currentBias == BIAS_BEAR && isBuy) return false;
      return true;
   }

   bool CheckPinBar(const MqlRates &bar, const EAState &state)
   {
      double body = MathAbs(bar.close - bar.open);
      double upperWick = bar.high - MathMax(bar.open, bar.close);
      double lowerWick = MathMin(bar.open, bar.close) - bar.low;
      double range = bar.high - bar.low;
      if(range == 0 || body == 0) return false;

      bool bullish = (bar.close > bar.open);
      if(bullish)
      {
         bool wickOK = (lowerWick >= body * PIN_BAR_WICK_MULT);
         bool closePos = (bar.close >= bar.low + range * 0.7);
         bool atLevel = IsAtKeyLevel(bar, state, true);
         return wickOK && closePos && atLevel;
      }
      else
      {
         bool wickOK = (upperWick >= body * PIN_BAR_WICK_MULT);
         bool closePos = (bar.close <= bar.low + range * 0.3);
         bool atLevel = IsAtKeyLevel(bar, state, false);
         return wickOK && closePos && atLevel;
      }
   }

   bool CheckEngulfing(const MqlRates &curr, const MqlRates &prev)
   {
      bool bullish = (curr.close > prev.open && curr.open < prev.close);
      bool bearish = (curr.close < prev.open && curr.open > prev.close);
      if(!bullish && !bearish) return false;
      return (curr.tick_volume >= prev.tick_volume * ENGULF_VOLUME_MULT);
   }

   bool CheckInsideBarBreakout(const MqlRates &breakout, const MqlRates &inside, const MqlRates &mother)
   {
      bool isInside = (inside.high < mother.high && inside.low > mother.low);
      if(!isInside) return false;
      bool bullBreak = (breakout.close > inside.high);
      bool bearBreak = (breakout.close < inside.low);
      return (bullBreak || bearBreak);
   }

   bool IsAtKeyLevel(const MqlRates &bar, const EAState &state, bool isBullish)
   {
      double proximity = state.assetProfile.atrMultiplierSL * g_volatility.GetATR() * 0.5;
      if(MathAbs(bar.close - state.vwapState.vwapValue) <= proximity) return true;
      if(isBullish && MathAbs(bar.low - state.swingLow) <= proximity) return true;
      if(!isBullish && MathAbs(bar.high - state.swingHigh) <= proximity) return true;

      // Check fibonacci levels
      int fibIdx;
      if(m_fib.IsNearFibLevel(bar.close, 0.3, fibIdx)) return true;

      return false;
   }

   void CalculateLevels(SignalData &signal, const MqlRates &bar, const EAState &state)
   {
      double atr = g_volatility.GetATR();
      if(atr <= 0) atr = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 10;
      signal.atrValue = atr;

      if(signal.isBuy) signal.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      else signal.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double slMult, tp1Mult, tp2Mult;
      if(state.currentRegime == REGIME_TREND)
      {
         slMult = InpTrendATRMult;
         tp1Mult = InpTrendATRMult * 2.0;
         tp2Mult = InpTrendATRMult * 4.0;
      }
      else
      {
         slMult = InpRangeATRMult;
         tp1Mult = InpRangeATRMult * 1.5;
         tp2Mult = InpRangeATRMult * 2.5;
      }

      double slDist = atr * slMult;
      double tp1Dist = atr * tp1Mult;
      double tp2Dist = atr * tp2Mult;

      // Adjust TP based on fibonacci extensions if available
      if(m_fib.IsValid())
      {
         double fibExtension = m_fib.GetExtension(1.618);
         if(fibExtension > 0)
         {
            if(signal.isBuy && fibExtension > signal.entryPrice + tp1Dist)
               tp2Dist = fibExtension - signal.entryPrice;
            else if(!signal.isBuy && fibExtension < signal.entryPrice - tp1Dist)
               tp2Dist = signal.entryPrice - fibExtension;
         }
      }

      if(signal.isBuy)
      {
         signal.slPrice = signal.entryPrice - slDist;
         signal.tp1Price = signal.entryPrice + tp1Dist;
         signal.tp2Price = signal.entryPrice + tp2Dist;
      }
      else
      {
         signal.slPrice = signal.entryPrice + slDist;
         signal.tp1Price = signal.entryPrice - tp1Dist;
         signal.tp2Price = signal.entryPrice - tp2Dist;
      }

      signal.isValid = true;
   }
};

#endif // __MICRO_TRIGGER_MQH__
