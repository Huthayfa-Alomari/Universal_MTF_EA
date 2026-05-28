//+------------------------------------------------------------------+
//| Risk/PositionSizer.mqh                                           |
//+------------------------------------------------------------------+
#ifndef __POSITION_SIZER_MQH__
#define __POSITION_SIZER_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"

class CPositionSizer
{
private:
   AssetProfile m_profile;
   double m_maxRiskPercent;

public:
   bool Init(const AssetProfile &profile, double maxRisk)
   {
      m_profile = profile; m_maxRiskPercent = maxRisk;
      Print("[PositionSizer] Max risk per trade: ", maxRisk, "%");
      return true;
   }
   void Calculate(TradeParams &params, const SignalData &signal, const EAState &state)
   {
      params.isValid = false; params.rejectReason = "";
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) { params.rejectReason = "Invalid account equity"; return; }
      double riskAmount = equity * (m_maxRiskPercent / 100.0);
      double slDistance = MathAbs(signal.entryPrice - signal.slPrice);
      if(slDistance <= 0) { params.rejectReason = "Invalid SL distance"; return; }
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickValue <= 0 || tickSize <= 0) { params.rejectReason = "Invalid tick value/size"; return; }
      double slTicks = slDistance / tickSize;
      double lotSize = riskAmount / (slTicks * tickValue);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep > 0) lotSize = MathFloor(lotSize / lotStep) * lotStep;
      lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

      double marginRequired = 0;
      double price = signal.entryPrice;
      bool marginCalc = OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, price, marginRequired);

      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginCalc && marginRequired > 0 && freeMargin < marginRequired * 1.2)
      {
         double maxLotByMargin = (freeMargin / 1.2) / (marginRequired / lotSize);
         if(lotStep > 0) lotSize = MathFloor(maxLotByMargin / lotStep) * lotStep;
         lotSize = MathMax(minLot, lotSize);
         if(lotSize <= minLot) { params.rejectReason = "Insufficient margin"; return; }
         marginCalc = OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, price, marginRequired);
      }

      double finalSlTicks = slDistance / tickSize;
      double finalRisk = lotSize * finalSlTicks * tickValue;
      double finalRiskPercent = (finalRisk / equity) * 100.0;
      if(finalRiskPercent > m_maxRiskPercent * 1.1)
      { params.rejectReason = "Risk exceeds max"; return; }
      params.lotSize = lotSize; params.riskAmount = finalRisk;
      params.riskPercent = finalRiskPercent; params.slDistance = slDistance;
      params.tp1Distance = MathAbs(signal.tp1Price - signal.entryPrice);
      params.tp2Distance = MathAbs(signal.tp2Price - signal.entryPrice);
      params.marginRequired = marginRequired; params.isValid = true;
   }
};

#endif // __POSITION_SIZER_MQH__
