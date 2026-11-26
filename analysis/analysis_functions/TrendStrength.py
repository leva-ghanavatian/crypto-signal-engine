import pandas as pd

def analyze_trend_strength(row):
    """
    Analyze trend strength using ADX and other trend indicators
    """
    adx = row.get('ADX_14', 50)
    dmp = row.get('DMP_14', 25)
    dmn = row.get('DMN_14', 25)
    
    if pd.isna(adx):
        return {
            'signal': 'insufficient_data',
            'strength': 0,
            'trend_strength': 0
        }
    
    # ADX interpretation
    if adx > 50:
        trend_strength = 'extremely_strong_trend'
        strength = 90
    elif adx > 35:
        trend_strength = 'strong_trend'
        strength = 75
    elif adx > 25:
        trend_strength = 'moderate_trend'
        strength = 60
    elif adx > 20:
        trend_strength = 'weak_trend'
        strength = 45
    else:
        trend_strength = 'no_trend_ranging'
        strength = 30
    
    # Determine direction
    if dmp > dmn:
        direction = 'bullish'
    elif dmn > dmp:
        direction = 'bearish'
    else:
        direction = 'neutral'
    
    return {
        'value': adx,
        'signal': f"{trend_strength}_{direction}",
        'strength': strength,
        'trend_strength': adx,
        'direction': direction
    }