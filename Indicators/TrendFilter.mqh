//+------------------------------------------------------------------+
//|                                                TrendFilter.mqh   |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Aggregates the optional trend-confirmation filters (EMA200,   |
//|   SMA200, Multi-Timeframe EMA) into a single decision point.    |
//|   SignalEngine asks ONE question — "does the wider trend        |
//|   confirm this proposed direction?" — without needing to know   |
//|   which individual filters are enabled or how each one works.   |
//|                                                                  |
//|   Each filter is independently toggleable via Inputs.mqh. A     |
//|   disabled filter is treated as "no opinion" (does not block).  |
//|   All ENABLED filters must agree with the proposed direction    |
//|   for Confirm() to return true.                                  |
//+------------------------------------------------------------------+
#ifndef __GHR_TRENDFILTER_MQH__
#define __GHR_TRENDFILTER_MQH__

#include "../Config/Inputs.mqh"
#include "../Core/Logger.mqh"
#include "EMAFilter.mqh"
#include "SMAEngine.mqh"

//====================================================================
// CLASS: CTrendFilter
//====================================================================
class CTrendFilter
  {
private:
   string      m_symbol;
   CLogger    *m_logger;

   CEMAFilter  m_ema200;      // EMA200 filter (current timeframe)
   CSMAEngine  m_sma200;      // SMA200 filter (current timeframe)
   CEMAFilter  m_mtfEma;      // Higher timeframe EMA (MTF confirmation)

   bool        m_ema200Enabled;
   bool        m_sma200Enabled;
   bool        m_mtfEnabled;

public:
   CTrendFilter()
     {
      m_logger        = NULL;
      m_ema200Enabled = false;
      m_sma200Enabled = false;
      m_mtfEnabled    = false;
     }

   //-----------------------------------------------------------------
   // Initializes only the sub-filters that are enabled in Inputs.mqh.
   // Returns false if any ENABLED filter fails to initialize (a
   // disabled filter never causes a failure).
   //-----------------------------------------------------------------
   bool Init(const string symbol, const ENUM_TIMEFRAMES chartTimeframe, CLogger *logger)
     {
      m_symbol = symbol;
      m_logger = logger;

      bool allOk = true;

      m_ema200Enabled = InpUseEma200Filter;
      if(m_ema200Enabled)
        {
         if(!m_ema200.InitTrendEma(symbol, chartTimeframe, InpEma200Period, logger))
           {
            if(m_logger != NULL)
               m_logger.Error("CTrendFilter::Init failed - EMA200 sub-filter init error");
            allOk = false;
           }
        }

      m_sma200Enabled = InpUseSma200Filter;
      if(m_sma200Enabled)
        {
         if(!m_sma200.Init(symbol, chartTimeframe, InpSma200Period, logger))
           {
            if(m_logger != NULL)
               m_logger.Error("CTrendFilter::Init failed - SMA200 sub-filter init error");
            allOk = false;
           }
        }

      m_mtfEnabled = InpUseMtfFilter;
      if(m_mtfEnabled)
        {
         if(!m_mtfEma.InitTrendEma(symbol, InpMtfTimeframe, InpMtfEmaPeriod, logger))
           {
            if(m_logger != NULL)
               m_logger.Error("CTrendFilter::Init failed - MTF sub-filter init error");
            allOk = false;
           }
        }

      return allOk;
     }

   void Release()
     {
      if(m_ema200Enabled)
         m_ema200.Release();
      if(m_mtfEnabled)
         m_mtfEma.Release();
      // CSMAEngine releases its own handle in its destructor
     }

   //-----------------------------------------------------------------
   // Checks whether the proposed direction is confirmed by ALL
   // currently enabled trend sub-filters.
   //
   // proposedDirection : the direction SignalEngine wants to take
   //                      (from cross detection or trend bias)
   // outConfirmed       : true if every enabled filter agrees
   //
   // Returns false if any ENABLED filter's data could not be read
   // (fail-safe — treat unreadable data as "do not enter").
   //-----------------------------------------------------------------
   bool Confirm(const ENUM_TRADE_DIRECTION proposedDirection, bool &outConfirmed)
     {
      outConfirmed = true;

      if(proposedDirection == DIRECTION_NONE)
        {
         outConfirmed = false;
         return true;
        }

      //--- EMA200 filter: close price must be on the correct side of EMA200
      if(m_ema200Enabled)
        {
         double emaValue;
         if(!m_ema200.GetTrendEmaValue(1, emaValue))
           {
            if(m_logger != NULL)
               m_logger.Debug("CTrendFilter::Confirm - EMA200 data unavailable, blocking entry");
            outConfirmed = false;
            return false;
           }

         double closePrice = iClose(m_symbol, PERIOD_CURRENT, 1);
         bool aligned = (proposedDirection == DIRECTION_BUY) ? (closePrice > emaValue) : (closePrice < emaValue);

         if(!aligned)
           {
            if(m_logger != NULL)
               m_logger.Debug("CTrendFilter::Confirm - blocked by EMA200 filter");
            outConfirmed = false;
            return true;
           }
        }

      //--- SMA200 filter: close price must be on the correct side of SMA200
      if(m_sma200Enabled)
        {
         double smaValue;
         if(!m_sma200.GetValue(1, smaValue))
           {
            if(m_logger != NULL)
               m_logger.Debug("CTrendFilter::Confirm - SMA200 data unavailable, blocking entry");
            outConfirmed = false;
            return false;
           }

         double closePrice = iClose(m_symbol, PERIOD_CURRENT, 1);
         bool aligned = (proposedDirection == DIRECTION_BUY) ? (closePrice > smaValue) : (closePrice < smaValue);

         if(!aligned)
           {
            if(m_logger != NULL)
               m_logger.Debug("CTrendFilter::Confirm - blocked by SMA200 filter");
            outConfirmed = false;
            return true;
           }
        }

      //--- Multi-Timeframe filter: higher timeframe trend bias must agree
      if(m_mtfEnabled)
        {
         ENUM_TRADE_DIRECTION mtfBias;
         if(!m_mtfEma.GetTrendBias(mtfBias))
           {
            if(m_logger != NULL)
               m_logger.Debug("CTrendFilter::Confirm - MTF data unavailable, blocking entry");
            outConfirmed = false;
            return false;
           }

         if(mtfBias != proposedDirection)
           {
            if(m_logger != NULL)
               m_logger.Debug("CTrendFilter::Confirm - blocked by Multi-Timeframe filter");
            outConfirmed = false;
            return true;
           }
        }

      // All enabled filters agreed (or none are enabled)
      outConfirmed = true;
      return true;
     }
  };

#endif // __GHR_TRENDFILTER_MQH__
