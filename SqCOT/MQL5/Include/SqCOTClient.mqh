// Public API 1: no HTTP, no credential persistence, no trading operations.
#ifndef __SQ_COT_CLIENT_MQH__
#define __SQ_COT_CLIENT_MQH__
#include <SqCOTReader.mqh>
#include <SqCOTPit.mqh>
#include <SqCOTSchedule.mqh>
#include <SqCOTNotifications.mqh>
#include <SqCOTSymbolMap.mqh>
#include <SqCOTFreshness.mqh>
#include <SqCOTSnapshot.mqh>
enum ENUM_COT_DATA_STATUS {COT_MISSING=0,COT_CURRENT=1,COT_INVALID=2,COT_TIME_UNKNOWN=3,COT_STALE=4,COT_SCHEDULE_UNKNOWN=5};
enum ENUM_COT_POLL {COT_POLL_ERROR=-1,COT_POLL_BUSY=-2,COT_POLL_UNCHANGED=0,COT_POLL_CHANGED=1};
struct SqCOTSnapshot
{
   string seriesId,reportId,errorCode;
   double values[5];
   long reportDate,availableAtUtc,generation,expectedReport,evaluatedAtUtc;
   int revision;
   ENUM_COT_DATA_STATUS dataStatus;
   bool calendarFallback;
   int maxReportAgeDays;
};
string COT_StatusName(const ENUM_COT_DATA_STATUS s)
{
   if(s==COT_CURRENT) return "CURRENT"; if(s==COT_STALE) return "STALE";
   if(s==COT_INVALID) return "INVALID"; if(s==COT_TIME_UNKNOWN) return "TIME_UNKNOWN";
   if(s==COT_SCHEDULE_UNKNOWN) return "SCHEDULE_UNKNOWN"; return "MISSING";
}
class CSqCOTClient
{
private:
   string m_series,m_version,m_directory,m_client,m_pinned,m_error;
   CotPitRecord m_rows[];
   long m_generation,m_firstAvailable,m_registered,m_started;
   ulong m_lastPoll,m_lastValidation;
   string m_fileSignature;
   int m_lag;
   bool m_ready,m_tester,m_popup,m_push;
   string m_profile;
   string m_profileData;
   CotRelease m_calendar[];
   long m_calendarUntil;
   CotFreshnessPolicy m_policy;
   CCOTSymbolMap m_map;
   CotMapResult m_mapping;
   bool m_auto,m_autoBound;
   string m_symbol,m_server,m_acceptedHash,m_mapStatus;
   int m_weeks;
public:
    CSqCOTClient() {m_auto=false;m_generation=0;m_ready=false;m_tester=false;m_popup=false;m_push=false;m_lastPoll=0;m_lastValidation=0;m_fileSignature="";m_registered=0;m_lag=0;m_profile="";m_started=0;m_policy.releaseHour=21;m_policy.lagMinutes=0;m_policy.graceMinutes=120;m_policy.legacy=false;m_policy.allowFallback=false;m_policy.maxAgeDays=14;}
   string Error() const {return m_error;}
   string Series() const {return m_series;}
   long Generation() const {return m_generation;}
   string DatasetKey() const {return m_directory;}
   void SetNotifications(const bool popup,const bool push) {m_popup=popup;m_push=push;}
   void Mapping(CotMapResult &result) {MappingReady();result=m_mapping;result.status=m_mapStatus;}
   bool MappingReady()
   {
      if(!m_auto)return true;
      if(!m_map.Resolve(m_symbol,m_server,m_weeks,m_mapping)){m_mapStatus=m_mapping.status;return false;}
      if(!m_autoBound && !m_tester)
      {
         string symbol=m_symbol,server=m_server;int weeks=m_weeks;
         return OpenAutoLive(symbol,server,weeks) && m_mapStatus=="RESOLVED";
      }
      m_mapStatus=m_mapping.hash==m_acceptedHash && m_mapping.series==m_series?"RESOLVED":"CONFIG_CHANGED";
      return m_mapStatus=="RESOLVED";
   }
   bool OpenAutoLive(const string symbol,const string server,const int weeks=52)
   {
      Close();if(weeks!=52 && weeks!=156){m_error="INVALID_HORIZON";return false;}
      if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)){m_error="SNAPSHOT_REQUIRED";return false;}
      CotMapResult r;bool resolved=m_map.Resolve(symbol,server,weeks,r,true);
      // Preserve a recoverable AUTO client before the first licensed download.
      if(resolved && !OpenLive(r.series))return false;
      m_auto=true;m_symbol=symbol;m_server=server;m_weeks=weeks;m_mapping=r;
      m_autoBound=resolved;
      m_acceptedHash=r.hash;m_mapStatus=r.status;m_error=resolved?"":r.status;
      return true;
   }
   bool OpenAutoSnapshot(const string symbol,const string server,const int weeks,const string snapshotId,const string brokerProfile)
   {
      Close();if(!COT_SafeName(snapshotId) || (weeks!=52 && weeks!=156)){m_error="INVALID_SNAPSHOT";return false;}
      string dir=COT_CACHE_DIR+"\\snapshots\\"+snapshotId;CotMapResult r;
      if(!m_map.OpenSnapshot(dir,symbol,server,weeks,r)){m_error=m_map.Error()==""?r.status:m_map.Error();return false;}
      if(!OpenSnapshot(r.series,snapshotId,brokerProfile))return false;
      // OpenSnapshot resets state; re-pin the mapping with the same validated files.
      if(!m_map.OpenSnapshot(dir,symbol,server,weeks,r)){m_ready=false;m_error="MAPPING_SNAPSHOT_INVALID";return false;}
      m_auto=true;m_symbol=symbol;m_server=server;m_weeks=weeks;m_mapping=r;
      m_autoBound=true;
      m_acceptedHash=r.hash;m_mapStatus=r.status;return true;
   }
   bool OpenLive(string series)
   {
      Close(); StringToUpper(series); if(!COT_SafeName(series)) {m_error="INVALID_SERIES";return false;}
      if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {m_error="SNAPSHOT_REQUIRED";return false;}
      m_series=series; m_client=COT_NewRequestId(); m_started=(long)COT_NOW(); m_pinned="";m_tester=false;
      Poll(true); return true; // Missing cache is recoverable; not an initialization failure.
   }
   bool OpenSnapshot(string series,const string snapshotId,const string brokerProfile)
   {
      Close(); StringToUpper(series);
      if(!COT_SafeName(series) || !COT_SafeName(snapshotId) || brokerProfile=="") {m_error="INVALID_SNAPSHOT";return false;}
      m_series=series;m_tester=true;m_pinned=COT_CACHE_DIR+"\\snapshots\\"+snapshotId;m_profile=brokerProfile;
      if(brokerProfile!="UTC" && StringFind(brokerProfile,"UTC+")!=0 && StringFind(brokerProfile,"UTC-")!=0)
      {
         string digest;uchar bytes[];
         string file=m_pinned+"\\profiles\\"+brokerProfile+".csv";
         if(!COT_SafeName(brokerProfile) || !COT_ReadText(file,m_profileData) ||
            !COT_ReadBytes(file,bytes) || !COT_ReadText(file+".sha256",digest) || COT_Trim(digest)!=COT_Hash(bytes))
         {m_error="SNAPSHOT_PROFILE_MISSING";return false;}
      }
      return Poll(true)==COT_POLL_CHANGED;
   }
   bool BarUtc(const datetime bar,const string profile,long &utc)
   {
      if(m_tester && profile!=m_profile) return false;
      if(m_tester && m_profileData!="") return COT_ProfileUtc(bar,m_profileData,utc);
      return COT_BarUtc(bar,profile,utc);
   }
   bool Expected(const long now,long &expected,long &due,long &next)
   {
       bool known;CotFreshnessPolicy policy;
       return Schedule(now,expected,due,next,known,policy) && known;
   }
   bool Schedule(const long now,long &expected,long &due,long &next,bool &known,CotFreshnessPolicy &policy)
   {
      known=false;expected=0;due=0;next=0;policy=m_policy;
       if(m_tester)
       {
          if(policy.legacy)
          {known=COT_LegacyExpected(now,policy.lagMinutes,expected,due,next,m_calendar,m_calendarUntil);return true;}
          long target;
          known=COT_WeeklyExpectation(now,policy.releaseHour,policy.lagMinutes,policy.graceMinutes,target,expected,due,next);
          return known;
       }
      int policyLock=COT_Lock("policy");if(policyLock==INVALID_HANDLE) return false;
       string text;
       if(!COT_ReadText(COT_CACHE_DIR+"\\policy.dat",text) || !COT_ParseFreshnessPolicy(text,policy) || policy.legacy)
       {FileClose(policyLock);return false;}
       FileClose(policyLock);
       long target;
       known=COT_WeeklyExpectation(now,policy.releaseHour,policy.lagMinutes,policy.graceMinutes,target,expected,due,next);
       return known;
   }
   bool NowUtc(long &now)
   {
      if(!m_tester) {now=(long)COT_NOW();return true;}
      if(!BarUtc(TimeCurrent(),m_profile,now)) {m_error="BROKER_TIME_UNKNOWN";return false;} return true;
   }
   ENUM_COT_POLL Poll(const bool force=false)
   {
      if(m_auto && !MappingReady()){m_error=m_mapStatus;return COT_POLL_ERROR;}
      if(m_series=="") return COT_POLL_ERROR;
      ulong tick=GetTickCount64();
      if(!force && tick-m_lastPoll<1000) return m_ready?COT_POLL_UNCHANGED:COT_POLL_ERROR;
      m_lastPoll=tick;
      if(!m_tester)
      {
         long now=(long)COT_NOW();
         if(now-m_registered>=60 || now<m_registered)
         {string err;if(COT_Register(m_client,m_series,err)) m_registered=now;}
         if(now-m_started>180 && !COT_ServiceAvailable())
            COT_Notify("service-offline","Service heartbeat expired. Start SqCOTService.",m_popup,m_push);
      }
      if(m_tester && m_ready) return COT_POLL_UNCHANGED; // pinned for complete run
      int lock=COT_Lock("cache");
      if(lock==INVALID_HANDLE) {m_error="CACHE_BUSY";return COT_POLL_BUSY;}
      string directory=m_pinned,version=m_pinned,runtime,pointer,ids[];datetime updated;
      bool ok=true;
      if(!m_tester)
      {
         ok=COT_ReadText(COT_METADATA_FILE,pointer) && COT_ParseMetadata(pointer,version,updated,ids);
         if(!ok) ok=COT_ReadText(COT_METADATA_FILE+".previous",pointer) && COT_ParseMetadata(pointer,version,updated,ids);
         directory=COT_CACHE_DIR+"\\generations\\"+version;
         bool active=false;for(int i=0;i<ArraySize(ids);i++)if(ids[i]==m_series)active=true;
         ok=ok && active; // Retained PIT files for retired markets are not live data.
      }
      string file=directory+"\\"+m_series+".pit";
      bool exists=FileIsExist(file,COT_FILE_SCOPE);
      string signature=version+"|"+IntegerToString(exists?FileGetInteger(file,FILE_SIZE,COT_FILE_SCOPE==FILE_COMMON):-1)+
         "|"+IntegerToString(exists?FileGetInteger(file,FILE_MODIFY_DATE,COT_FILE_SCOPE==FILE_COMMON):-1);
      if(ok && exists && version==m_version && m_ready && signature==m_fileSignature &&
         tick>=m_lastValidation && tick-m_lastValidation<3600000)
      {FileClose(lock);m_error="";return COT_POLL_UNCHANGED;}
      if(ok) ok=!FileIsExist(directory+"\\EXPORTING",COT_FILE_SCOPE) && COT_ReadText(directory+"\\runtime.dat",runtime) && COT_Field(runtime,"SCHEMA")=="2";
      CotFreshnessPolicy loadedPolicy={};if(ok) ok=COT_ParseFreshnessPolicy(runtime,loadedPolicy);
      long gen=StringToInteger(COT_Field(runtime,"GENERATION"));
      CotPitRecord rows[];
      if(ok) ok=gen>0 && gen<=9007199254740991 && COT_ReadPit(directory+"\\"+m_series+".pit",rows);
      // Snapshot exports carry an integrity hash for each file.
      if(ok && m_tester)
      {
         ok=COT_VerifySnapshotPolicy(directory,runtime);
         string digest; uchar bytes[];
         ok=ok && COT_ReadText(directory+"\\"+m_series+".sha256",digest) &&
            COT_ReadBytes(directory+"\\"+m_series+".pit",bytes) && COT_Trim(digest)==COT_Hash(bytes);
          if(ok && loadedPolicy.legacy && !COT_LoadLegacyCalendar(m_calendar,m_calendarUntil,directory+"\\calendar.csv"))
          {ArrayFree(m_calendar);m_calendarUntil=0;ok=loadedPolicy.allowFallback;}
      }
      FileClose(lock);
      if(!ok) {m_error="CACHE_INVALID_OR_MISSING";m_ready=false;m_generation=0;return COT_POLL_ERROR;}
      ArrayCopy(m_rows,rows);ArrayResize(m_rows,ArraySize(rows));
      m_firstAvailable=rows[0].available;
      for(int i=1;i<ArraySize(rows);i++) m_firstAvailable=MathMin(m_firstAvailable,rows[i].available);
      m_generation=gen;m_directory=directory;m_version=version;
      m_policy=loadedPolicy;
       m_lag=loadedPolicy.lagMinutes;
       if(m_lag<0 || m_lag>(loadedPolicy.legacy?10080:1440)){m_ready=false;m_error="INVALID_LAG";return COT_POLL_ERROR;}
      m_fileSignature=signature;m_lastValidation=tick;
      m_ready=true;m_error=""; return COT_POLL_CHANGED;
   }
   bool ReadAt(const long asOf,SqCOTSnapshot &s,const int reportShift=0)
   {
      ZeroMemory(s);s.seriesId=m_series;s.evaluatedAtUtc=asOf;s.dataStatus=COT_MISSING;
      for(int i=0;i<5;i++) s.values[i]=EMPTY_VALUE;
      if(!MappingReady()){s.dataStatus=COT_INVALID;s.errorCode=m_mapStatus;return false;}
      if(!m_ready || asOf<m_firstAvailable) {s.errorCode=m_error==""?"NOT_AVAILABLE_AT_TIME":m_error;return false;}
      int row=COT_PitAt(m_rows,asOf,reportShift);
      if(row<0) {s.errorCode="INSUFFICIENT_HISTORY";return false;}
      CotPitRecord r=m_rows[row]; s.reportDate=r.value.date;s.reportId=TimeToString((datetime)s.reportDate,TIME_DATE);
      s.availableAtUtc=r.available;s.revision=r.revision;s.generation=m_generation;
      s.values[0]=r.value.cpihedg;s.values[1]=r.value.ctihedg;s.values[2]=r.value.cpispec;
      s.values[3]=r.value.ctispec;s.values[4]=r.value.cpismall;
      for(int i=0;i<5;i++) if(!COT_ValueValid(s.values[i])) {s.dataStatus=COT_INVALID;s.errorCode="MISSING_FIELD";return false;}
      return AssessFreshness(asOf,s);
   }
   bool AssessFreshness(const long asOf,SqCOTSnapshot &s)
   {
      long expected,due,next;bool known;CotFreshnessPolicy policy;
      if(!Schedule(asOf,expected,due,next,known,policy) || (!known && !policy.allowFallback))
      {s.dataStatus=COT_SCHEDULE_UNKNOWN;s.errorCode="SCHEDULE_UNKNOWN";return true;}
       s.expectedReport=known?expected:0;s.calendarFallback=policy.legacy && !known;
       s.maxReportAgeDays=policy.legacy?policy.maxAgeDays:0;
      if(s.reportDate<=0 || s.reportDate>asOf)
      {s.dataStatus=COT_INVALID;s.errorCode="INVALID_REPORT_DATE";return false;}
      s.dataStatus=COT_ReportReady(s.reportDate,asOf,known,expected,policy)?COT_CURRENT:COT_STALE;
       s.errorCode=s.dataStatus==COT_STALE?(known?"EXPECTED_REPORT_MISSING":"REPORT_TOO_OLD"):
          (s.calendarFallback?"CALENDAR_FALLBACK":"");
      return true;
   }
   bool ReadLatest(SqCOTSnapshot &s)
   {
      Poll(); long now; if(!NowUtc(now)) {ZeroMemory(s);s.dataStatus=COT_TIME_UNKNOWN;return false;}
      return ReadAt(now,s);
   }
   bool ReadReport(const int shift,SqCOTSnapshot &s)
   {
      Poll();long now;if(!NowUtc(now)) return false;return ReadAt(now,s,shift);
   }
   bool ReadBar(const datetime bar,const string profile,SqCOTSnapshot &s)
   {
      Poll();long utc;if(!BarUtc(bar,profile,utc)) {ZeroMemory(s);s.dataStatus=COT_TIME_UNKNOWN;return false;}
      return ReadAt(utc,s);
   }
   bool CanTrade(const SqCOTSnapshot &s)
   {
      if(!MappingReady())return false;
      long now;if(!NowUtc(now) || !m_ready || s.seriesId!=m_series || s.generation!=m_generation ||
         s.availableAtUtc>now || s.evaluatedAtUtc>now || now-s.evaluatedAtUtc>60 || s.dataStatus!=COT_CURRENT) return false;
      SqCOTSnapshot checked=s;
      if(!AssessFreshness(now,checked) || checked.dataStatus!=COT_CURRENT) return false;
      for(int i=0;i<5;i++) if(!COT_ValueValid(s.values[i])) return false;
      return true;
   }
   void Close()
   {
      m_auto=false;m_map.Reset();m_mapStatus="";m_acceptedHash="";
      if(m_client!="") COT_Unregister(m_client);
      m_client="";m_series="";m_version="";m_directory="";m_pinned="";m_ready=false;m_generation=0;m_registered=0;m_lastPoll=0;
      m_fileSignature="";m_lastValidation=0;
      ArrayFree(m_rows);
      ArrayFree(m_calendar);m_calendarUntil=0;m_profileData="";m_profile="";
   }
};
// Callers retain their clients. No partial result is accepted across generations.
bool COT_ReadBatch(CSqCOTClient &clients[],SqCOTSnapshot &out[])
{
   int n=ArraySize(clients); if(n<1 || n>COT_MAX_SERIES) return false;
   ArrayResize(out,n); long generation=0;string dataset="";
   for(int i=0;i<n;i++)
   {
      if(!clients[i].ReadLatest(out[i]) || !clients[i].CanTrade(out[i])) return false;
      if(i==0) {generation=out[i].generation;dataset=clients[i].DatasetKey();}
      else if(out[i].generation!=generation || clients[i].DatasetKey()!=dataset) return false;
   }
   return true;
}
#endif
