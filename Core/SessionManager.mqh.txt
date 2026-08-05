//+------------------------------------------------------------------+
//|                                             SessionManager.mqh   |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Small, focused module answering ONE question: "is trading     |
//|   allowed right now based on the session filter?" Kept separate |
//|   from SignalEngine so session logic can be reused (e.g. by      |
//|   RecoveryEngine to decide whether to even allow a recovery      |
//|   layer outside session hours) without duplicating hour-range    |
//|   logic.                                                          |
//+------------------------------------------------------------------+
#ifndef __GHR_SESSIONMANAGER_MQH__
#define __GHR_SESSIONMANAGER_MQH__

#include "../Config/Inputs.mqh"
#include "Utils.mqh"
#include "Logger.mqh"

//====================================================================
// CLASS: CSessionManager
//====================================================================
class CSessionManager
  {
private:
   bool     m_enabled;
   int      m_startHour;
   int      m_endHour;
   CLogger *m_logger;

public:
   CSessionManager()
     {
      m_enabled   = false;
      m_startHour = 0;
      m_endHour   = 24;
      m_logger    = NULL;
     }

   //-----------------------------------------------------------------
   void Init(CLogger *logger)
     {
      m_logger    = logger;
      m_enabled   = InpUseSessionFilter;
      m_startHour = InpSessionStartHour;
      m_endHour   = InpSessionEndHour;

      if(m_enabled && (m_startHour < 0 || m_startHour > 23 || m_endHour < 0 || m_endHour > 23))
        {
         if(m_logger != NULL)
            m_logger.Warning("CSessionManager::Init - session hours out of range [0-23], filter disabled defensively");
         m_enabled = false;
        }
     }

   //-----------------------------------------------------------------
   // Returns true if trading is currently allowed by the session
   // filter. If the filter is disabled, always returns true (no
   // restriction).
   //-----------------------------------------------------------------
   bool IsTradingAllowed()
     {
      if(!m_enabled)
         return true;

      bool allowed = CUtils::IsWithinHourRange(m_startHour, m_endHour);

      if(!allowed && m_logger != NULL)
         m_logger.Debug(StringFormat("CSessionManager - outside session hours [%02d:00-%02d:00]", m_startHour, m_endHour));

      return allowed;
     }

   bool IsEnabled() const { return m_enabled; }
   int  GetStartHour() const { return m_startHour; }
   int  GetEndHour() const { return m_endHour; }
  };

#endif // __GHR_SESSIONMANAGER_MQH__
