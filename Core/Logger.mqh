//+------------------------------------------------------------------+
//|                                                      Logger.mqh  |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Centralized logging. Every trading action funnels through     |
//|   this class so log format stays consistent, and CSV logging    |
//|   can be toggled without touching any other module.             |
//|                                                                  |
//| CSV COLUMNS:                                                    |
//|   Time, Symbol, Ticket, Layer, Action, Price, Lot, Profit,      |
//|   Floating, Retcode, Description                                |
//+------------------------------------------------------------------+
#ifndef __GHR_LOGGER_MQH__
#define __GHR_LOGGER_MQH__

#include "../Config/Inputs.mqh"
#include "Utils.mqh"

//====================================================================
// CLASS: CLogger
//====================================================================
class CLogger
  {
private:
   bool     m_enabled;
   bool     m_csvEnabled;
   bool     m_verbose;
   string   m_csvFileName;
   int      m_csvHandle;
   bool     m_headerWritten;

   //-----------------------------------------------------------------
   // Opens (or re-opens) the CSV file in append mode and writes the
   // header row once per file lifetime.
   //-----------------------------------------------------------------
   bool EnsureCsvOpen()
     {
      if(!m_csvEnabled)
         return false;

      if(m_csvHandle != INVALID_HANDLE)
         return true;

      m_csvHandle = FileOpen(m_csvFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');

      if(m_csvHandle == INVALID_HANDLE)
        {
         PrintFormat("[GoldHedgeRecovery][Logger] Failed to open CSV file '%s'. Error: %d",
                     m_csvFileName, GetLastError());
         return false;
        }

      // Move to end of file to append instead of overwrite
      FileSeek(m_csvHandle, 0, SEEK_END);

      if(FileSize(m_csvHandle) == 0)
        {
         FileWrite(m_csvHandle, "Time", "Symbol", "Ticket", "Layer", "Action",
                    "Price", "Lot", "Profit", "Floating", "Retcode", "Description");
        }

      return true;
     }

public:
   //-----------------------------------------------------------------
   CLogger()
     {
      m_enabled       = true;
      m_csvEnabled    = false;
      m_verbose       = false;
      m_csvFileName   = "GoldHedgeRecovery_Log.csv";
      m_csvHandle     = INVALID_HANDLE;
      m_headerWritten = false;
     }

   ~CLogger()
     {
      if(m_csvHandle != INVALID_HANDLE)
         FileClose(m_csvHandle);
     }

   //-----------------------------------------------------------------
   // Must be called once from OnInit() before any logging happens.
   //-----------------------------------------------------------------
   void Init()
     {
      m_enabled     = InpEnableLogging;
      m_csvEnabled  = InpEnableCsvLogging;
      m_verbose     = InpVerboseLogging;
      m_csvFileName = InpCsvFileName;

      if(m_csvEnabled)
         EnsureCsvOpen();
     }

   void Deinit()
     {
      if(m_csvHandle != INVALID_HANDLE)
        {
         FileClose(m_csvHandle);
         m_csvHandle = INVALID_HANDLE;
        }
     }

   //-----------------------------------------------------------------
   // General purpose info log (Experts tab only).
   //-----------------------------------------------------------------
   void Info(const string message)
     {
      if(!m_enabled)
         return;
      PrintFormat("[GoldHedgeRecovery][INFO] %s | %s", CUtils::FormatDateTime(TimeCurrent()), message);
     }

   //-----------------------------------------------------------------
   // Debug log — only prints when InpVerboseLogging = true.
   //-----------------------------------------------------------------
   void Debug(const string message)
     {
      if(!m_enabled || !m_verbose)
         return;
      PrintFormat("[GoldHedgeRecovery][DEBUG] %s | %s", CUtils::FormatDateTime(TimeCurrent()), message);
     }

   //-----------------------------------------------------------------
   // Warning log — always printed regardless of verbose setting.
   //-----------------------------------------------------------------
   void Warning(const string message)
     {
      if(!m_enabled)
         return;
      PrintFormat("[GoldHedgeRecovery][WARN] %s | %s", CUtils::FormatDateTime(TimeCurrent()), message);
     }

   //-----------------------------------------------------------------
   // Error log — always printed regardless of verbose setting.
   //-----------------------------------------------------------------
   void Error(const string message)
     {
      if(!m_enabled)
         return;
      PrintFormat("[GoldHedgeRecovery][ERROR] %s | %s", CUtils::FormatDateTime(TimeCurrent()), message);
     }

   //-----------------------------------------------------------------
   // Full structured trade action log — writes to Experts tab AND
   // CSV (if enabled). This is the primary log entry point called
   // by TradeEngine / RecoveryEngine / PositionManager / RiskEngine.
   //
   // action    : e.g. "OPEN", "CLOSE", "MODIFY", "REJECT", "EMERGENCY_CLOSE"
   // symbol    : trading symbol
   // ticket    : position/order ticket (0 if not yet known)
   // layer     : recovery layer index (0 = initial)
   // price     : execution/close price
   // lot       : lot size involved
   // profit    : realized profit (0 if not applicable)
   // floating  : current floating P/L at time of log
   // retcode   : trade server return code (0 if not applicable)
   //-----------------------------------------------------------------
   void LogTrade(const string action, const string symbol, const ulong ticket,
                 const int layer, const double price, const double lot,
                 const double profit, const double floating, const int retcode)
     {
      string desc = (retcode == 0) ? "" : CUtils::RetcodeDescription(retcode);

      if(m_enabled)
        {
         PrintFormat("[GoldHedgeRecovery][TRADE] %s | %s | Ticket=%I64u Layer=%d Price=%.2f Lot=%.2f "
                     "Profit=%.2f Floating=%.2f Retcode=%d (%s)",
                     CUtils::FormatDateTime(TimeCurrent()), action, ticket, layer, price, lot,
                     profit, floating, retcode, desc);
        }

      if(m_csvEnabled && EnsureCsvOpen())
        {
         FileWrite(m_csvHandle,
                    CUtils::FormatDateTime(TimeCurrent()),
                    symbol,
                    IntegerToString((long)ticket),
                    IntegerToString(layer),
                    action,
                    DoubleToString(price, 2),
                    DoubleToString(lot, 2),
                    DoubleToString(profit, 2),
                    DoubleToString(floating, 2),
                    IntegerToString(retcode),
                    desc);
         FileFlush(m_csvHandle);
        }
     }
  };

#endif // __GHR_LOGGER_MQH__
