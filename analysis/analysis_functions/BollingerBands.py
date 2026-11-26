import pandas as pd
def analyze_bbands(row):
    """
    Analyze Bollinger Bands
    """
    close = row['close']
    bb_upper = row['BBU_20_2.0_2.0']
    bb_middle = row['BBM_20_2.0_2.0']
    bb_lower = row['BBL_20_2.0_2.0']
    
    if pd.isna(bb_upper) or pd.isna(bb_lower):
        return {
            'upper': None,  
            'lower': None,      
            'middle': None,     
            'percent_b': 0.5,
            'signal': 'insufficient_data', 
            'strength': 0, 
            'recommendation': 'no_data'
        }
    
    # Calculate %B (position within bands)
    bb_width = bb_upper - bb_lower
    if bb_width > 0:
        percent_b = (close - bb_lower) / bb_width
    else:
        percent_b = 0.5
    
    # Touching or breaking lower band
    if close <= bb_lower:
        signal = 'lower_band_touch'
        strength = min(100, int((bb_lower - close) / bb_lower * 1000 + 80))
        recommendation = 'strong_buy'
    # Touching or breaking upper band
    elif close >= bb_upper:
        signal = 'upper_band_touch'
        strength = min(100, int((close - bb_upper) / close * 1000 + 80))
        recommendation = 'strong_sell'
    # In lower half of bands (potential buy zone)
    elif percent_b < 0.3:
        signal = 'lower_zone'
        strength = int((0.3 - percent_b) / 0.3 * 60 + 40)
        recommendation = 'buy_zone'
    # In upper half of bands (potential sell zone)
    elif percent_b > 0.7:
        signal = 'upper_zone'
        strength = int((percent_b - 0.7) / 0.3 * 60 + 40)
        recommendation = 'sell_zone'
    # Middle zone (neutral)
    else:
        signal = 'middle_zone'
        strength = 50
        recommendation = 'neutral'
    
    return {
        'upper': bb_upper,
        'lower': bb_lower,
        'middle': bb_middle,
        'percent_b': percent_b,
        'signal': signal,
        'strength': strength,
        'recommendation': recommendation
    }