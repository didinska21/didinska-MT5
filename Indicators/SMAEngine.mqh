//+------------------------------------------------------------------+
//|                                                  SMAEngine.mqh   |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Thin, defensive wrapper around the built-in SMA indicator     |
//|   handle. Keeps indicator-handle lifecycle (create/release) and |
//|   buffer-copy error handling in ONE place instead of scattering  |
//|   iMA() calls across the codebase.                              |
//+------------------------------------------------------------------+
#ifndef __GHR_SMAENGINE_MQH__
#define __GHR_SMAENGINE_MQH__

#include "../Core/Logger.mqh"

//====================================================================
// CLASS: CSMAEngine
//====================================================================
class CSMAEngine
  {
private:
   int      m_handle;
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int      m_period;
   bool     m_ready;
   CLogger *m_logger;

public:
   CSMAEngine()
     {
      m_handle    = INVALID_HANDLE;
      m_ready     = false;
      m_period    = 0;
      m_timeframe = PERIOD_CURRENT;
      m_logger    = NULL;
     }

   ~CSMAEngine()
     {
      Release();
     }

   //-----------------------------------------------------------------
   // Creates the indicator handle. Must be called once from OnInit().
   // Returns false if handle creation fails (e.g. invalid period).
   //-----------------------------------------------------------------
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, const int period, CLogger *logger)
     {
      m_symbol    = symbol;
      m_timeframe = timeframe;
      m_period    = period;
      m_logger    = logger;

      if(period <= 0)
        {
         if(m_logger != NULL)
            m_logger.Error("CSMAEngine::Init failed - period must be > 0");
         m_ready = false;
         return false;
        }

      m_handle = iMA(m_symbol, m_timeframe, m_period, 0, MODE_SMA, PRICE_CLOSE);

      if(m_handle == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat("CSMAEngine::Init failed - iMA handle invalid for %s period=%d", m_symbol, m_period));
         m_ready = false;
         return false;
        }

      m_ready = true;
      return true;
     }

   //-----------------------------------------------------------------
   // Releases the indicator handle. Must be called from OnDeinit().
   //-----------------------------------------------------------------
   void Release()
     {
      if(m_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_handle);
         m_handle = INVALID_HANDLE;
        }
      m_ready = false;
     }

   bool IsReady() const { return m_ready; }

   //-----------------------------------------------------------------
   // Retrieves the SMA value at the given shift (0 = current/forming bar,
   // 1 = last closed bar). Returns false on failure (not enough data,
   // indicator not ready, etc.) so callers can defensively skip logic
   // rather than trading on a garbage 0.0 value.
   //-----------------------------------------------------------------
   bool GetValue(const int shift, double &outValue)
     {
      outValue = 0.0;

      if(!m_ready || m_handle == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Debug("CSMAEngine::GetValue called before Init/after Release");
         return false;
        }

      double buffer[];
      ArraySetAsSeries(buffer, true);

      int copied = CopyBuffer(m_handle, 0, shift, 1, buffer);
      if(copied <= 0)
        {
         if(m_logger != NULL)
            m_logger.Debug(StringFormat("CSMAEngine::GetValue CopyBuffer failed, shift=%d, error=%d", shift, GetLastError()));
         return false;
        }

      outValue = buffer[0];
      return true;
     }

   //-----------------------------------------------------------------
   // Convenience: is price above the SMA at given shift (bullish bias)?
   //-----------------------------------------------------------------
   bool IsPriceAbove(const double price, const int shift, bool &outResult)
     {
      double smaValue;
      if(!GetValue(shift, smaValue))
         return false;

      outResult = (price > smaValue);
      return true;
     }
  };

#endif // __GHR_SMAENGINE_MQH__
