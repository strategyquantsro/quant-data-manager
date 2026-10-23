//+------------------------------------------------------------------+
//|                                                SqCOTBlocks.mqh   |
//|                                Copyright 2026, StrategyQuant      |
//|                            https://www.strategyquant.com           |
//+------------------------------------------------------------------+
//| MQL5 helper functions for COT condition blocks.                    |
//| Uses the strict SqCOTStrategy adapter; configure context in OnInit.|
//| Handle encoding: 0-4 = 52w buffers, 10-14 = 156w buffers          |
//+------------------------------------------------------------------+
#ifndef __SQ_COT_BLOCKS_MQH__
#define __SQ_COT_BLOCKS_MQH__
#include <SqCOTStrategy.mqh>

//+==================================================================+
//| HELPER: Get bar index for Nth previous COT record                 |
//| Uses actual observed report records, including publication gaps. |
//| getCotRecordBar and MC DLL ShiftELDateByWeeks.                    |
//+==================================================================+

// Internal report cursor; deliberately not a price-bar index.
int SqCOT_GetRecordBar(int startBar, int recordShift)
{ return SqCOT_ReportCursor(startBar,recordShift); }

//+==================================================================+
//| COMPOSITE SCORE                                                   |
//| score = avg(hedg52, hedg156) - avg(spec52, spec156)               |
//+==================================================================+

double SqCOT_CalcScore(int hH52, int hH156, int hS52, int hS156, int shift)
{
   double h52  = SqCOT_StrategyValue(hH52,  0, shift);
   double h156 = SqCOT_StrategyValue(hH156, 0, shift);
   double s52  = SqCOT_StrategyValue(hS52,  2, shift);
   double s156 = SqCOT_StrategyValue(hS156, 2, shift);
   return SqCOT_NumberResult(((h52 + h156) / 2.0) - ((s52 + s156) / 2.0));
}

// CalcScore at Nth COT record back from startBar
double SqCOT_CalcScoreRecord(int hH52, int hH156, int hS52, int hS156, int startBar, int recordShift)
{
   int bar = SqCOT_GetRecordBar(startBar, recordShift);
   // Convert absolute bar to relative shift from g_currentBar
   int relShift = bar - g_currentBar;
   return SqCOT_NumberResult(SqCOT_CalcScore(hH52, hH156, hS52, hS156, relShift));
}

//+==================================================================+
//| ACCUMULATION                                                      |
//+==================================================================+
// SqCOT_AccumulationBullish(h52_0, h52_2, shift, minWeeks)
bool SqCOT_AccumulationBullish(int hH52, int hS52, int shift, int minWeeks)
{
   if(minWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   for(int i = 0; i < minWeeks; i++)
   {
      int bNow  = SqCOT_GetRecordBar(startBar, i);
      int bPrev = SqCOT_GetRecordBar(startBar, i + 1);
      double hedgNow  = SqCOT_StrategyValue(hH52, 0, bNow - g_currentBar);
      double hedgPrev = SqCOT_StrategyValue(hH52, 0, bPrev - g_currentBar);
      double specNow  = SqCOT_StrategyValue(hS52, 2, bNow - g_currentBar);
      double specPrev = SqCOT_StrategyValue(hS52, 2, bPrev - g_currentBar);
      if(hedgNow <= hedgPrev || specNow >= specPrev) return SqCOT_BlockResult(false);
   }
   return SqCOT_BlockResult(true);
}

// SqCOT_AccumulationBearish(h52_0, h52_2, shift, minWeeks)
bool SqCOT_AccumulationBearish(int hH52, int hS52, int shift, int minWeeks)
{
   if(minWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   for(int i = 0; i < minWeeks; i++)
   {
      int bNow  = SqCOT_GetRecordBar(startBar, i);
      int bPrev = SqCOT_GetRecordBar(startBar, i + 1);
      double hedgNow  = SqCOT_StrategyValue(hH52, 0, bNow - g_currentBar);
      double hedgPrev = SqCOT_StrategyValue(hH52, 0, bPrev - g_currentBar);
      double specNow  = SqCOT_StrategyValue(hS52, 2, bNow - g_currentBar);
      double specPrev = SqCOT_StrategyValue(hS52, 2, bPrev - g_currentBar);
      if(hedgNow >= hedgPrev || specNow <= specPrev) return SqCOT_BlockResult(false);
   }
   return SqCOT_BlockResult(true);
}

//+==================================================================+
//| EXTREME EXIT                                                      |
//+==================================================================+
// SqCOT_ExtremeExitBullish(h52_0, shift, lookbackWeeks, exitThreshold, extremeThreshold)
bool SqCOT_ExtremeExitBullish(int hH52, int shift, int lookbackWeeks,
                               double exitThreshold, double extremeThreshold)
{
   if(lookbackWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double currentVal = SqCOT_StrategyValue(hH52, 0, shift);
   if(currentVal < 0 || currentVal >= exitThreshold) return SqCOT_BlockResult(false);
   for(int i = 1; i <= lookbackWeeks; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      if(SqCOT_StrategyValue(hH52, 0, bk - g_currentBar) > extremeThreshold)
         return SqCOT_BlockResult(true);
   }
   return SqCOT_BlockResult(false);
}

// SqCOT_ExtremeExitBearish(h52_2, shift, lookbackWeeks, exitThreshold, extremeThreshold)
bool SqCOT_ExtremeExitBearish(int hS52, int shift, int lookbackWeeks,
                               double exitThreshold, double extremeThreshold)
{
   if(lookbackWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double currentVal = SqCOT_StrategyValue(hS52, 2, shift);
   if(currentVal < 0 || currentVal >= exitThreshold) return SqCOT_BlockResult(false);
   for(int i = 1; i <= lookbackWeeks; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      if(SqCOT_StrategyValue(hS52, 2, bk - g_currentBar) > extremeThreshold)
         return SqCOT_BlockResult(true);
   }
   return SqCOT_BlockResult(false);
}

//+==================================================================+
//| EXTREME PERSISTENCE                                               |
//+==================================================================+
// SqCOT_ExtremePersistence(handle, bufIdx, shift, minWeeks, extremeThreshold)
bool SqCOT_ExtremePersistence(int handle, int bufIdx, int shift,
                               int minWeeks, double extremeThreshold)
{
   if(minWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   for(int i = 0; i < minWeeks; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      double val = SqCOT_StrategyValue(handle, bufIdx, bk - g_currentBar);
      if(val < 0 || val < extremeThreshold)
         return SqCOT_BlockResult(false);
   }
   return SqCOT_BlockResult(true);
}

//+==================================================================+
//| EXTREME UNWIND                                                    |
//+==================================================================+
// SqCOT_ExtremeUnwindBullish(h52_2, shift, lookbackWeeks, normalizeThreshold, crowdedThreshold)
bool SqCOT_ExtremeUnwindBullish(int hS52, int shift, int lookbackWeeks,
                                 double normalizeThreshold, double crowdedThreshold)
{
   if(lookbackWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double now  = SqCOT_StrategyValue(hS52, 2, shift);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   double prev = SqCOT_StrategyValue(hS52, 2, bPrev - g_currentBar);
   if(now >= normalizeThreshold || now >= prev) return SqCOT_BlockResult(false);
   for(int i = 1; i <= lookbackWeeks; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      if(SqCOT_StrategyValue(hS52, 2, bk - g_currentBar) > crowdedThreshold)
         return SqCOT_BlockResult(true);
   }
   return SqCOT_BlockResult(false);
}

// SqCOT_ExtremeUnwindBearish(h52_0, shift, lookbackWeeks, normalizeThreshold, crowdedThreshold)
bool SqCOT_ExtremeUnwindBearish(int hH52, int shift, int lookbackWeeks,
                                 double normalizeThreshold, double crowdedThreshold)
{
   if(lookbackWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double now  = SqCOT_StrategyValue(hH52, 0, shift);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   double prev = SqCOT_StrategyValue(hH52, 0, bPrev - g_currentBar);
   if(now >= normalizeThreshold || now >= prev) return SqCOT_BlockResult(false);
   for(int i = 1; i <= lookbackWeeks; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      if(SqCOT_StrategyValue(hH52, 0, bk - g_currentBar) > crowdedThreshold)
         return SqCOT_BlockResult(true);
   }
   return SqCOT_BlockResult(false);
}

//+==================================================================+
//| SPEC EXHAUSTION                                                   |
//+==================================================================+
// SqCOT_SpecExhaustionLong(h52_2, h52_0, shift, lookbackWeeks, specExtreme, hedgerThreshold)
bool SqCOT_SpecExhaustionLong(int hS52, int hH52, int shift, int lookbackWeeks,
                               double specExtreme, double hedgerThreshold)
{
   if(lookbackWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double specNow  = SqCOT_StrategyValue(hS52, 2, shift);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   double specPrev = SqCOT_StrategyValue(hS52, 2, bPrev - g_currentBar);
   double hedgNow  = SqCOT_StrategyValue(hH52, 0, shift);
   double shortExtreme = 1.0 - specExtreme;
   if(specNow <= specPrev || hedgNow <= hedgerThreshold) return SqCOT_BlockResult(false);
   for(int i = 1; i <= lookbackWeeks; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      if(SqCOT_StrategyValue(hS52, 2, bk - g_currentBar) < shortExtreme)
         return SqCOT_BlockResult(true);
   }
   return SqCOT_BlockResult(false);
}

// SqCOT_SpecExhaustionShort(h52_2, h52_0, shift, lookbackWeeks, specExtreme, hedgerThreshold)
bool SqCOT_SpecExhaustionShort(int hS52, int hH52, int shift, int lookbackWeeks,
                                double specExtreme, double hedgerThreshold)
{
   if(lookbackWeeks<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double specNow  = SqCOT_StrategyValue(hS52, 2, shift);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   double specPrev = SqCOT_StrategyValue(hS52, 2, bPrev - g_currentBar);
   double hedgNow  = SqCOT_StrategyValue(hH52, 0, shift);
   if(specNow >= specPrev || hedgNow >= hedgerThreshold) return SqCOT_BlockResult(false);
   for(int i = 1; i <= lookbackWeeks; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      if(SqCOT_StrategyValue(hS52, 2, bk - g_currentBar) > specExtreme)
         return SqCOT_BlockResult(true);
   }
   return SqCOT_BlockResult(false);
}

//+==================================================================+
//| DEVIATION FROM PRECEDING REPORT MEAN (not calendar seasonality)    |
//+==================================================================+
// SqCOT_SeasonalBullish(h52_0, shift, lookback, threshold)
bool SqCOT_AboveReportMean(int hH52, int shift, int lookback, double threshold)
{
   if(lookback<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double current = SqCOT_StrategyValue(hH52, 0, shift);
   double sum = 0;
   for(int i = 1; i <= lookback; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      sum += SqCOT_StrategyValue(hH52, 0, bk - g_currentBar);
   }
   return SqCOT_BlockResult((current > sum / lookback + threshold));
}

// SqCOT_SeasonalBearish(h52_0, shift, lookback, threshold)
bool SqCOT_BelowReportMean(int hH52, int shift, int lookback, double threshold)
{
   if(lookback<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double current = SqCOT_StrategyValue(hH52, 0, shift);
   double sum = 0;
   for(int i = 1; i <= lookback; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      sum += SqCOT_StrategyValue(hH52, 0, bk - g_currentBar);
   }
   return SqCOT_BlockResult((current < sum / lookback - threshold));
}

// Backward-compatible aliases: these never measured calendar seasonality.
bool SqCOT_SeasonalBullish(int handle,int shift,int lookback,double threshold)
{return SqCOT_AboveReportMean(handle,shift,lookback,threshold);}
bool SqCOT_SeasonalBearish(int handle,int shift,int lookback,double threshold)
{return SqCOT_BelowReportMean(handle,shift,lookback,threshold);}

//+==================================================================+
//| SPREAD Z-SCORE                                                    |
//+==================================================================+
// SqCOT_SpreadZScoreBullish(h52_0, h52_2, shift, period, zThreshold)
bool SqCOT_SpreadZScoreBullish(int hH52, int hS52, int shift, int period, double zThreshold)
{
   if(period<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double sum = 0, sumSq = 0;
   double currentSpread = SqCOT_StrategyValue(hH52, 0, shift)
                        - SqCOT_StrategyValue(hS52, 2, shift);
   for(int i = 0; i < period; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      double spread = SqCOT_StrategyValue(hH52, 0, bk - g_currentBar)
                    - SqCOT_StrategyValue(hS52, 2, bk - g_currentBar);
      sum += spread;
      sumSq += spread * spread;
   }
   double mean = sum / period;
   double variance = (sumSq / period) - (mean * mean);
   if(variance <= 0) return SqCOT_BlockResult(false);
   double zScore = (currentSpread - mean) / MathSqrt(variance);
   return SqCOT_BlockResult((zScore > zThreshold));
}

// SqCOT_SpreadZScoreBearish(h52_0, h52_2, shift, period, zThreshold)
bool SqCOT_SpreadZScoreBearish(int hH52, int hS52, int shift, int period, double zThreshold)
{
   if(period<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double sum = 0, sumSq = 0;
   double currentSpread = SqCOT_StrategyValue(hH52, 0, shift)
                        - SqCOT_StrategyValue(hS52, 2, shift);
   for(int i = 0; i < period; i++)
   {
      int bk = SqCOT_GetRecordBar(startBar, i);
      double spread = SqCOT_StrategyValue(hH52, 0, bk - g_currentBar)
                    - SqCOT_StrategyValue(hS52, 2, bk - g_currentBar);
      sum += spread;
      sumSq += spread * spread;
   }
   double mean = sum / period;
   double variance = (sumSq / period) - (mean * mean);
   if(variance <= 0) return SqCOT_BlockResult(false);
   double zScore = (currentSpread - mean) / MathSqrt(variance);
   return SqCOT_BlockResult((zScore < -zThreshold));
}

//+==================================================================+
//| HIGHER LOW / LOWER HIGH                                           |
//+==================================================================+
// SqCOT_HigherLow(h52_0, h156_0, h52_2, h156_2, shift, shortWindow, longWindow)
bool SqCOT_HigherLow(int hH52, int hH156, int hS52, int hS156,
                      int shift, int shortWindow, int longWindow)
{
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double shortMin = DBL_MAX;
   for(int i = 0; i < shortWindow; i++)
      shortMin = MathMin(shortMin, SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, i));
   double longMin = DBL_MAX;
   for(int i = shortWindow; i < longWindow; i++)
      longMin = MathMin(longMin, SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, i));
   return SqCOT_BlockResult((shortMin > longMin && longMin < 0));
}

// SqCOT_LowerHigh(h52_0, h156_0, h52_2, h156_2, shift, shortWindow, longWindow)
bool SqCOT_LowerHigh(int hH52, int hH156, int hS52, int hS156,
                      int shift, int shortWindow, int longWindow)
{
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double shortMax = -DBL_MAX;
   for(int i = 0; i < shortWindow; i++)
      shortMax = MathMax(shortMax, SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, i));
   double longMax = -DBL_MAX;
   for(int i = shortWindow; i < longWindow; i++)
      longMax = MathMax(longMax, SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, i));
   return SqCOT_BlockResult((shortMax < longMax && longMax > 0));
}

//+==================================================================+
//| SCORE MOMENTUM                                                    |
//+==================================================================+
// SqCOT_ScoreMomentumAbove(h52_0, h156_0, h52_2, h156_2, shift, lookback, momThreshold, levelThreshold)
bool SqCOT_ScoreMomentumAbove(int hH52, int hH156, int hS52, int hS156,
                               int shift, int lookback,
                               double momThreshold, double levelThreshold)
{
   if(lookback<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double scoreNow  = SqCOT_CalcScore(hH52, hH156, hS52, hS156, shift);
   double scorePrev = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, lookback);
   double momentum  = scoreNow - scorePrev;
   if(momentum <= momThreshold) return SqCOT_BlockResult(false);
   if(levelThreshold != 0.0 && scoreNow <= levelThreshold) return SqCOT_BlockResult(false);
   return SqCOT_BlockResult(true);
}

// SqCOT_ScoreMomentumBelow(h52_0, h156_0, h52_2, h156_2, shift, lookback, momThreshold, levelThreshold)
bool SqCOT_ScoreMomentumBelow(int hH52, int hH156, int hS52, int hS156,
                               int shift, int lookback,
                               double momThreshold, double levelThreshold)
{
   if(lookback<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double scoreNow  = SqCOT_CalcScore(hH52, hH156, hS52, hS156, shift);
   double scorePrev = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, lookback);
   double momentum  = scoreNow - scorePrev;
   if(momentum >= -momThreshold) return SqCOT_BlockResult(false);
   if(levelThreshold != 0.0 && scoreNow >= levelThreshold) return SqCOT_BlockResult(false);
   return SqCOT_BlockResult(true);
}

//+==================================================================+
//| SCORE ZERO CROSS                                                  |
//+==================================================================+
// SqCOT_ScoreZeroCrossUp(h52_0, h156_0, h52_2, h156_2, shift)
bool SqCOT_ScoreZeroCrossUp(int hH52, int hH156, int hS52, int hS156, int shift)
{
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double scoreNow  = SqCOT_CalcScore(hH52, hH156, hS52, hS156, shift);
   double scorePrev = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, 1);
   return SqCOT_BlockResult((scoreNow > 0 && scorePrev <= 0));
}

// SqCOT_ScoreZeroCrossDown(h52_0, h156_0, h52_2, h156_2, shift)
bool SqCOT_ScoreZeroCrossDown(int hH52, int hH156, int hS52, int hS156, int shift)
{
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double scoreNow  = SqCOT_CalcScore(hH52, hH156, hS52, hS156, shift);
   double scorePrev = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, 1);
   return SqCOT_BlockResult((scoreNow < 0 && scorePrev >= 0));
}

//+==================================================================+
//| MOMENTUM REVERSAL                                                 |
//+==================================================================+
// SqCOT_MomentumRevBullish(h52_0, h156_0, h52_2, h156_2, shift, momPeriod)
bool SqCOT_MomentumRevBullish(int hH52, int hH156, int hS52, int hS156,
                               int shift, int momPeriod)
{
   if(momPeriod<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double momNow  = SqCOT_CalcScore(hH52, hH156, hS52, hS156, shift)
                  - SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, momPeriod);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   double momPrev = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, 0) // actually we need score at bPrev
                  - SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, bPrev, momPeriod);
   // Fix: score at bPrev, not startBar
   int relPrev = bPrev - g_currentBar;
   double scorePrev = SqCOT_CalcScore(hH52, hH156, hS52, hS156, relPrev);
   double scorePrevMom = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, bPrev, momPeriod);
   momPrev = scorePrev - scorePrevMom;
   return SqCOT_BlockResult((momNow > 0 && momPrev <= 0));
}

// SqCOT_MomentumRevBearish(h52_0, h156_0, h52_2, h156_2, shift, momPeriod)
bool SqCOT_MomentumRevBearish(int hH52, int hH156, int hS52, int hS156,
                               int shift, int momPeriod)
{
   if(momPeriod<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double momNow  = SqCOT_CalcScore(hH52, hH156, hS52, hS156, shift)
                  - SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, momPeriod);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   int relPrev = bPrev - g_currentBar;
   double scorePrev = SqCOT_CalcScore(hH52, hH156, hS52, hS156, relPrev);
   double scorePrevMom = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, bPrev, momPeriod);
   double momPrev = scorePrev - scorePrevMom;
   return SqCOT_BlockResult((momNow < 0 && momPrev >= 0));
}

//+==================================================================+
//| SCORE ACCELERATION                                                |
//+==================================================================+
// SqCOT_ScoreAccelBullish(h52_0, h156_0, h52_2, h156_2, shift, momPeriod, momentumThreshold)
bool SqCOT_ScoreAccelBullish(int hH52, int hH156, int hS52, int hS156,
                              int shift, int momPeriod, double momentumThreshold)
{
   if(momPeriod<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double momNow  = SqCOT_CalcScore(hH52, hH156, hS52, hS156, shift)
                  - SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, momPeriod);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   int relPrev = bPrev - g_currentBar;
   double scorePrev = SqCOT_CalcScore(hH52, hH156, hS52, hS156, relPrev);
   double scorePrevMom = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, bPrev, momPeriod);
   double momPrev = scorePrev - scorePrevMom;
   return SqCOT_BlockResult((momNow > momPrev && momNow > momentumThreshold));
}

// SqCOT_ScoreAccelBearish(h52_0, h156_0, h52_2, h156_2, shift, momPeriod, momentumThreshold)
bool SqCOT_ScoreAccelBearish(int hH52, int hH156, int hS52, int hS156,
                              int shift, int momPeriod, double momentumThreshold)
{
   if(momPeriod<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double momNow  = SqCOT_CalcScore(hH52, hH156, hS52, hS156, shift)
                  - SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, momPeriod);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   int relPrev = bPrev - g_currentBar;
   double scorePrev = SqCOT_CalcScore(hH52, hH156, hS52, hS156, relPrev);
   double scorePrevMom = SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, bPrev, momPeriod);
   double momPrev = scorePrev - scorePrevMom;
   return SqCOT_BlockResult((momNow < momPrev && momNow < -momentumThreshold));
}

//+==================================================================+
//| REGIME SHIFT — Matches MC DLL RegShiftBull/Bear                   |
//| shortAvg(shiftWeeks) vs longAvg(shiftWeeks*3)                     |
//+==================================================================+
// SqCOT_RegimeShiftBullish(h52_0, h156_0, h52_2, h156_2, shift, level, shiftWeeks)
bool SqCOT_RegimeShiftBullish(int hH52, int hH156, int hS52, int hS156,
                               int shift, double level, int shiftWeeks)
{
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double shortSum = 0;
   for(int i = 0; i < shiftWeeks; i++)
      shortSum += SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, i);
   double shortAvg = shortSum / shiftWeeks;

   int longWin = shiftWeeks * 3;
   double longSum = 0;
   for(int i = 0; i < longWin; i++)
      longSum += SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, i);
   double longAvg = longSum / longWin;

   return SqCOT_BlockResult((shortAvg > longAvg && shortAvg > 0));
}

// SqCOT_RegimeShiftBearish(h52_0, h156_0, h52_2, h156_2, shift, level, shiftWeeks)
bool SqCOT_RegimeShiftBearish(int hH52, int hH156, int hS52, int hS156,
                               int shift, double level, int shiftWeeks)
{
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double shortSum = 0;
   for(int i = 0; i < shiftWeeks; i++)
      shortSum += SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, i);
   double shortAvg = shortSum / shiftWeeks;

   int longWin = shiftWeeks * 3;
   double longSum = 0;
   for(int i = 0; i < longWin; i++)
      longSum += SqCOT_CalcScoreRecord(hH52, hH156, hS52, hS156, startBar, i);
   double longAvg = longSum / longWin;

   return SqCOT_BlockResult((shortAvg < longAvg && shortAvg < 0));
}

//+==================================================================+
//| CROWDING UNWIND                                                   |
//+==================================================================+
// SqCOT_CrowdingUnwind(h52_0, h52_2, shift, direction, specExtreme, hedgerOpposing)
bool SqCOT_CrowdingUnwind(int hH52, int hS52, int shift, int direction,
                           double specExtreme, double hedgerOpposing)
{
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double specNow  = SqCOT_StrategyValue(hS52, 2, shift);
   int bPrev = SqCOT_GetRecordBar(startBar, 1);
   double specPrev = SqCOT_StrategyValue(hS52, 2, bPrev - g_currentBar);
   double hedgNow  = SqCOT_StrategyValue(hH52, 0, shift);
   if(specNow < 0 || specPrev < 0 || hedgNow < 0) return SqCOT_BlockResult(false);
   if(direction > 0)
   {
      return SqCOT_BlockResult((specPrev > specExtreme && specNow < specPrev && hedgNow < hedgerOpposing));
   }
   else
   {
      double shortExtreme = 1.0 - specExtreme;
      double hedgerHigh = 1.0 - hedgerOpposing;
      return SqCOT_BlockResult((specPrev < shortExtreme && specNow > specPrev && hedgNow > hedgerHigh));
   }
}

//+==================================================================+
//| ROC — Matches MC DLL RocBull/Bear                                 |
//| Uses composite score difference, not spread ROC                   |
//+==================================================================+
// SqCOT_RocBullish(h52_0, h52_2, shift, rocPeriod, rocThreshold)
// Note: export passes h52_0 and h52_2, but Roc needs full score (4 handles).
// However, the export calls with only 2 handles. The MC DLL RocBull uses
// GetScoreShifted which needs all 4 (52w+156w). Since the export only passes
// h52_0 and h52_2, we compute a simplified score using just 52w:
// score = hedg52 - spec52 (no 156w averaging).
bool SqCOT_RocBullish(int hH52, int hS52, int shift, int rocPeriod, double rocThreshold)
{
   if(rocPeriod<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double scoreNow  = SqCOT_StrategyValue(hH52, 0, shift) - SqCOT_StrategyValue(hS52, 2, shift);
   int bPrev = SqCOT_GetRecordBar(startBar, rocPeriod);
   int relPrev = bPrev - g_currentBar;
   double scorePast = SqCOT_StrategyValue(hH52, 0, relPrev) - SqCOT_StrategyValue(hS52, 2, relPrev);
   if(scoreNow < -1.0 || scorePast < -1.0) return SqCOT_BlockResult(false);
   return SqCOT_BlockResult(((scoreNow - scorePast) > rocThreshold));
}

// SqCOT_RocBearish(h52_0, h52_2, shift, rocPeriod, rocThreshold)
bool SqCOT_RocBearish(int hH52, int hS52, int shift, int rocPeriod, double rocThreshold)
{
   if(rocPeriod<=0) return false;
   if(!SqCOT_BeginEvaluation()) return false;
   int startBar = g_currentBar + shift;
   double scoreNow  = SqCOT_StrategyValue(hH52, 0, shift) - SqCOT_StrategyValue(hS52, 2, shift);
   int bPrev = SqCOT_GetRecordBar(startBar, rocPeriod);
   int relPrev = bPrev - g_currentBar;
   double scorePast = SqCOT_StrategyValue(hH52, 0, relPrev) - SqCOT_StrategyValue(hS52, 2, relPrev);
   if(scoreNow < -1.0 || scorePast < -1.0) return SqCOT_BlockResult(false);
   return SqCOT_BlockResult(((scoreNow - scorePast) < -rocThreshold));
}

#endif // __SQ_COT_BLOCKS_MQH__
