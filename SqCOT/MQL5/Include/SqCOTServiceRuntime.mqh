// Service runtime shared with the isolated fault-injection tester.
#ifndef __SQ_COT_SERVICE_RUNTIME_MQH__
#define __SQ_COT_SERVICE_RUNTIME_MQH__
#include <SqCOTDownloader.mqh>
#include <SqCOTScheduler.mqh>
#include <SqCOTNotifications.mqh>
#include <SqCOTMaintenance.mqh>
#include <SqCOTSymbolMap.mqh>
#ifndef COT_PROCESS_UPDATE
#define COT_PROCESS_UPDATE ProcessUpdateRequest
#endif
input string DownloadUrl=COT_DEFAULT_URL;
input int DownloadTimeoutMs=30000;
input bool AutoUpdateEnabled=true;
input(name="QDM Data License") string ServiceLicenseKey=""; // Free QDM licence: https://strategyquant.com/quantdatamanager/
input string RequiredSeries="GC_52W,6E_52W,ES_52W";
input int ReleaseHourPrague=21; // First Friday probe, Europe/Prague time
input int ProviderLagMinutes=0;
input int ReportGraceMinutes=120; // Existing report can be used during this window
input int SchedulerCheckSeconds=60;
input int AvailabilityAlertDelayMinutes=120;
input int NetworkAlertAfterFailures=3;
input bool NotifyPopup=true;
input bool NotifyPush=false;
input int AlertCooldownHours=6;
CotJobState Job;
CCOTJobWriter JobWriter;
CCOTExpectedCache ExpectedCache;
CCOTHeartbeatWriter HeartbeatWriter;
string ActiveLicense="",LastPrintedState="";
ulong LastCheck=0;
ulong LastMappingCheck=0;
string LastMappingError="";
bool PolicyReady=false;
string ScheduleMode="WEEKLY";
int DataReady=0;
bool RefreshServicePolicy()
{
   int lock=COT_Lock("policy");if(lock==INVALID_HANDLE) {PolicyReady=false;return false;}
   string policy=COT_WeeklyPolicyText(ReleaseHourPrague,ProviderLagMinutes,ReportGraceMinutes),old;
   string path=COT_CACHE_DIR+"\\policy.dat";
   bool ok=COT_ReadText(path,old) && old==policy;
   if(!ok)ok=COT_WriteText(path,policy);
   // Remove only the former service-generated shared file; historical exports stay immutable.
   string obsolete=COT_CACHE_DIR+"\\calendar.csv";
   if(ok && FileIsExist(obsolete,COT_FILE_SCOPE) && !FileDelete(obsolete,COT_FILE_SCOPE))
      Print("[SQ COT] Obsolete shared schedule file could not be removed; it is ignored.");
   FileClose(lock);PolicyReady=ok;
   g_cotReleaseHour=ReleaseHourPrague;g_cotProviderLag=ProviderLagMinutes;
   g_cotGraceMinutes=ReportGraceMinutes;
   return ok;
}
int ServiceReadiness(const string series,const long now,const long expected,const bool force=false)
{
   DataReady=ExpectedCache.Check(series,expected,GetTickCount64(),force,true,now);
   return DataReady;
}

void PublishHealth()
{
   // A separate timestamp describes scheduler progress even while the cache is unchanged.
   string text="SCHEMA=2\nTIMESTAMP="+IntegerToString((long)COT_NOW())+
      "\nINSTANCE="+g_cotServiceInstance+"\nSTATE="+Job.state+"\nERROR="+Job.error+
      "\nAUTO_UPDATE="+IntegerToString(AutoUpdateEnabled?1:0)+
      "\nSCHEDULE_MODE=WEEKLY\nDATA_READY="+IntegerToString(DataReady)+
      "\nEXPECTED_REPORT="+IntegerToString(Job.expected)+
      "\nNEXT_ATTEMPT="+IntegerToString(Job.nextAttempt)+
      "\nHEARTBEAT_FAILURES="+IntegerToString(HeartbeatWriter.Failures())+"\n";
   if(!COT_WriteText(COT_CACHE_DIR+"\\health.dat",text))
      Print("[SQ COT] Cannot publish health status; check shared-folder access and disk space.");
}
void CheckMapping()
{
   string error;
   if(!COT_MapSync(error) && error!=LastMappingError)
   {
      Print("[SQ COT MAPPING] ",error);
      COT_Notify("mapping-"+COT_MapHash(error),error,NotifyPopup,NotifyPush,AlertCooldownHours*3600);
   }
   LastMappingError=error;LastMappingCheck=GetTickCount64();
}
void PublishJob()
{
   if(!JobWriter.Save(Job)) Print("[SQ COT] Cannot persist scheduler state; retaining last valid cache.");
   string summary=Job.state+" "+Job.error;
   if(summary!=LastPrintedState) {Print("[SQ COT] ",summary);LastPrintedState=summary;}
}
void NotifyIssue(const string category,const string message)
{
   string key=IntegerToString(Job.expected)+"-"+category;
   Job.alertKey=key;PublishJob();
   COT_Notify(key,message,NotifyPopup,NotifyPush,AlertCooldownHours*3600);
}
void RecoverAlert()
{
   if(Job.alertKey=="") return;
   if(COT_Notify("recovery-"+Job.alertKey,"Expected COT data is available again.",NotifyPopup,NotifyPush,31536000) || (!NotifyPopup && !NotifyPush))
      Job.alertKey="";
}
string SubscribedSeries()
{
   string result=RequiredSeries;StringToUpper(result);
   int lock=COT_Lock("registration");if(lock==INVALID_HANDLE) return result;
   string name;long h=FileFindFirst(COT_CACHE_DIR+"\\clients\\*.dat",name,COT_FILE_SCOPE);
   if(h!=INVALID_HANDLE)
   {
      do
      {
         string text,path=COT_CACHE_DIR+"\\clients\\"+name;
         if(!COT_ReadText(path,text)) continue;
         long age=(long)COT_NOW()-StringToInteger(COT_Field(text,"TIMESTAMP"));
         if(age<0 || age>300) {FileDelete(path,COT_FILE_SCOPE);continue;}
         string series=COT_Field(text,"SERIES"),parts[];
         if(!COT_ValidSeriesList(series)) continue;
         int n=StringSplit(series,',',parts);
         for(int i=0;i<n;i++) if(StringFind(","+result+",",","+parts[i]+",")<0)
            result+=(result==""?"":",")+parts[i];
      }while(FileFindNext(h,name));
      FileFindClose(h);
   }
   FileClose(lock);return result;
}
void RunUpdate(const string id,const string series,string license)
{
   if(!PolicyReady)
   {COT_WriteStatus(id,"ERROR","POLICY_UNAVAILABLE","Repair shared policy storage before updating.");return;}
   long now=(long)COT_NOW();Job.job=id;Job.state="DOWNLOADING";Job.error="";Job.lastAttempt=now;
   Job.nextAttempt=now+300;
   if(!JobWriter.Save(Job) || !COT_WriteStatus(id,"DOWNLOADING","0","Downloading and validating COT data."))
   {
      COT_JobFailure(Job,"ERROR_FILE_WRITE",now);
      COT_WriteStatus(id,"ERROR","ERROR_FILE_WRITE","Cannot persist update intent/status. Retrying without replacing the cache.");
      PublishJob();return;
   }
   string code,error;
   bool ok=COT_PROCESS_UPDATE(id,series,license,DownloadUrl,DownloadTimeoutMs,code,error);
   license="";now=(long)COT_NOW();
   long target,tradeExpected,due,next;
   COT_WeeklyExpectation(now,ReleaseHourPrague,ProviderLagMinutes,ReportGraceMinutes,target,tradeExpected,due,next);
   Job.expected=target;
   if(ok)
   {
      Job.lastChecked=now;Job.failures=0;Job.error="";
      bool fresh=ServiceReadiness(series,now,tradeExpected,true)==1;
      bool complete=ExpectedCache.Check(series,target,GetTickCount64(),false,true,now)==1;
      Job.state=complete?"IDLE":(fresh?"WAITING_NEW_REPORT":"REPORT_LATE");
      Job.nextAttempt=complete?MathMin(next,now+86400):now+COT_MissingRetrySeconds(now-due);
      COT_WriteStatus(id,"SUCCESS",code,complete?"Expected COT report is available.":"Source checked; the new weekly report is still unavailable.");
      if(complete)RecoverAlert();
      else if(!fresh && now-due>=MathMax(ReportGraceMinutes,AvailabilityAlertDelayMinutes)*60)
         NotifyIssue("REPORT_LATE","Expected COT report is missing. New entries are blocked; retry is scheduled.");
   }
   else
   {
      COT_JobFailure(Job,code,now);
      Job.nextAttempt+=(long)(GetTickCount64()%31); // bounded retry jitter, persisted with intent
      if(g_cotRetryAfterSeconds>0) Job.nextAttempt=MathMax(Job.nextAttempt,now+g_cotRetryAfterSeconds);
      COT_WriteStatus(id,"ERROR",code,error);
      if(Job.state=="CONFIG_BLOCKED" || Job.failures>=NetworkAlertAfterFailures) NotifyIssue(code,error);
   }
   CheckMapping();PublishJob();COT_Heartbeat();
}
bool ProcessManual()
{
   int lock=COT_Lock("queue");if(lock==INVALID_HANDLE) return false;
   CotStatus status;string request;
   bool queued=COT_ReadStatusUnlocked(status) && status.state=="REQUESTED";
   bool present=queued && COT_ReadText(COT_REQUEST_FILE,request);
   if(queued && !present) COT_WriteStatusUnlocked(status.id,"ERROR","ERROR_INVALID_REQUEST","Queued request file is missing or unreadable.");
   if(!present) {FileClose(lock);return false;}
   string id=COT_Field(request,"REQUEST_ID"),series=COT_Field(request,"IDENTIFIER");
   long age=(long)COT_NOW()-StringToInteger(COT_Field(request,"TIMESTAMP"));
   bool valid=id==status.id && COT_SafeName(id) && COT_SafeName(series) &&
      COT_Field(request,"ACTION")=="UPDATE" && age>=0 && age<=300;
   bool removed=FileDelete(COT_REQUEST_FILE,COT_FILE_SCOPE);request="";
   if(!valid || !removed)
   {COT_WriteStatusUnlocked(status.id,"ERROR","ERROR_INVALID_REQUEST","Invalid, expired or unreadable request.");FileClose(lock);return false;}
   if(ActiveLicense=="")
   {COT_WriteStatusUnlocked(id,"ERROR","CREDENTIALS_REQUIRED",COT_LicenseSetupMessage());FileClose(lock);return false;}
   if((long)COT_NOW()-Job.lastAttempt<60)
   {COT_WriteStatusUnlocked(id,"ERROR","ERROR_COOLDOWN","An update was just attempted. Wait one minute.");FileClose(lock);return false;}
   bool claimed=COT_WriteStatusUnlocked(id,"DOWNLOADING","0","Request accepted.");FileClose(lock);
   if(!claimed) return false;
   RunUpdate(id,series,ActiveLicense);return true;
}
void CheckSchedule()
{
   if(!AutoUpdateEnabled) {Job.state="AUTO_DISABLED";PublishJob();return;}
   string series=SubscribedSeries();long now=(long)COT_NOW(),target,tradeExpected,due,next;
   if(!PolicyReady)
   {Job.state="POLICY_ERROR";Job.error="POLICY_UNAVAILABLE";NotifyIssue(Job.error,"Cannot publish weekly policy. Check shared-folder access.");return;}
   if(!COT_WeeklyExpectation(now,ReleaseHourPrague,ProviderLagMinutes,ReportGraceMinutes,target,tradeExpected,due,next))
   {Job.state="POLICY_ERROR";Job.error="TIME_INVALID";PublishJob();return;}
   bool expectationChanged=Job.expected!=target;Job.expected=target;
   if(series=="") {Job.state="WAITING_CLIENTS";PublishJob();return;}
   // Report missing unattended credentials now, even when last week's data is current.
   if(ActiveLicense=="") {Job.state="WAITING_CREDENTIALS";Job.error="CREDENTIALS_REQUIRED";NotifyIssue(Job.error,COT_LicenseSetupMessage());return;}
   int readiness=ServiceReadiness(series,now,tradeExpected);
   if(readiness<0) return; // A reader/writer holding the lock is not missing data.
   int complete=ExpectedCache.Check(series,target,GetTickCount64(),false,true,now);
   if(complete<0)return;
   if(Job.state=="CONFIG_BLOCKED") {NotifyIssue(Job.error,"COT update is blocked: "+Job.error+". Correct configuration and restart service.");return;}
   if(complete==1)
   {
      if(Job.state=="BACKOFF" && now<Job.nextAttempt){PublishJob();return;}
      if(Job.state!="IDLE" || expectationChanged || Job.nextAttempt<=0 || Job.nextAttempt>next)
         Job.nextAttempt=MathMin(next,MathMax(now,Job.lastChecked+86400));
      Job.state="IDLE";Job.error="";RecoverAlert();
      if(now<Job.nextAttempt){PublishJob();return;}
   }
   else if(Job.state!="BACKOFF")
   {
      if(Job.state=="IDLE" || expectationChanged || Job.nextAttempt<=0)
         Job.nextAttempt=MathMax(now,Job.lastAttempt+60);
      Job.state=readiness==1?"WAITING_NEW_REPORT":"REPORT_LATE";
      Job.error=readiness==1?"":"EXPECTED_REPORT_MISSING";
      if(readiness!=1 && now-due>=MathMax(ReportGraceMinutes,AvailabilityAlertDelayMinutes)*60)
         NotifyIssue("REPORT_LATE","Expected COT report is missing. New entries are blocked; retry is scheduled.");
   }
   if(now<Job.lastAttempt) {Job.nextAttempt=now+300;Job.lastAttempt=now;PublishJob();return;}
   if(now<Job.nextAttempt) {PublishJob();return;}
   RunUpdate(COT_NewRequestId(),series,ActiveLicense);
}
void RecoverRequest()
{
   CotStatus s;if(!COT_ReadStatus(s) || s.state!="DOWNLOADING") return;
   string text,version,ids[];datetime updated;
   bool committed=COT_ReadText(COT_METADATA_FILE,text) && COT_ParseMetadata(text,version,updated,ids) && version==s.id;
   COT_WriteStatus(s.id,committed?"SUCCESS":"ERROR",committed?"RECOVERED":"ERROR_INTERRUPTED",
      committed?"Committed generation recovered.":"Interrupted update; scheduler will retry.");
}
void COT_RunService()
{
   if(!COT_ValidEndpoint(DownloadUrl) || DownloadTimeoutMs<1000 || DownloadTimeoutMs>120000 ||
       SchedulerCheckSeconds<1 || SchedulerCheckSeconds>3600 || ReleaseHourPrague<0 || ReleaseHourPrague>23 ||
       ProviderLagMinutes<0 || ProviderLagMinutes>1440 || ReportGraceMinutes<0 || ReportGraceMinutes>4320 ||
      AvailabilityAlertDelayMinutes<0 || AvailabilityAlertDelayMinutes>10080 ||
      NetworkAlertAfterFailures<1 || NetworkAlertAfterFailures>100000 || AlertCooldownHours<1 || AlertCooldownHours>8760 ||
      (RequiredSeries!="" && !COT_ValidSeriesList(RequiredSeries)))
   {Print("[SQ COT] Invalid service inputs.");return;}
   int serviceLock=COT_Lock("service");
   if(serviceLock==INVALID_HANDLE && COT_ServiceAvailable())
   {Print("[SQ COT] Another service already owns the shared cache.");return;}
   if(serviceLock==INVALID_HANDLE) Print("[SQ COT] Waiting for service ownership/shared-folder access; retrying every 30 seconds.");
   while(serviceLock==INVALID_HANDLE && !IsStopped())
   {Sleep(30000);serviceLock=COT_Lock("service");}
   if(serviceLock==INVALID_HANDLE) return;
   ActiveLicense=COT_Trim(ServiceLicenseKey);g_cotServiceInstance=COT_NewRequestId();
   g_cotProviderLag=ProviderLagMinutes;
   COT_LoadJob(Job);if(Job.state=="CONFIG_BLOCKED") {Job.state="IDLE";Job.nextAttempt=0;}
   RefreshServicePolicy();
    RecoverRequest();CheckMapping();Print("[SQ COT] Service 4.2.5 started.");
   while(!IsStopped())
   {
      ulong tick=GetTickCount64();
      HeartbeatWriter.Tick(tick);
      bool manual=ProcessManual();
      if(tick>=LastMappingCheck && tick-LastMappingCheck>=60000)CheckMapping();
      if(manual || LastCheck==0 || tick-LastCheck>=(ulong)SchedulerCheckSeconds*1000)
      {
         RefreshServicePolicy();CheckSchedule();PublishHealth();LastCheck=GetTickCount64();
         if(HeartbeatWriter.Failures()>0) COT_Notify("heartbeat-write","Heartbeat cannot be written. Service is retrying; inspect disk space and shared-folder access.",NotifyPopup,NotifyPush,AlertCooldownHours*3600);
      }
      Sleep(250);
   }
   ActiveLicense="";Job.state="STOPPED";PublishHealth();
   int heartbeatLock=COT_Lock("heartbeat");
   if(heartbeatLock!=INVALID_HANDLE) {FileDelete(COT_HEARTBEAT_FILE,COT_FILE_SCOPE);FileClose(heartbeatLock);}
   FileClose(serviceLock);Print("[SQ COT] Service stopped.");
}


#endif
