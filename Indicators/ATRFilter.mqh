//+------------------------------------------------------------------+
//|                                                 ATRFilter.mqh    |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Wraps the ATR indicator and exposes a simple volatility gate:  |
//|   entries are only allowed when ATR (in points) sits between     |
//|   InpAtrMinPoints and InpAtrMaxPoints. This filters out both     |
//|   dead/choppy markets AND abnormal news-spike volatility.        |
//+------------------------------------------------------------------+
#ifndef __GHR_ATRFILTER_MQH__
#define __GHR_ATRFILTER_MQH__

#include "../Core/Logger.mqh"
#include "../Core/Utils.mqh"

//====================================================================
// CLASS: CATRFilter
//====================================================================
class CATRFilter
  {
private:
   int      m_handle;
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int      m_period;
   bool     m_ready;
   CLogger *m_logger;

public:
   CATRFilter()
     {
      m_handle    = INVALID_HANDLE;
      m_ready     = false;
      m_period    = 0;
      m_timeframe = PERIOD_CURRENT;
      m_logger    = NULL;
     }

   ~CATRFilter()
     {
      Release();
     }

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
            m_logger.Error("CATRFilter::Init failed - period must be > 0");
         m_ready = false;
         return false;
        }

      m_handle = iATR(m_symbol, m_timeframe, m_period);

      if(m_handle == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat("CATRFilter::Init failed - iATR handle invalid for %s period=%d", m_symbol, m_period));
         m_ready = false;
         return false;
        }

      m_ready = true;
      return true;
     }

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
   // Returns the current ATR value (in price units) at the given shift.
   //-----------------------------------------------------------------
   bool GetValue(const int shift, double &outValue)
     {
      outValue = 0.0;

      if(!m_ready || m_handle == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Debug("CATRFilter::GetValue called before Init/after Release");
         return false;
        }

      double buffer[];
      ArraySetAsSeries(buffer, true);

      int copied = CopyBuffer(m_handle, 0, shift, 1, buffer);
      if(copied <= 0)
        {
         if(m_logger != NULL)
            m_logger.Debug(StringFormat("CATRFilter::GetValue CopyBuffer failed, shift=%d, error=%d", shift, GetLastError()));
         return false;
        }

      outValue = buffer[0];
      return true;
     }

   //-----------------------------------------------------------------
   // Returns the current ATR value converted to points (broker points,
   // not pips) for easy comparison against InpAtrMinPoints/MaxPoints.
   //-----------------------------------------------------------------
   bool GetValuePoints(const int shift, double &outPoints)
     {
      double raw;
      if(!GetValue(shift, raw))
        {
         outPoints = 0.0;
         return false;
        }

      outPoints = CUtils::PriceToPoints(m_symbol, raw);
      return true;
     }

   //-----------------------------------------------------------------
   // Core filter gate: returns true if current ATR (points) is within
   // [minPoints, maxPoints]. If ATR data is unavailable, returns false
   // (fail-safe: no entry when volatility state is unknown).
   //-----------------------------------------------------------------
   bool IsVolatilityAcceptable(const double minPoints, const double maxPoints, double &outAtrPoints)
     {
      outAtrPoints = 0.0;

      if(!GetValuePoints(1, outAtrPoints))
         return false;

      if(outAtrPoints < minPoints)
        {
         if(m_logger != NULL)
            m_logger.Debug(StringFormat("ATR filter blocked entry - ATR too low (%.1f < %.1f pts)", outAtrPoints, minPoints));
         return false;
        }

      if(maxPoints > 0.0 && outAtrPoints > maxPoints)
        {
         if(m_logger != NULL)
            m_logger.Debug(StringFormat("ATR filter blocked entry - ATR too high (%.1f > %.1f pts)", outAtrPoints, maxPoints));
         return false;
        }

      return true;
     }
  };

#endif // __GHR_ATRFILTER_MQH__
