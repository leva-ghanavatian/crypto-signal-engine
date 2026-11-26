import pandas as pd
def analyze_rsi(row):
    """
    Analyze RSI indicator
    Returns: dict with signal, strength, and recommendation
    """
    rsi = row['RSI']
    
    if pd.isna(rsi):
        return {'value': None, 
                'signal': 'insufficient_data', 
                'strength': 0, 
                'recommendation': 'no_data'}
    
    # RSI signals
    if rsi < 30:
        signal = 'oversold'
        strength = min(100, int((30 - rsi) * 3.33))  # 0-100 scale (lower RSI = higher strength)
        recommendation = 'potential_buy'
    elif rsi > 70:
        signal = 'overbought'
        strength = min(100, int((rsi - 70) * 3.33))
        recommendation = 'potential_sell'
    elif 30 <= rsi < 40:
        signal = 'near_oversold'
        strength = int((40 - rsi) * 10)
        recommendation = 'watch_for_buy'
    elif 60 < rsi <= 70:
        signal = 'near_overbought'
        strength = int((rsi - 60) * 10)
        recommendation = 'watch_for_sell'
    else:
        signal = 'neutral'
        strength = 50
        recommendation = 'hold'
    
    return {
        'value': rsi,
        'signal': signal,
        'strength': strength,
        'recommendation': recommendation
    }