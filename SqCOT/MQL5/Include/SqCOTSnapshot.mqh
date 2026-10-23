// Export active data and its effective policy as one reproducible snapshot.
#ifndef __SQ_COT_SNAPSHOT_MQH__
#define __SQ_COT_SNAPSHOT_MQH__
#include <SqCOTReader.mqh>
#include <SqCOTPit.mqh>
#include <SqCOTSymbolMap.mqh>
#include <SqCOTFreshness.mqh>
bool COT_VerifySnapshotPolicy(const string directory,const string runtime)
{
   string schema=COT_Field(runtime,"SNAPSHOT_POLICY_SCHEMA");
   if(schema=="")return !FileIsExist(directory+"\\snapshot-policy.dat",COT_FILE_SCOPE); // Previously exported snapshots keep their original contract.
   string manifest,digest,calendar,source;
   bool ok=(schema=="1" || schema=="2") && COT_ReadText(directory+"\\snapshot-policy.dat",manifest) &&
      COT_ReadText(directory+"\\snapshot-policy.sha256",digest) && COT_Trim(digest)==COT_MapHash(manifest) &&
      COT_Field(manifest,"SCHEMA")==schema && COT_Field(manifest,"RUNTIME_HASH")==COT_MapHash(runtime) &&
      COT_ReadText(directory+"\\source.dat",source) && COT_Field(manifest,"SOURCE_HASH")==COT_MapHash(source);
   if(schema=="1")ok=ok && COT_ReadText(directory+"\\calendar.csv",calendar) &&
      COT_Field(manifest,"CALENDAR_HASH")==COT_MapHash(calendar);
   return ok;
}
bool COT_ExportSnapshot(const string snapshotId,const string profile,const bool mapping,
   const string symbol,const string server,string &error)
{
   error="";
   if(!COT_SafeName(snapshotId) || (profile!="" && !COT_SafeName(profile)))
   {error="Invalid snapshot or profile name.";return false;}
   int lock=COT_Lock("cache");if(lock==INVALID_HANDLE){error="Cache busy; retry export.";return false;}
   int policyLock=COT_Lock("policy");
   if(policyLock==INVALID_HANDLE){FileClose(lock);error="Policy busy; retry export.";return false;}
   string pointer,version,ids[];datetime updated;
   bool ok=COT_ReadText(COT_METADATA_FILE,pointer) && COT_ParseMetadata(pointer,version,updated,ids);
   if(!ok)ok=COT_ReadText(COT_METADATA_FILE+".previous",pointer) && COT_ParseMetadata(pointer,version,updated,ids);
   string src=COT_CACHE_DIR+"\\generations\\"+version,dst=COT_CACHE_DIR+"\\snapshots\\"+snapshotId;
   string runtime,policyText;CotFreshnessPolicy policy={};
   if(ok)ok=COT_ReadText(src+"\\runtime.dat",runtime) && COT_Field(runtime,"SCHEMA")=="2";
   if(ok)ok=COT_ReadText(COT_CACHE_DIR+"\\policy.dat",policyText) &&
      COT_ParseFreshnessPolicy(policyText,policy) && !policy.legacy;
   // Copy the effective settings while both mutable sources are locked.
   string captured="SCHEMA=2\nGENERATION="+COT_Field(runtime,"GENERATION")+"\nHASH="+COT_Field(runtime,"HASH")+
      "\nOBSERVED_AT="+COT_Field(runtime,"OBSERVED_AT")+"\n"+
      COT_WeeklyPolicyText(policy.releaseHour,policy.lagMinutes,policy.graceMinutes)+"SNAPSHOT_POLICY_SCHEMA=2\n";
   FileClose(policyLock);
   if(FileIsExist(dst+"\\runtime.dat",COT_FILE_SCOPE) || FileIsExist(dst+"\\EXPORTING",COT_FILE_SCOPE))ok=false;
   if(ok)ok=COT_WriteText(dst+"\\EXPORTING","INCOMPLETE\n");
   for(int i=0;ok && i<ArraySize(ids);i++)
   {
      CotPitRecord rows[];uchar bytes[];
      ok=COT_ReadPit(src+"\\"+ids[i]+".pit",rows) && COT_ReadBytes(src+"\\"+ids[i]+".pit",bytes) &&
         COT_WriteBytes(dst+"\\"+ids[i]+".pit",bytes) && COT_WriteText(dst+"\\"+ids[i]+".sha256",COT_Hash(bytes)+"\n");
   }
   if(ok)ok=COT_WriteText(dst+"\\runtime.dat",captured);
   if(ok && profile!="")
   {
      uchar bytes[];string file="\\profiles\\"+profile+".csv";
      ok=COT_ReadBytes(COT_CACHE_DIR+file,bytes) && COT_WriteBytes(dst+file,bytes) && COT_WriteText(dst+file+".sha256",COT_Hash(bytes)+"\n");
   }
   if(ok && mapping)ok=COT_MapExport(dst,pointer,symbol,server);
   string manifest="SCHEMA=2\nCAPTURED_AT="+IntegerToString((long)COT_NOW())+"\nRUNTIME_HASH="+COT_MapHash(captured)+
      "\nSOURCE_HASH="+COT_MapHash(pointer)+"\n";
   if(ok)ok=COT_WriteText(dst+"\\source.dat",pointer) && COT_WriteText(dst+"\\snapshot-policy.dat",manifest) &&
      COT_WriteText(dst+"\\snapshot-policy.sha256",COT_MapHash(manifest)+"\n") &&
      COT_VerifySnapshotPolicy(dst,captured) && FileDelete(dst+"\\EXPORTING",COT_FILE_SCOPE);
   FileClose(lock);
   if(!ok)error="Snapshot export failed or ID already exists; resolve the cause and use a new ID.";
   return ok;
}
#endif
