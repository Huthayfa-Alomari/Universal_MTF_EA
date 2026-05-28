//+------------------------------------------------------------------+
//| Logic/MicroTrigger.mqh                                           |
//+------------------------------------------------------------------+
#ifndef __MICRO_TRIGGER_MQH__
#define __MICRO_TRIGGER_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Data/PriceEngine.mqh"
#include "../Data/Volatility.mqh"
#include "../Core/Logger.mqh"

extern CLogger g_logger;
extern CVolatility g_volatility;

class CMicroTrigger
{
private:
   ENUM_TIMEFRAMES m_ltf;
   CPriceEngine *m_price;

public:
   bool Init(ENUM_TIMEFRAMES ltf, CPriceEngine &price)
   {
      m_ltf = ltf; m_price = GetPointer(price);
      Print("[MicroTrigger] LTF entry logic initialized on ", EnumToString(ltf));
      return true;
   }
   void Release() {}
   void GenerateSignal(SignalData &signal, const EAState &state, CPriceEngine &price)
   {
      signal.isValid = false; signal.isBuy = false; signal.pattern = PATTERN_NONE;
      signal.rejectionReason = ""; signal.signalTime = TimeCurrent(); signal.atrValue = 0;
      if(state.currentBias == BIAS_NEUTRAL && state.currentRegime != REGIME_RANGE)
      { signal.rejectionReason = "HTF Bias Neutral + Not Range Mode"; return; }
      MqlRates bars[4];
      if(!price.GetClosedBar(m_ltf, 1, bars[1]) || !price.GetClosedBar(m_ltf, 2, bars[2]))
      { signal.rejectionReason = "Failed to load LTF closed bars"; return; }
      if(CheckPinBar(bars[1], state))
      {
         signal.pattern = PATTERN_PIN_BAR; signal.patternName = "Pin Bar";
         signal.isBuy = (bars[1].close > bars[1].open);
         if(ValidateDirection(signal, state)) { CalculateLevels(signal, bars[1], state); return; }
      }
      if(!price.GetClosedBar(m_ltf, 2, bars[2])) { signal.rejectionReason = "Failed to load bar[2]"; return; }
      if(CheckEngulfing(bars[1], bars[2]))
      {
         signal.pattern = PATTERN_ENGULFING; signal.patternName = "Engulfing";
         signal.isBuy = (bars[1].close > bars[1].open);
         if(ValidateDirection(signal, state)) { CalculateLevels(signal, bars[1], state); return; }
      }
      if(price.GetClosedBar(m_ltf, 3, bars[3]))
      {
         if(CheckInsideBarBreakout(bars[1], bars[2], bars[3]))
         {
            signal.pattern = PATTERN_INSIDE_BAR; signal.patternName = "Inside Bar Breakout";
            signal.isBuy = (bars[1].close > bars[2].high);
            if(ValidateDirection(signal, state)) { CalculateLevels(signal, bars[1], state); return; }
         }
      }
      signal.rejectionReason = "No valid price action pattern";
   }

private:
   bool ValidateDirection(SignalData &signal, const EAState &state)
   {
      if(state.currentRegime == REGIME_RANGE) return true;
      if(state.currentBias == BIAS_BULL && !signal.isBuy)
      { signal.isValid = false; signal.rejectionReason = "Bearish signal rejected (HTF Bias: BULL)"; return false; }
      if(state.currentBias == BIAS_BEAR && signal.isBuy)
      { signal.isValid = false; signal.rejectionReason = "Bullish signal rejected (HTF Bias: BEAR)"; return false; }
      signal.isValid = true; return true;
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
      int maHandle = iMA(_Symbol, m_ltf, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(maHandle != INVALID_HANDLE)
      {
         double maBuf[]; ArraySetAsSeries(maBuf, true);
         if(CopyBuffer(maHandle, 0, 1, 1, maBuf) > 0)
         {
            double ema50 = maBuf[0];
            IndicatorRelease(maHandle);
            if(MathAbs(bar.close - ema50) <= proximity) return true;
         }
         IndicatorRelease(maHandle);
      }
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
      { slMult = InpTrendATRMult; tp1Mult = InpTrendATRMult * 2.0; tp2Mult = InpTrendATRMult * 4.0; }
      else
      { slMult = InpRangeATRMult; tp1Mult = InpRangeATRMult * 1.5; tp2Mult = InpRangeATRMult * 2.5; }
      double slDist = atr * slMult;
      double tp1Dist = atr * tp1Mult;
      double tp2Dist = atr * tp2Mult;
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
