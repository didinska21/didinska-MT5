//+------------------------------------------------------------------+
//|                                                       Utils.mqh  |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Stateless, reusable helper functions used across every        |
//|   module (lot normalization, price/points conversion, safe      |
//|   math, time helpers, string helpers). Keeping these here        |
//|   avoids duplicated code across the Trade/Recovery/Risk          |
//|   engines (DRY principle).                                       |
//+------------------------------------------------------------------+
#ifndef __GHR_UTILS_MQH__
#define __GHR_UTILS_MQH__

#include "../Config/Inputs.mqh"

//====================================================================
// CLASS: CUtils
// A namespace-style static class. No instance state — every method
// is self-contained and safe to call from any module.
//====================================================================
class CUtils
  {
public:
   //-----------------------------------------------------------------
   // Lot normalization: clamps a raw lot value to the broker's
   // allowed min/max/step for the given symbol. Prevents
   // ERR_INVALID_TRADE_VOLUME on order send.
   //-----------------------------------------------------------------
   static double NormalizeLot(const string symbol, double rawLot)
     {
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(stepLot <= 0.0)
         stepLot = 0.01;

      double steps = MathRound(rawLot / stepLot);
      double lot   = steps * stepLot;

      if(lot < minLot)
         lot = minLot;
      if(maxLot > 0.0 && lot > maxLot)
         lot = maxLot;

      // Re-round to avoid floating point artifacts (e.g. 0.070000000001)
      int digits = 2;
      if(stepLot < 0.01)
         digits = 3;
      lot = NormalizeDouble(lot, digits);

      return lot;
     }

   //-----------------------------------------------------------------
   // Points <-> Price helpers (symbol aware)
   //-----------------------------------------------------------------
   static double PointsToPrice(const string symbol, double points)
     {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return points * point;
     }

   static double PriceToPoints(const string symbol, double priceDelta)
     {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return 0.0;
      return priceDelta / point;
     }

   //-----------------------------------------------------------------
   // Normalize a price to the symbol's digit precision.
   //-----------------------------------------------------------------
   static double NormalizePrice(const string symbol, double price)
     {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      return NormalizeDouble(price, digits);
     }

   //-----------------------------------------------------------------
   // Current spread in points for a symbol.
   //-----------------------------------------------------------------
   static double GetSpreadPoints(const string symbol)
     {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return 0.0;
      return (ask - bid) / point;
     }

   //-----------------------------------------------------------------
   // Safe division — avoids division by zero crashes.
   //-----------------------------------------------------------------
   static double SafeDivide(double numerator, double denominator, double fallback = 0.0)
     {
      if(MathAbs(denominator) < 0.0000001)
         return fallback;
      return numerator / denominator;
     }

   //-----------------------------------------------------------------
   // Parses a comma separated lot sequence string (e.g. "0.01,0.02,0.04")
   // into a double array. Used by RECOVERY_CUSTOM_SEQUENCE mode.
   // Returns the number of parsed elements.
   //-----------------------------------------------------------------
   static int ParseCsvDoubles(const string csv, double &out[])
     {
      string parts[];
      int count = StringSplit(csv, ',', parts);
      ArrayResize(out, count);

      int validCount = 0;
      for(int i = 0; i < count; i++)
        {
         string trimmed = parts[i];
         StringTrimLeft(trimmed);
         StringTrimRight(trimmed);
         if(StringLen(trimmed) == 0)
            continue;
         out[validCount] = StringToDouble(trimmed);
         validCount++;
        }
      ArrayResize(out, validCount);
      return validCount;
     }

   //-----------------------------------------------------------------
   // Returns true if the current broker time hour falls within
   // [startHour, endHour). Handles overnight ranges (e.g. 22 -> 4).
   //-----------------------------------------------------------------
   static bool IsWithinHourRange(int startHour, int endHour)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      if(startHour == endHour)
         return true; // 24h session

      if(startHour < endHour)
         return (hour >= startHour && hour < endHour);

      // overnight wrap, e.g. 22 -> 4
      return (hour >= startHour || hour < endHour);
     }

   //-----------------------------------------------------------------
   // Formats a datetime as a compact string for logs/dashboard.
   //-----------------------------------------------------------------
   static string FormatDateTime(datetime t)
     {
      return TimeToString(t, TIME_DATE | TIME_MINUTES | TIME_SECONDS);
     }

   //-----------------------------------------------------------------
   // Formats a money value with fixed 2 decimals and currency symbol.
   //-----------------------------------------------------------------
   static string FormatMoney(double value)
     {
      return StringFormat("%.2f", value);
     }

   //-----------------------------------------------------------------
   // Human readable retcode description (used by Logger on trade errors).
   //-----------------------------------------------------------------
   static string RetcodeDescription(int retcode)
     {
      switch(retcode)
        {
         case TRADE_RETCODE_REQUOTE:            return "Requote";
         case TRADE_RETCODE_REJECT:              return "Request rejected";
         case TRADE_RETCODE_CANCEL:              return "Request canceled by trader";
         case TRADE_RETCODE_PLACED:              return "Order placed";
         case TRADE_RETCODE_DONE:                return "Request completed";
         case TRADE_RETCODE_DONE_PARTIAL:        return "Request partially completed";
         case TRADE_RETCODE_ERROR:               return "Request processing error";
         case TRADE_RETCODE_TIMEOUT:             return "Request timeout";
         case TRADE_RETCODE_INVALID:             return "Invalid request";
         case TRADE_RETCODE_INVALID_VOLUME:      return "Invalid volume";
         case TRADE_RETCODE_INVALID_PRICE:       return "Invalid price";
         case TRADE_RETCODE_INVALID_STOPS:       return "Invalid stops";
         case TRADE_RETCODE_TRADE_DISABLED:      return "Trade disabled";
         case TRADE_RETCODE_MARKET_CLOSED:       return "Market closed";
         case TRADE_RETCODE_NO_MONEY:            return "Not enough money";
         case TRADE_RETCODE_PRICE_CHANGED:       return "Price changed";
         case TRADE_RETCODE_PRICE_OFF:           return "Off quotes";
         case TRADE_RETCODE_INVALID_EXPIRATION:  return "Invalid order expiration";
         case TRADE_RETCODE_ORDER_CHANGED:       return "Order state changed";
         case TRADE_RETCODE_TOO_MANY_REQUESTS:   return "Too many requests";
         case TRADE_RETCODE_NO_CHANGES:          return "No changes in request";
         case TRADE_RETCODE_SERVER_DISABLES_AT:  return "Autotrading disabled by server";
         case TRADE_RETCODE_CLIENT_DISABLES_AT:  return "Autotrading disabled by client terminal";
         case TRADE_RETCODE_LOCKED:              return "Request locked for processing";
         case TRADE_RETCODE_FROZEN:              return "Order or position frozen";
         case TRADE_RETCODE_INVALID_FILL:        return "Invalid fill type";
         case TRADE_RETCODE_CONNECTION:          return "No connection with trade server";
         case TRADE_RETCODE_ONLY_REAL:           return "Operation allowed only for live accounts";
         case TRADE_RETCODE_LIMIT_ORDERS:        return "Pending orders limit reached";
         case TRADE_RETCODE_LIMIT_VOLUME:        return "Volume limit reached";
         case TRADE_RETCODE_POSITION_CLOSED:     return "Position already closed";
         default:                                return "Unknown retcode (" + IntegerToString(retcode) + ")";
        }
     }

   //-----------------------------------------------------------------
   // Returns true if a retcode is considered "retryable"
   // (transient/network related, worth retrying the send).
   //-----------------------------------------------------------------
   static bool IsRetryableRetcode(int retcode)
     {
      switch(retcode)
        {
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_PRICE_CHANGED:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_TIMEOUT:
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_TOO_MANY_REQUESTS:
         case TRADE_RETCODE_LOCKED:
         case TRADE_RETCODE_FROZEN:
            return true;
         default:
            return false;
        }
     }
  };

#endif // __GHR_UTILS_MQH__
