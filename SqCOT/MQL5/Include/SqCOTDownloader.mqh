// Service-only downloader for the supplied cot.php contract.
// POST application/x-www-form-urlencoded license=... -> HTTP 200 application/zip.
#ifndef __SQ_COT_DOWNLOADER_MQH__
#define __SQ_COT_DOWNLOADER_MQH__
#include <SqCOTProtocol.mqh>
#include <SqCOTZip.mqh>
#include <SqCOTJson.mqh>
#include <SqCOTReader.mqh>
#include <SqCOTPit.mqh>
#include <SqCOTSchedule.mqh>
#include <SqCOTFreshness.mqh>
#include <SqCOTRetention.mqh>

string g_cotUpdateOutcome="";
int g_cotReleaseHour=21,g_cotProviderLag=0,g_cotGraceMinutes=120;
int g_cotRetryAfterSeconds=0;
string COT_Header(string headers,const string wanted)
{
   StringReplace(headers,"\r","");string lines[];int n=StringSplit(headers,'\n',lines);
   for(int i=0;i<n;i++) {int p=StringFind(lines[i],":");if(p<1)continue;string name=StringSubstr(lines[i],0,p);StringToLower(name);if(name==wanted)return COT_Trim(StringSubstr(lines[i],p+1));}
   return "";
}

#define COT_DEFAULT_URL "https://cdn.strategyquantcdn.com/cot.php"

string COT_FormEncode(const string text)
{
   uchar bytes[];
   int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   string encoded="";
   for(int i=0;i<n;i++)
   {
      uchar c=bytes[i];
      if((c>='A' && c<='Z') || (c>='a' && c<='z') || (c>='0' && c<='9') ||
         c=='-' || c=='_' || c=='.' || c=='~') encoded+=CharToString(c);
      else encoded+=StringFormat("%%%02X",(int)c);
   }
   return encoded;
}
bool COT_ValidEndpoint(const string url)
{
   return StringFind(url,"https://")==0 && StringLen(url)>8 && StringFind(url,"@")<0 &&
          StringFind(url,"\r")<0 && StringFind(url,"\n")<0 && StringFind(url," ")<0 &&
          StringFind(url,"#")<0;
}
string COT_Origin(const string url)
{
   int slash=StringFind(url,"/",8);
   return slash<0 ? url : StringSubstr(url,0,slash);
}
bool COT_ArchiveCacheIntact(const string directory,const string &ids[])
{
   for(int i=0;i<ArraySize(ids);i++)
      if(!COT_SeriesFilesValid(directory,ids[i])) return false;
   return ArraySize(ids)>0;
}
bool DownloadCOTData(const string endpoint,string license,const int timeoutMs,
                     uchar &archive[],string &code,string &error)
{
   if(!COT_ValidEndpoint(endpoint)) {code="ERROR_ENDPOINT"; error="Only a valid HTTPS endpoint is allowed."; return false;}
   char body[],response[];
   g_cotRetryAfterSeconds=0;
   string oldVersion,oldIds[],oldDirectory,oldRuntime;datetime oldUpdated;
   string knownHash="";
   if(COT_ReadSnapshot(oldVersion,oldUpdated,oldIds,oldDirectory) && COT_ReadText(oldDirectory+"\\runtime.dat",oldRuntime))
      knownHash=COT_Field(oldRuntime,"HASH");
   string form="license="+COT_FormEncode(license);
   // Do not accept an unchanged response when local files need repair.
   if(knownHash!="" && !COT_ArchiveCacheIntact(oldDirectory,oldIds)) knownHash="";
   if(StringLen(knownHash)==64) form+="&knownHash="+knownHash;
   int n=StringToCharArray(form,body,0,WHOLE_ARRAY,CP_UTF8);
   ArrayResize(body,n-1); // PHP body must not include the terminating NUL.
   string headers="Content-Type: application/x-www-form-urlencoded\r\nAccept: application/zip\r\n",replyHeaders;
   if(!COT_Heartbeat(timeoutMs/1000+15)) {code="ERROR_FILE_WRITE"; error="Cannot publish service heartbeat."; return false;}
   Print("[SQ COT] Downloading COT archive.");
   ResetLastError();
   int http=WebRequest("POST",endpoint,headers,timeoutMs,body,response,replyHeaders);
   int nativeError=GetLastError();
   ArrayInitialize(body,0); ArrayFree(body); license=""; form="";
   COT_Heartbeat(60);
   long retryAfter;
   if(COT_ParseLong(COT_Header(replyHeaders,"retry-after"),retryAfter)) g_cotRetryAfterSeconds=(int)MathMin(retryAfter,86400);
   if(IsStopped()) {code="ERROR_INTERRUPTED"; error="Service stopped during download."; return false;}
   if(http==-1)
   {
      if(nativeError==4014 || nativeError==5200)
      {
         code="ERROR_WEBREQUEST_NOT_ALLOWED";
         error="Enable WebRequest: add "+COT_Origin(endpoint)+" in Tools > Options > Expert Advisors > Allow WebRequest for listed URL.";
      }
      else if(nativeError==5202) {code="ERROR_TIMEOUT"; error="COT server connection timed out. Retry later.";}
      else {code="ERROR_NETWORK"; error="Unable to connect to COT server (MQL error "+IntegerToString(nativeError)+").";}
      return false;
   }
   Print("[SQ COT] HTTP ",http,"; received ",ArraySize(response)," bytes.");
   if(http==204 && StringLen(knownHash)==64 && COT_Header(replyHeaders,"x-cot-hash")==knownHash &&
      COT_Header(replyHeaders,"x-cot-result")=="unchanged")
   {ArrayFree(archive);code="UNCHANGED";return true;}
   if(http!=200)
   {
      code="HTTP_"+IntegerToString(http);
       if(http==400 || http==401 || http==403) error="Licence rejected or invalid request. Check QDM Data License in SqCOTService. Free QDM licence: "+COT_QDM_LICENSE_URL;
      else if(http==503) error="COT data or licence server is temporarily unavailable. Retry later.";
      else error="COT server returned HTTP "+IntegerToString(http)+".";
      return false; // Do not log response bodies, headers, URL queries or credentials.
   }
   int size=ArraySize(response);
   if(size<22 || size>67108864) {code="ERROR_RESPONSE_SIZE"; error="Empty, truncated or oversized COT archive."; return false;}
   ArrayResize(archive,size);
   ArrayCopy(archive,response);
   if(COT_U32(archive,0)!=0x04034b50) {code="ERROR_INVALID_RESPONSE"; error="Server did not return a ZIP archive."; return false;}
   string responseHash=COT_Header(replyHeaders,"x-cot-hash");
   if(responseHash!="" && COT_Hash(archive)!=responseHash) {code="ERROR_HASH_MISMATCH";error="Archive does not match server hash.";return false;}
   return true;
}

bool ValidateCOTData(const uchar &archive[],CotZipEntry &entries[],string &error)
{
   return COT_ZipDirectory(archive,entries,error);
}

// Each generation is immutable. Publish only one small pointer under cache.lock;
// keep the previous pointer for recovery if the terminal dies during FileMove.
bool COT_CommitMetadata(const string metadata,string &error)
{
   string version,ids[]; datetime updated;
   if(!COT_ParseMetadata(metadata,version,updated,ids)) {error="Invalid cache metadata."; return false;}
   int lock=INVALID_HANDLE;
   for(int i=0;i<20 && !IsStopped();i++)
   {
      lock=COT_Lock("cache");
      if(lock!=INVALID_HANDLE) break;
      Sleep(50);
   }
   if(lock==INVALID_HANDLE) {error="Cache is busy; retry update."; return false;}
   string old,oldVersion,oldIds[]; datetime oldTime;
   bool hasOld=COT_ReadText(COT_METADATA_FILE,old) && COT_ParseMetadata(old,oldVersion,oldTime,oldIds);
   if(!hasOld) hasOld=COT_ReadText(COT_METADATA_FILE+".previous",old) && COT_ParseMetadata(old,oldVersion,oldTime,oldIds);
   bool ok=true;
   if(hasOld) ok=COT_WriteText(COT_METADATA_FILE+".previous",old);
   if(ok) ok=COT_WriteText(COT_METADATA_FILE,metadata);
   if(ok)
   {
      string verify;
      ok=COT_ReadText(COT_METADATA_FILE,verify) && verify==metadata;
   }
   if(!ok && hasOld) COT_WriteText(COT_METADATA_FILE,old);
   if(!ok && !hasOld) FileDelete(COT_METADATA_FILE,COT_FILE_SCOPE);
   FileClose(lock);
   if(!ok) error="Cannot publish cache metadata; previous data retained.";
   return ok;
}

bool COT_StageSeries(const string directory,string id,const CotBinRecord &records[],
                     string &ids[],string &error)
{
   StringToUpper(id);
   if(!COT_SafeName(id)) {error="Invalid COT identifier in archive."; return false;}
   for(int k=0;k<ArraySize(ids);k++)
      if(ids[k]==id) {error="Duplicate COT identifier in archive: "+id; return false;}
   // Some new/discontinued contracts have no data for the selected lookback.
   // They are valid JSON entries, but must not be advertised as loadable series.
   if(ArraySize(records)==0) return true;
   if(ArraySize(ids)>=COT_MAX_SERIES) {error="Too many COT series in archive."; return false;}
   string tmp=directory+"\\"+id+".tmp",target=directory+"\\"+id+".bin";
   if(!COT_WriteBin(tmp,records,error)) return false;
   if(!FileMove(tmp,COT_FILE_SCOPE,target,COT_FILE_SCOPE)) {error="Cannot finalize COT series file."; return false;}
   int count=ArraySize(ids); ArrayResize(ids,count+1); ids[count]=id;
   return true;
}

bool COT_ImportJson(const uchar &data[],const string directory,string &ids[],string &error)
{
   int pos=0,size=ArraySize(data);
   if(size>=3 && data[0]==0xEF && data[1]==0xBB && data[2]==0xBF) pos=3;
   if(!COT_JsonTake(data,pos,'{',error)) return false;
   COT_JsonSpace(data,pos);
   string seen[];
   bool closed=false;
   if(pos<size && data[pos]=='}') {pos++; closed=true;}
   else while(pos<size)
   {
      if(IsStopped()) {error="Service stopped while importing COT JSON."; return false;}
      if(!COT_Heartbeat(60)) {error="Cannot update import heartbeat."; return false;}
      string id;
      if(!COT_JsonString(data,pos,id,error)) return false;
      StringToUpper(id);
      if(!COT_SafeName(id)) {error="Invalid series identifier in COT JSON."; return false;}
      int count=ArraySize(seen);
      if(count>=COT_MAX_SERIES) {error="Too many keys in COT JSON."; return false;}
      for(int i=0;i<count;i++)
         if(seen[i]==id) {error="Duplicate series identifier in COT JSON: "+id; return false;}
      ArrayResize(seen,count+1); seen[count]=id;
      if(!COT_JsonTake(data,pos,':',error)) return false;
      CotBinRecord records[];
      if(!COT_JsonSeries(data,pos,records,error))
      {error=id+": "+error; return false;}
      if(!COT_StageSeries(directory,id,records,ids,error)) return false;
      COT_JsonSpace(data,pos);
      if(pos<size && data[pos]=='}') {pos++; closed=true; break;}
      if(!COT_JsonTake(data,pos,',',error)) return false;
   }
   COT_JsonSpace(data,pos);
   if(!closed || pos!=size) {error="Incomplete COT JSON or trailing data."; return false;}
   Print("[SQ COT] Imported cot.json: ",ArraySize(seen)," keys, ",ArraySize(ids)," non-empty series.");
   return true;
}

bool SaveCOTData(const uchar &archive[],const CotZipEntry &entries[],const string requestId,
                 string requiredIdentifier,string &error)
{
   g_cotUpdateOutcome="";
   if(!COT_SafeName(requestId)) {error="Invalid generation identifier."; return false;}
   StringToUpper(requiredIdentifier);
   string oldVersion,oldIds[],oldDirectory,oldRuntime; datetime oldUpdated;
   ENUM_COT_SNAPSHOT_STATE previous=COT_ReadSnapshotState(oldVersion,oldUpdated,oldIds,oldDirectory);
   if(previous==COT_SNAPSHOT_BUSY) {error="Cache busy; retry import without replacing history.";return false;}
   if(previous==COT_SNAPSHOT_INVALID) {error="Cache metadata invalid; restore a verified pointer before importing.";return false;}
   bool haveOld=previous==COT_SNAPSHOT_READY;
   if(haveOld && !COT_ReadText(oldDirectory+"\\runtime.dat",oldRuntime))
      {error="Active cache has no v2 metadata; preserve it and use a fresh v2 cache."; return false;}
   string hash=COT_Hash(archive);
   if(hash=="") {error="Cannot hash archive."; return false;}
   string required[]; int requiredCount=StringSplit(requiredIdentifier,',',required);
   if(requiredCount<1) {error="No requested series."; return false;}
   for(int r=0;r<requiredCount;r++) if(!COT_SafeName(required[r])) {error="Invalid required series."; return false;}
   bool repair=haveOld && !COT_ArchiveCacheIntact(oldDirectory,oldIds);
   if(haveOld && !repair && COT_Field(oldRuntime,"HASH")==hash)
   {
      g_cotUpdateOutcome="UNCHANGED"; return true;
   }
   string directory=COT_CACHE_DIR+"\\generations\\"+requestId;
   // A request ID is never reused; existing files cannot be overwritten.
   if(FileIsExist(directory+"\\complete.dat",COT_FILE_SCOPE)) {error="Generation already exists."; return false;}
   string ids[];
   for(int i=0;i<ArraySize(entries);i++)
   {
      if(IsStopped()) {error="Service stopped before cache publication."; return false;}
      COT_Heartbeat(60);
      string name=entries[i].name;
      StringReplace(name,"\\","/");
      string parts[];
      int partsCount=StringSplit(name,'/',parts);
      string leaf=parts[partsCount-1],lower=leaf;
      StringToLower(lower);
      if(lower=="cot.json")
      {
         uchar json[];
         if(!COT_ZipExtract(archive,entries[i],json,error)) return false;
         if(!COT_ImportJson(json,directory,ids,error)) return false;
         continue;
      }
      if(StringLen(lower)<5 || StringSubstr(lower,StringLen(lower)-4)!=".csv") continue;
      string id=StringSubstr(leaf,0,StringLen(leaf)-4);
      uchar csv[];
      if(!COT_ZipExtract(archive,entries[i],csv,error)) return false;
      CotBinRecord records[];
      if(!COT_ParseCsv(CharArrayToString(csv,0,ArraySize(csv),CP_UTF8),records,error)) return false;
      if(!COT_StageSeries(directory,id,records,ids,error)) return false;
   }
   if(ArraySize(ids)==0) {error="ZIP contains no COT records in cot.json or CSV files."; return false;}
   // Acquisition publishes every usable market independently of client subscriptions.
   // Retired markets retain their revision files but are absent from the active catalog.
   string historyIds[];ArrayCopy(historyIds,oldIds);
   if(haveOld && FileIsExist(oldDirectory+"\\history.dat",COT_FILE_SCOPE))
   {
      string history,historyVersion;datetime historyTime;
      if(!COT_ReadText(oldDirectory+"\\history.dat",history) ||
         !COT_ParseMetadata(history,historyVersion,historyTime,historyIds) || historyVersion!=oldVersion)
      {error="Invalid retained history catalog.";return false;}
   }
   bool anyChanged=!haveOld || repair || ArraySize(ids)!=ArraySize(oldIds),newReport=!haveOld;
   for(int i=0;i<ArraySize(ids);i++)
   {
      bool active=false;for(int k=0;k<ArraySize(oldIds);k++)if(ids[i]==oldIds[k])active=true;
      if(!active)anyChanged=true;
   }
   for(int i=0;i<ArraySize(ids);i++)
   {
      CotBinRecord fresh[]; CotPitRecord old[],merged[];
      if(!COT_ReadBin(directory+"\\"+ids[i]+".bin",fresh,error)) return false;
      if(fresh[ArraySize(fresh)-1].date>(long)COT_NOW()) {error="Future report date."; return false;}
      bool existed=false;for(int k=0;k<ArraySize(historyIds);k++) if(historyIds[k]==ids[i]) existed=true;
      if(haveOld && existed && !COT_ReadPit(oldDirectory+"\\"+ids[i]+".pit",old))
      {error="Previous PIT history is missing or invalid. Restore a verified backup; observation times cannot be recreated.";return false;}
      if(!COT_Heartbeat(60)) {error="Cannot publish import heartbeat; retry scheduled.";return false;}
      bool changed;
      if(!COT_MergePit(fresh,old,(long)COT_NOW(),merged,changed,error)) return false;
      anyChanged=anyChanged || changed;
      if(ArraySize(old)==0 || fresh[ArraySize(fresh)-1].date>old[ArraySize(old)-1].value.date) newReport=true;
      if(!COT_WritePit(directory+"\\"+ids[i]+".pit",merged)) {error="Cannot write PIT revisions."; return false;}
   }
   string retained[];ArrayCopy(retained,ids);
   for(int k=0;k<ArraySize(historyIds);k++)
   {
      string id=historyIds[k];bool active=false;
      for(int i=0;i<ArraySize(ids);i++)if(ids[i]==id)active=true;
      if(active)continue;
      CotPitRecord history[];
      if(!COT_ReadPit(oldDirectory+"\\"+id+".pit",history) ||
         !COT_WritePit(directory+"\\"+id+".pit",history))
      {error="Cannot preserve retired series history: "+id;return false;}
      int n=ArraySize(retained);ArrayResize(retained,n+1);retained[n]=id;
   }
   string historyMetadata=requestId+"\n"+IntegerToString((long)COT_NOW())+"\n";
   for(int i=0;i<ArraySize(retained);i++)historyMetadata+=retained[i]+"\n";
   if(!COT_WriteText(directory+"\\history.dat",historyMetadata)) {error="Cannot save retained history catalog.";return false;}
   // A different ZIP encoding of identical rows is not a new dataset.
   if(!anyChanged) {g_cotUpdateOutcome="UNCHANGED";COT_DiscardStage(requestId);return true;}
   long generation=haveOld?StringToInteger(COT_Field(oldRuntime,"GENERATION"))+1:1;
   if(generation<1 || generation>9007199254740991) {error="Generation range exceeded."; return false;}
   string runtime="SCHEMA=2\nGENERATION="+IntegerToString(generation)+"\nHASH="+hash+
      "\nOBSERVED_AT="+IntegerToString((long)COT_NOW())+"\n"+
      COT_WeeklyPolicyText(g_cotReleaseHour,g_cotProviderLag,g_cotGraceMinutes);
   if(!COT_WriteText(directory+"\\runtime.dat",runtime)) {error="Cannot write runtime metadata."; return false;}
   string metadata=requestId+"\n"+IntegerToString((long)COT_NOW())+"\n";
   for(int i=0;i<ArraySize(ids);i++) metadata+=ids[i]+"\n";
   if(!COT_WriteText(directory+"\\complete.dat",metadata)) {error="Cannot finalize cache generation."; return false;}
   if(IsStopped()) {error="Service stopped before cache publication."; return false;}
   if(!COT_CommitMetadata(metadata,error)) return false;
   Print("[SQ COT] Cache updated: ",ArraySize(ids)," series.");
   g_cotUpdateOutcome=newReport?"NEW_REPORT":"REVISION_ONLY";
   return true;
}

bool ProcessUpdateRequest(const string id,const string identifier,string license,
                           const string endpoint,const int timeoutMs,string &code,string &error)
{
   uchar archive[];
   if(!DownloadCOTData(endpoint,license,timeoutMs,archive,code,error)) return false;
   license="";
   if(code=="UNCHANGED" && ArraySize(archive)==0) {g_cotUpdateOutcome="UNCHANGED";return true;}
   string tmp=COT_CACHE_DIR+"\\download-"+id+".tmp";
   code="ERROR_FILE_WRITE";
   if(!COT_WriteBytes(tmp,archive)) {error="Cannot save temporary archive."; FileDelete(tmp,COT_FILE_SCOPE); return false;}
   ArrayFree(archive);
   bool ok=COT_ReadBytes(tmp,archive);
   FileDelete(tmp,COT_FILE_SCOPE);
   if(!ok) {error="Cannot read back temporary archive."; return false;}
   code="ERROR_INVALID_DATA";
   CotZipEntry entries[];
   if(!ValidateCOTData(archive,entries,error)) return false;
   if(!SaveCOTData(archive,entries,id,identifier,error)) {COT_DiscardStage(id);return false;}
   COT_PruneGenerations();
   code=g_cotUpdateOutcome; error="";
   return true;
}
#endif
