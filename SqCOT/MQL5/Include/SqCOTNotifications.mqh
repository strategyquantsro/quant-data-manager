#ifndef __SQ_COT_NOTIFICATIONS_MQH__
#define __SQ_COT_NOTIFICATIONS_MQH__
#include <SqCOTProtocol.mqh>
#include <SqCOTPit.mqh>
// Shared persisted claim: failed delivery is retried at most once per minute.
bool COT_Notify(const string eventKey,const string message,const bool popup,const bool push,const int cooldown=21600)
{
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION) || (!popup && !push)) return false;
   uchar bytes[]; int n=StringToCharArray(eventKey,bytes,0,WHOLE_ARRAY,CP_UTF8); ArrayResize(bytes,n-1);
   string key=COT_Hash(bytes); if(key=="") return false;
   int lock=COT_Lock("notifications"); if(lock==INVALID_HANDLE) return false;
   string path=COT_CACHE_DIR+"\\alerts\\"+key+".dat",old;
   COT_ReadText(path,old); long now=(long)COT_NOW();
   long shown=StringToInteger(COT_Field(old,"POPUP")),sent=StringToInteger(COT_Field(old,"PUSH"));
   long attempt=StringToInteger(COT_Field(old,"ATTEMPT"));
   string gate; COT_ReadText(COT_CACHE_DIR+"\\alerts\\rate.dat",gate);
   long lastAny=StringToInteger(COT_Field(gate,"ATTEMPT"));
   bool canPopup=popup && (shown==0 || now<shown || now-shown>=cooldown);
   bool canPush=push && (sent==0 || now<sent || now-sent>=cooldown) &&
      (now<attempt || now-attempt>=60) && (now<lastAny || now-lastAny>=10);
   if(!canPopup && !canPush)
   {FileClose(lock);return (!popup || shown>0) && (!push || sent>0);}
   if(canPopup) shown=now;
   if(canPush) attempt=now;
   bool saved=COT_WriteText(path,"POPUP="+IntegerToString(shown)+"\nPUSH="+IntegerToString(sent)+"\nATTEMPT="+IntegerToString(attempt)+"\n");
   if(canPush) saved=saved && COT_WriteText(COT_CACHE_DIR+"\\alerts\\rate.dat","ATTEMPT="+IntegerToString(now)+"\n");
   if(!saved) {FileClose(lock); return false;}
   string msg=StringSubstr("SQ COT: "+message,0,255);
   if(canPopup) Alert(msg);
   bool delivered=canPush && SendNotification(msg);
   if(delivered) COT_WriteText(path,"POPUP="+IntegerToString(shown)+"\nPUSH="+IntegerToString(now)+"\nATTEMPT="+IntegerToString(attempt)+"\n");
   FileClose(lock);
   if(canPush && !delivered) Print("[SQ COT] Push delivery failed; check MT5 Notifications. Event ",eventKey);
   // Recovery is complete only after every requested channel has succeeded.
   return (!popup || shown>0) && (!push || delivered || sent>0);
}
#endif
