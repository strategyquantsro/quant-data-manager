#property service
#property version "4.25"
#property description "StrategyQuant COT: resilient scheduled updates and health monitoring."
#include <SqCOTServiceRuntime.mqh>
void OnStart() {COT_RunService();}
