// Local maintenance only. No network requests or chart operations.
#ifndef __SQ_COT_MAINTENANCE_MQH__
#define __SQ_COT_MAINTENANCE_MQH__
#include <SqCOTProtocol.mqh>
#include <SqCOTPit.mqh>

// Recover from transient heartbeat lock/write failures without exiting the service.
class CCOTHeartbeatWriter
{
private:
   ulong m_last;
   int m_failures;
   bool m_attempted;
public:
   CCOTHeartbeatWriter() {m_last=0;m_failures=0;m_attempted=false;}
   int Failures() const {return m_failures;}
   bool Tick(const ulong tick)
   {
      ulong interval=(ulong)(m_failures==0?2000:MathMin(30000,2000*m_failures));
      if(m_attempted && tick>=m_last && tick-m_last<interval) return m_failures==0;
      m_last=tick;m_attempted=true;
      if(COT_Heartbeat())
      {
         if(m_failures>0) Print("[SQ COT] Heartbeat writes recovered.");
         m_failures=0;return true;
      }
      m_failures=MathMin(m_failures+1,10000);
      if(m_failures==1 || m_failures%30==0)
         Print("[SQ COT] Heartbeat write unavailable; retrying. Check shared-folder access and free disk space.");
      return false;
   }
};

class CCOTPollGate
{
private:
   ulong m_last;
   bool m_checked;
public:
   CCOTPollGate() {m_last=0;m_checked=false;}
   bool Due(const ulong tick,const bool force=false)
   {
      if(!force && m_checked && tick>=m_last && tick-m_last<60000) return false;
      m_last=tick;m_checked=true;return true;
   }
};

// Immutable generations need a full read only when their identity/requirements
// change. Stat checks catch deletion/truncation; an hourly full read also catches
// damage that preserves file size and modification time. Never cache lock failure.
class CCOTExpectedCache
{
private:
   string m_signature;
   ulong m_validated;
   bool m_checked,m_ready;
   int m_reads;
   long m_oldest,m_newest;
public:
   CCOTExpectedCache() {m_signature="";m_validated=0;m_checked=false;m_ready=false;m_reads=0;}
   int FullChecks() const {return m_reads;}
   // -1 = busy (defer, do not download), 0 = missing/invalid, 1 = expected report.
   int Check(const string series,const long expected,const ulong tick,const bool force=false,const bool checkPit=false,const long asOf=0)
   {
      if(expected<=0 || !COT_ValidSeriesList(series)) return 0;
      int lock=COT_Lock("cache");if(lock==INVALID_HANDLE) return -1;
      string text,version,ids[],required[];datetime updated;
      bool metadata=COT_ReadText(COT_METADATA_FILE,text) && COT_ParseMetadata(text,version,updated,ids);
      if(!metadata) {m_checked=false;FileClose(lock);return 0;}
      string directory=COT_CACHE_DIR+"\\generations\\"+version+"\\";
      string signature=version+"|"+series+"|"+(checkPit?"|PIT":"");
      int n=StringSplit(series,',',required);
      for(int i=0;i<n;i++)
      {
         string path=directory+required[i]+".bin";
         bool exists=FileIsExist(path,COT_FILE_SCOPE);
         signature+="|"+IntegerToString(exists?FileGetInteger(path,FILE_SIZE,COT_FILE_SCOPE==FILE_COMMON):-1)+
            ":"+IntegerToString(exists?FileGetInteger(path,FILE_MODIFY_DATE,COT_FILE_SCOPE==FILE_COMMON):-1);
         if(checkPit)
         {
            path=directory+required[i]+".pit";exists=FileIsExist(path,COT_FILE_SCOPE);
            signature+="|"+IntegerToString(exists?FileGetInteger(path,FILE_SIZE,COT_FILE_SCOPE==FILE_COMMON):-1)+
               ":"+IntegerToString(exists?FileGetInteger(path,FILE_MODIFY_DATE,COT_FILE_SCOPE==FILE_COMMON):-1);
         }
      }
      if(!force && m_checked && signature==m_signature && tick>=m_validated && tick-m_validated<3600000)
      {FileClose(lock);return m_ready && m_oldest>=expected && (asOf<=0 || m_newest<=asOf)?1:0;}
      bool ok=true;m_reads++;m_oldest=LONG_MAX;m_newest=0;
      for(int i=0;ok && i<n;i++)
      {
         bool active=false;for(int k=0;k<ArraySize(ids);k++)if(ids[k]==required[i])active=true;
         if(!active){ok=false;break;}
         CotBinRecord rows[];string error;
         ok=COT_ReadBin(directory+required[i]+".bin",rows,error);
         if(ok && checkPit)
         {CotPitRecord pit[];ok=COT_ReadPit(directory+required[i]+".pit",pit) && COT_MatchesPit(rows,pit);}
         if(ok)
         {
            CotBinRecord r=rows[ArraySize(rows)-1];
            m_oldest=MathMin(m_oldest,r.date);m_newest=MathMax(m_newest,r.date);
            ok=r.date>0 && COT_ValueValid(r.cpihedg) && COT_ValueValid(r.ctihedg) &&
               COT_ValueValid(r.cpispec) && COT_ValueValid(r.ctispec) && COT_ValueValid(r.cpismall);
         }
      }
      m_signature=signature;m_validated=tick;m_checked=true;m_ready=ok;
      FileClose(lock);return ok && m_oldest>=expected && (asOf<=0 || m_newest<=asOf)?1:0;
   }
};
#endif
