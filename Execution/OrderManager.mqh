//+------------------------------------------------------------------+
//| Execution/OrderManager.mqh                                       |
//+------------------------------------------------------------------+
#ifndef __ORDER_MANAGER_MQH__
#define __ORDER_MANAGER_MQH__

#include <Trade\Trade.mqh>
#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Core/Logger.mqh"

extern CLogger g_logger;

class COrderManager
{
private:
   CTrade m_trade;
   ulong m_magic;
   AssetProfile m_profile;

public:
   bool Init(ulong magic, const AssetProfile &profile)
   {
      m_magic = magic;
      m_profile = profile;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(10);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_trade.SetAsyncMode(false);
      Print("[OrderManager] Execution layer initialized. Magic: ", magic);
      return true;
   }

   bool ExecuteOrder(const SignalData &signal, const TradeParams &params,
                     EAState &state, ulong &outTicket)
   {
      outTicket = 0;
      if(!ValidateOrder(signal, params)) return false;
      bool useLimit = ShouldUseLimitOrder(signal, state);
      if(useLimit) return ExecuteLimitOrder(signal, params, state, outTicket);
      else return ExecuteMarketOrder(signal, params, state, outTicket);
   }

   bool ExecuteMarketOrder(const SignalData &signal, const TradeParams &params,
                           EAState &state, ulong &outTicket)
   {
      outTicket = 0;
      int slippage = CalculateSlippage(signal.atrValue);
      m_trade.SetDeviationInPoints(slippage);
      bool success = false;
      int retries = 0;
      while(retries <= MAX_RETRIES && !success)
      {
         if(retries > 0)
         {
            int delayMs = RETRY_BASE_MS * (1 << (retries - 1));
            g_logger.LogEvent("ORDER", StringFormat("Retry %d/%d after %d ms", retries, MAX_RETRIES, delayMs));
            Sleep(delayMs);
         }
         if(signal.isBuy)
            success = m_trade.Buy(params.lotSize, _Symbol, signal.entryPrice, signal.slPrice, signal.tp1Price, InpEALabel);
         else
            success = m_trade.Sell(params.lotSize, _Symbol, signal.entryPrice, signal.slPrice, signal.tp1Price, InpEALabel);
         if(!success)
         {
            int err = GetLastError();
            g_logger.LogError("OrderManager", err, GetErrorDescription(err), retries);
            if(!IsRetriableError(err)) { g_logger.LogEvent("ORDER", "Non-retriable error. Aborting."); break; }
            if(err == TRADE_RETCODE_INVALID_STOPS) 
            { 
               SignalData mutableSignal = signal;
               AdjustStops(mutableSignal); 
            }
            else if(err == TRADE_RETCODE_NO_MONEY) { g_logger.LogEvent("ORDER", "No margin. Aborting."); break; }
            else if(err == TRADE_RETCODE_MARKET_CLOSED) { g_logger.LogEvent("ORDER", "Market closed."); break; }
         }
         else outTicket = m_trade.ResultOrder();
         retries++;
      }
      if(success && outTicket > 0)
      {
         if(PositionSelectByTicket(outTicket))
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double lots = PositionGetDouble(POSITION_VOLUME);
            g_logger.LogEvent("ORDER", StringFormat("MARKET ORDER Ticket=%llu Price=%.5f Lots=%.2f", outTicket, openPrice, lots));
            return true;
         }
      }
      return false;
   }

   bool ExecuteLimitOrder(const SignalData &signal, const TradeParams &params,
                          EAState &state, ulong &outTicket)
   {
      outTicket = 0;
      double limitPrice = CalculateLimitPrice(signal);
      double currentPrice = signal.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double maxDistance = signal.atrValue * 0.3;
      if(signal.isBuy && limitPrice > currentPrice + maxDistance)
         return ExecuteMarketOrder(signal, params, state, outTicket);
      if(!signal.isBuy && limitPrice < currentPrice - maxDistance)
         return ExecuteMarketOrder(signal, params, state, outTicket);
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = params.lotSize;
      request.price = limitPrice;
      request.sl = signal.slPrice;
      request.tp = signal.tp1Price;
      request.deviation = CalculateSlippage(signal.atrValue);
      request.magic = m_magic;
      request.comment = InpEALabel + "_LIMIT";
      request.type = signal.isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      request.type_filling = ORDER_FILLING_IOC;
      request.expiration = ORDER_TIME_GTC;
      bool success = OrderSend(request, result);
      if(success && result.retcode == TRADE_RETCODE_DONE)
      {
         outTicket = result.order;
         g_logger.LogEvent("ORDER", StringFormat("LIMIT ORDER Ticket=%llu Price=%.5f Lots=%.2f", outTicket, limitPrice, params.lotSize));
         return true;
      }
      else
      {
         int err = GetLastError();
         g_logger.LogError("OrderManager", err, "Limit order failed", 0);
         return ExecuteMarketOrder(signal, params, state, outTicket);
      }
   }

   void CancelStaleOrders(int maxAgeMinutes = 30)
   {
      int total = OrdersTotal();
      datetime now = TimeCurrent();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(OrderGetInteger(ORDER_MAGIC) != m_magic) continue;
         datetime orderTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         int ageMinutes = (int)((now - orderTime) / 60);
         if(ageMinutes > maxAgeMinutes)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_REMOVE;
            request.order = ticket;
            if(OrderSend(request, result))
               g_logger.LogEvent("ORDER", StringFormat("Cancelled stale order %llu (age: %d min)", ticket, ageMinutes));
         }
      }
   }

private:
   bool ShouldUseLimitOrder(const SignalData &signal, const EAState &state)
   {
      if(state.currentRegime == REGIME_RANGE && InpUseLimitOrders) return true;
      if(signal.pattern == PATTERN_PIN_BAR || signal.pattern == PATTERN_INSIDE_BAR) return InpUseLimitOrders;
      return false;
   }

   double CalculateLimitPrice(const SignalData &signal)
   {
      double currentPrice = signal.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double offset = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 5;
      if(signal.isBuy) return currentPrice - offset;
      else return currentPrice + offset;
   }

   bool ValidateOrder(const SignalData &signal, const TradeParams &params)
   {
      int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = stopsLevel * _Point;
      double slDist = MathAbs(signal.entryPrice - signal.slPrice);
      double tpDist = MathAbs(signal.entryPrice - signal.tp1Price);
      if(slDist < minDist || tpDist < minDist)
      {
         g_logger.LogEvent("ORDER", "VALIDATION FAIL: SL/TP too close");
         return false;
      }
      int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      if(freezeLevel > 0)
      {
         double currentPrice = signal.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(MathAbs(signal.entryPrice - currentPrice) > freezeLevel * _Point * 2)
         {
            g_logger.LogEvent("ORDER", "VALIDATION FAIL: Entry too far");
            return false;
         }
      }
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      if(params.lotSize < minLot || params.lotSize > maxLot)
      {
         g_logger.LogEvent("ORDER", StringFormat("VALIDATION FAIL: Lot %.2f outside range", params.lotSize));
         return false;
      }
      return true;
   }

   int CalculateSlippage(double atrValue) const
   {
      double slippagePrice = atrValue * SLIPPAGE_ATR_MULT;
      int slippagePoints = (int)MathRound(slippagePrice / _Point);
      return MathMax(MIN_SLIPPAGE_PTS, MathMin(MAX_SLIPPAGE_PTS, slippagePoints));
   }

   bool IsRetriableError(int err) const
   {
      switch(err)
      {
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_REJECT:
         case TRADE_RETCODE_CANCEL:
         case TRADE_RETCODE_TIMEOUT:
         case TRADE_RETCODE_INVALID:
         case TRADE_RETCODE_INVALID_VOLUME:
         case TRADE_RETCODE_INVALID_PRICE:
         case TRADE_RETCODE_INVALID_STOPS:
         case TRADE_RETCODE_TRADE_DISABLED:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_PRICE_CHANGED:
            return true;
         default: return false;
      }
   }

   void AdjustStops(SignalData &signal)
   {
      int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = stopsLevel * _Point + _Point * 2;
      if(signal.isBuy)
      {
         signal.slPrice = signal.entryPrice - minDist;
         if(signal.tp1Price <= signal.entryPrice + minDist)
            signal.tp1Price = signal.entryPrice + minDist * 2;
      }
      else
      {
         signal.slPrice = signal.entryPrice + minDist;
         if(signal.tp1Price >= signal.entryPrice - minDist)
            signal.tp1Price = signal.entryPrice - minDist * 2;
      }
   }

   string GetErrorDescription(int err) const
   {
      switch(err)
      {
         case TRADE_RETCODE_REQUOTE: return "Requote";
         case TRADE_RETCODE_REJECT: return "Rejected";
         case TRADE_RETCODE_CANCEL: return "Canceled";
         case TRADE_RETCODE_DONE: return "Done";
         case TRADE_RETCODE_DONE_PARTIAL: return "Partial";
         case TRADE_RETCODE_ERROR: return "Error";
         case TRADE_RETCODE_TIMEOUT: return "Timeout";
         case TRADE_RETCODE_INVALID: return "Invalid";
         case TRADE_RETCODE_INVALID_VOLUME: return "Invalid Volume";
         case TRADE_RETCODE_INVALID_PRICE: return "Invalid Price";
         case TRADE_RETCODE_INVALID_STOPS: return "Invalid Stops";
         case TRADE_RETCODE_TRADE_DISABLED: return "Trade Disabled";
         case TRADE_RETCODE_MARKET_CLOSED: return "Market Closed";
         case TRADE_RETCODE_NO_MONEY: return "No Money";
         case TRADE_RETCODE_PRICE_OFF: return "Price Off";
         case TRADE_RETCODE_CONNECTION: return "No Connection";
         case TRADE_RETCODE_PRICE_CHANGED: return "Price Changed";
         default: return "Unknown " + IntegerToString(err);
      }
   }
};

#endif // __ORDER_MANAGER_MQH__
