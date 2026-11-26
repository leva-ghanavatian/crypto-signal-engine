# analysis_functions/analyze_rsi_ema.py
import pandas as pd

def analyze_rsi_ema(row):
    """
    Analyze RSI-EMA crossover signals
    
    Parameters:
    - row: Current candle data (includes prev_RSI and prev_RSI_EMA if available)
    """
    rsi = row['RSI']
    rsi_ema = row['RSI_EMA']
    
    if pd.isna(rsi) or pd.isna(rsi_ema):
        return {'value': None, 
                'signal': 'insufficient_data', 
                'strength': 0, 
                'recommendation': 'no_data'}
    
    # Use previous row data from the row dict (added by main analyzer)
    prev_rsi = row.get('prev_RSI', rsi)
    prev_rsi_ema = row.get('prev_RSI_EMA', rsi_ema)
    
    # Check for crossovers
    # Bullish crossover: RSI crosses above RSI-EMA
    if prev_rsi <= prev_rsi_ema and rsi > rsi_ema:
        signal = 'bullish_crossover'
        strength = 80
        recommendation = 'buy_signal'
    # Bearish crossover: RSI crosses below RSI-EMA
    elif prev_rsi >= prev_rsi_ema and rsi < rsi_ema:
        signal = 'bearish_crossover'
        strength = 80
        recommendation = 'sell_signal'
    # RSI above EMA (bullish alignment)
    elif rsi > rsi_ema:
        signal = 'bullish_aligned'
        strength = int(60 + (rsi - rsi_ema) / rsi_ema * 20)
        recommendation = 'bullish'
    # RSI below EMA (bearish alignment)
    elif rsi < rsi_ema:
        signal = 'bearish_aligned'
        strength = int(60 + (rsi_ema - rsi) / rsi_ema * 20)
        recommendation = 'bearish'
    else:
        signal = 'neutral'
        strength = 50
        recommendation = 'neutral'
    
    return {
        'value': rsi_ema,
        'signal': signal,
        'strength': min(100, strength),
        'recommendation': recommendation
    }