// Local request/status protocol; no network calls.
#ifndef __SQ_COT_PROTOCOL_MQH__
#define __SQ_COT_PROTOCOL_MQH__
#include <SqCOTStorage.mqh>
#define COT_REQUEST_FILE COT_CACHE_DIR "\\request.dat"
#define COT_STATUS_FILE COT_CACHE_DIR "\\status.dat"
#define COT_HEARTBEAT_FILE COT_CACHE_DIR "\\heartbeat.dat"
// Data-access setup help; the key is entered only in SqCOTService.
#define COT_QDM_LICENSE_URL "https://strategyquant.com/quantdatamanager/"
string COT_LicenseSetupMessage()
{
   return "QDM Data License is missing. Get a free QDM licence: "+COT_QDM_LICENSE_URL+
          " Enter the key in SqCOTService Inputs > QDM Data License, then restart the service.";
}
string g_cotServiceInstance="";
struct CotStatus
{
   string id,state,code,message;
   datetime updated;
};
string COT_Field(const string text,const string key)
{
   string lines[];
   int count=StringSplit(text,'\n',lines);
   string prefix=key+"=";
   for(int i=0;i<count;i++)
      if(StringFind(lines[i],prefix)==0) return COT_Trim(StringSubstr(lines[i],StringLen(prefix)));
   return "";
}
bool COT_ReadStatusUnlocked(CotStatus &status)
{
   string text;
   if(!COT_ReadText(COT_STATUS_FILE,text)) return false;
   status.id=COT_Field(text,"REQUEST_ID"); status.state=COT_Field(text,"STATUS");
   status.code=COT_Field(text,"ERROR_CODE"); status.message=COT_Field(text,"MESSAGE");
   status.updated=(datetime)StringToInteger(COT_Field(text,"UPDATED_AT"));
   return COT_SafeName(status.id) && status.state!="";
}
bool COT_ReadStatus(CotStatus &status)
{
   int lock=COT_Lock("queue");
   if(lock==INVALID_HANDLE) return false;
   bool ok=COT_ReadStatusUnlocked(status);
   FileClose(lock);
   return ok;
}
bool COT_WriteStatusUnlocked(const string id,const string state,const string code,const string message)
{
   string text="REQUEST_ID="+id+"\nSTATUS="+state+
                       "\nPROGRESS=-1\nERROR_CODE="+code+"\nMESSAGE="+message+
                       "\nUPDATED_AT="+IntegerToString((long)COT_NOW())+"\n";
   // Keep each result so a later request from another chart cannot hide it.
   if(!COT_WriteText(COT_CACHE_DIR+"\\status\\"+id+".dat",text)) return false;
   return COT_WriteText(COT_STATUS_FILE,text);
}
bool COT_ReadRequestStatus(const string id,CotStatus &status)
{
   if(!COT_SafeName(id)) return false;
   int lock=COT_Lock("queue");
   if(lock==INVALID_HANDLE) return false;
   string text;
   bool ok=COT_ReadText(COT_CACHE_DIR+"\\status\\"+id+".dat",text);
   FileClose(lock);
   if(!ok || COT_Field(text,"REQUEST_ID")!=id) return false;
   status.id=id; status.state=COT_Field(text,"STATUS");
   status.code=COT_Field(text,"ERROR_CODE"); status.message=COT_Field(text,"MESSAGE");
   status.updated=(datetime)StringToInteger(COT_Field(text,"UPDATED_AT"));
   return true;
}
bool COT_WriteStatus(const string id,const string state,const string code,const string message)
{
   int lock=COT_Lock("queue");
   if(lock==INVALID_HANDLE) return false;
   bool ok=COT_WriteStatusUnlocked(id,state,code,message);
   FileClose(lock);
   return ok;
}
// A bounded lease covers the synchronous WebRequest / validation interval.
// Allow a short filesystem stall; an operation lease is still bounded.
bool COT_HeartbeatFresh(const string text,const long now)
{
   long ts=StringToInteger(COT_Field(text,"TIMESTAMP"));
   long lease=StringToInteger(COT_Field(text,"BUSY_UNTIL"));
   return COT_Field(text,"INSTANCE")!="" && ts>0 && ts<=now+2 &&
      ((now-ts<15) || (lease>=now && lease>=ts && lease-ts<=180));
}
bool COT_ServiceAvailable()
{
   static string last="";
   int lock=COT_Lock("heartbeat");
   // Contention must not manufacture an indefinitely healthy service.
   if(lock==INVALID_HANDLE) return COT_HeartbeatFresh(last,(long)COT_NOW());
   string text;
   bool read=COT_ReadText(COT_HEARTBEAT_FILE,text);
   FileClose(lock);
   if(read) last=text;
   return COT_HeartbeatFresh(last,(long)COT_NOW());
}
bool COT_Heartbeat(const int busySeconds=0)
{
   int lock=COT_Lock("heartbeat");
   if(lock==INVALID_HANDLE) return false;
   long now=(long)COT_NOW();
   bool ok=COT_WriteText(COT_HEARTBEAT_FILE,"TIMESTAMP="+IntegerToString(now)+
                         "\nBUSY_UNTIL="+IntegerToString(busySeconds>0?now+busySeconds:0)+
                         "\nINSTANCE="+g_cotServiceInstance+"\n");
   FileClose(lock);
   return ok;
}
string COT_NewRequestId()
{
   static uint serial=0;
   serial++;
   return IntegerToString((long)COT_NOW())+"-"+IntegerToString(ChartID())+"-"+
          IntegerToString((long)GetMicrosecondCount())+"-"+IntegerToString(serial);
}
bool COT_RequestUpdate(const string identifier,string &id,string &error)
{
   if(!COT_SafeName(identifier)) {error="Invalid COT identifier."; return false;}
   if(!COT_ServiceAvailable()) {error="Service not running. Start Navigator > Services > SqCOTService."; return false;}
   int lock=COT_Lock("queue");
   if(lock==INVALID_HANDLE) {error="Another COT request is being prepared. Retry shortly."; return false;}
   CotStatus status;
   if(COT_ReadStatusUnlocked(status) && (status.state=="REQUESTED" || status.state=="DOWNLOADING"))
   {FileClose(lock); error="Another COT update is in progress."; return false;}
   id=COT_NewRequestId();
   bool ok=COT_WriteStatusUnlocked(id,"REQUESTED","0","Waiting for COT service.");
   if(ok) ok=COT_WriteText(COT_REQUEST_FILE,"REQUEST_ID="+id+"\nACTION=UPDATE\nIDENTIFIER="+identifier+
                           "\nTIMESTAMP="+IntegerToString((long)COT_NOW())+"\n");
   if(!ok)
   {
      FileDelete(COT_REQUEST_FILE,COT_FILE_SCOPE); FileDelete(COT_REQUEST_FILE+".tmp",COT_FILE_SCOPE);
      COT_WriteStatusUnlocked(id,"ERROR","ERROR_FILE_WRITE","Cannot create update request.");
      error="Cannot create update request in FILE_COMMON.";
   }
   FileClose(lock);
   return ok;
}
void COT_CancelQueued(const string id)
{
   int lock=COT_Lock("queue");
   if(lock==INVALID_HANDLE) return;
   CotStatus status;
   if(COT_ReadStatusUnlocked(status) && status.id==id && status.state=="REQUESTED")
   {
      FileDelete(COT_REQUEST_FILE,COT_FILE_SCOPE); FileDelete(COT_REQUEST_FILE+".tmp",COT_FILE_SCOPE);
      COT_WriteStatusUnlocked(id,"ERROR","ERROR_CANCELLED","Queued update cancelled.");
   }
   FileClose(lock);
}
bool COT_ValidSeriesList(string text)
{
   string ids[]; int n=StringSplit(text,',',ids);
   if(n<1 || n>COT_MAX_SERIES) return false;
   for(int i=0;i<n;i++) if(!COT_SafeName(ids[i])) return false;
   return true;
}
// Subscription metadata only. Credentials are never written by this protocol.
bool COT_Register(const string client,string series,string &error)
{
   if(!COT_SafeName(client) || !COT_ValidSeriesList(series)) {error="Invalid registration."; return false;}
   int lock=COT_Lock("registration");
   if(lock==INVALID_HANDLE) {error="Registration busy."; return false;}
   StringToUpper(series);
   bool ok=COT_WriteText(COT_CACHE_DIR+"\\clients\\"+client+".dat",
      "CLIENT="+client+"\nSERIES="+series+"\nTIMESTAMP="+IntegerToString((long)COT_NOW())+"\n");
   FileClose(lock); if(!ok) error="Cannot register COT client."; return ok;
}
void COT_Unregister(const string client)
{
   if(!COT_SafeName(client)) return;
   int lock=COT_Lock("registration"); if(lock==INVALID_HANDLE) return;
   FileDelete(COT_CACHE_DIR+"\\clients\\"+client+".dat",COT_FILE_SCOPE);
   FileClose(lock);
}
#endif
