//+------------------------------------------------------------------+
//|                                                 EMAFilter.mqh    |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Wraps EMA indicator handles and exposes the two building       |
//|   blocks the SignalEngine needs:                                 |
//|     1) Cross detection between a fast and a slow EMA             |
//|     2) Trend bias (price vs a single EMA, e.g. EMA200)           |
//|                                                                  |
//|   One instance of this class can manage BOTH a fast+slow pair    |
//|   (for ENTRY_WAIT_CROSS) and a single trend EMA (for             |
//|   ENTRY_CURRENT_TREND / EMA200 filter), depending on how many     |
//|   handles are initialized.                                       |
//+------------------------------------------------------------------+
#ifndef __GHR_EMAFILTER_MQH__
#define __GHR_EMAFILTER_MQH__

#include "../Core/Logger.mqh"
#include "../Config/Inputs.mqh"

//====================================================================
// CLASS: CEMAFilter
//====================================================================
class CEMAFilter
  {
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   CLogger *m_logger;

   // Fast/Slow pair (for cross detection)
   int      m_fastHandle;
   int      m_slowHandle;
   int      m_fastPeriod;
   int      m_slowPeriod;
   bool     m_crossReady;

   // Single EMA (for trend bias / EMA200 filter)
   int      m_trendHandle;
   int      m_trendPeriod;
   bool     m_trendReady;

   //-----------------------------------------------------------------
   bool CopyOne(const int handle, const int shift, double &outValue)
     {
      outValue = 0.0;
      if(handle == INVALID_HANDLE)
         return false;

      double buffer[];
      ArraySetAsSeries(buffer, true);

      int copied = CopyBuffer(handle, 0, shift, 1, buffer);
      if(copied <= 0)
         return false;

      outValue = buffer[0];
      return true;
     }

public:
   CEMAFilter()
     {
      m_fastHandle  = INVALID_HANDLE;
      m_slowHandle  = INVALID_HANDLE;
      m_trendHandle = INVALID_HANDLE;
      m_fastPeriod  = 0;
      m_slowPeriod  = 0;
      m_trendPeriod = 0;
      m_crossReady  = false;
      m_trendReady  = false;
      m_logger      = NULL;
      m_timeframe   = PERIOD_CURRENT;
     }

   ~CEMAFilter()
     {
      Release();
     }

   //-----------------------------------------------------------------
   // Initializes the fast/slow EMA pair used for ENTRY_WAIT_CROSS.
   //-----------------------------------------------------------------
   bool InitCrossPair(const string symbol, const ENUM_TIMEFRAMES timeframe,
                       const int fastPeriod, const int slowPeriod, CLogger *logger)
     {
      m_symbol    = symbol;
      m_timeframe = timeframe;
      m_logger    = logger;
      m_fastPeriod = fastPeriod;
      m_slowPeriod = slowPeriod;

      if(fastPeriod <= 0 || slowPeriod <= 0 || fastPeriod >= slowPeriod)
        {
         if(m_logger != NULL)
            m_logger.Error("CEMAFilter::InitCrossPair failed - invalid fast/slow period combination");
         m_crossReady = false;
         return false;
        }

      m_fastHandle = iMA(m_symbol, m_timeframe, m_fastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_slowHandle = iMA(m_symbol, m_timeframe, m_slowPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Error("CEMAFilter::InitCrossPair failed - could not create iMA handle(s)");
         m_crossReady = false;
         return false;
        }

      m_crossReady = true;
      return true;
     }

   //-----------------------------------------------------------------
   // Initializes a single EMA used for trend bias / EMA200 filter.
   //-----------------------------------------------------------------
   bool InitTrendEma(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      const int period, CLogger *logger)
     {
      m_symbol    = symbol;
      m_timeframe = timeframe;
      m_logger    = logger;
      m_trendPeriod = period;

      if(period <= 0)
        {
         if(m_logger != NULL)
            m_logger.Error("CEMAFilter::InitTrendEma failed - period must be > 0");
         m_trendReady = false;
         return false;
        }

      m_trendHandle = iMA(m_symbol, m_timeframe, m_trendPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(m_trendHandle == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Error("CEMAFilter::InitTrendEma failed - could not create iMA handle");
         m_trendReady = false;
         return false;
        }

      m_trendReady = true;
      return true;
     }

   //-----------------------------------------------------------------
   void Release()
     {
      if(m_fastHandle != INVALID_HANDLE)  { IndicatorRelease(m_fastHandle);  m_fastHandle  = INVALID_HANDLE; }
      if(m_slowHandle != INVALID_HANDLE)  { IndicatorRelease(m_slowHandle);  m_slowHandle  = INVALID_HANDLE; }
      if(m_trendHandle != INVALID_HANDLE) { IndicatorRelease(m_trendHandle); m_trendHandle = INVALID_HANDLE; }
      m_crossReady = false;
      m_trendReady = false;
     }

   bool IsCrossReady() const { return m_crossReady; }
   bool IsTrendReady()  const { return m_trendReady; }

   //-----------------------------------------------------------------
   // Detects a fresh EMA cross between the two most recently CLOSED
   // bars (shift 1 vs shift 2), avoiding repainting on the forming bar.
   //
   // outDirection = DIRECTION_BUY  if fast crossed ABOVE slow
   // outDirection = DIRECTION_SELL if fast crossed BELOW slow
   // outDirection = DIRECTION_NONE if no fresh cross occurred
   //
   // Returns false if indicator data could not be retrieved.
   //-----------------------------------------------------------------
   bool DetectCross(ENUM_TRADE_DIRECTION &outDirection)
     {
      outDirection = DIRECTION_NONE;

      if(!m_crossReady)
        {
         if(m_logger != NULL)
            m_logger.Debug("CEMAFilter::DetectCross called before InitCrossPair");
         return false;
        }

      double fastPrev, fastPrevPrev, slowPrev, slowPrevPrev;

      if(!CopyOne(m_fastHandle, 1, fastPrev))     return false;
      if(!CopyOne(m_fastHandle, 2, fastPrevPrev)) return false;
      if(!CopyOne(m_slowHandle, 1, slowPrev))     return false;
      if(!CopyOne(m_slowHandle, 2, slowPrevPrev)) return false;

      bool wasBelow = (fastPrevPrev < slowPrevPrev);
      bool isAbove  = (fastPrev > slowPrev);

      bool wasAbove = (fastPrevPrev > slowPrevPrev);
      bool isBelow  = (fastPrev < slowPrev);

      if(wasBelow && isAbove)
         outDirection = DIRECTION_BUY;
      else if(wasAbove && isBelow)
         outDirection = DIRECTION_SELL;
      else
         outDirection = DIRECTION_NONE;

      return true;
     }

   //-----------------------------------------------------------------
   // Determines trend bias by comparing the last CLOSED bar's close
   // price against the trend EMA value at the same shift.
   //
   // outDirection = DIRECTION_BUY  if price is above the EMA (bullish)
   // outDirection = DIRECTION_SELL if price is below the EMA (bearish)
   //-----------------------------------------------------------------
   bool GetTrendBias(ENUM_TRADE_DIRECTION &outDirection)
     {
      outDirection = DIRECTION_NONE;

      if(!m_trendReady)
        {
         if(m_logger != NULL)
            m_logger.Debug("CEMAFilter::GetTrendBias called before InitTrendEma");
         return false;
        }

      double emaValue;
      if(!CopyOne(m_trendHandle, 1, emaValue))
         return false;

      double closePrice = iClose(m_symbol, m_timeframe, 1);
      if(closePrice <= 0.0)
         return false;

      outDirection = (closePrice > emaValue) ? DIRECTION_BUY : DIRECTION_SELL;
      return true;
     }

   //-----------------------------------------------------------------
   // Raw accessor for the trend EMA value (used by EMA200 filter to
   // simply confirm/deny a direction rather than generate one).
   //-----------------------------------------------------------------
   bool GetTrendEmaValue(const int shift, double &outValue)
     {
      if(!m_trendReady)
         return false;
      return CopyOne(m_trendHandle, shift, outValue);
     }
  };

#endif // __GHR_EMAFILTER_MQH__
