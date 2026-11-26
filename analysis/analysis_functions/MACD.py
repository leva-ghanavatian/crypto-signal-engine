import pandas as pd

def analyze_macd(row):
    """
    Analyze MACD indicator
    
    Parameters:
    - row: Current candle data (dict or Series)
    - previous_row: Previous candle data (optional, for crossover detection)
    """
    macd = row['MACD_12_26_9']
    macd_signal = row['MACDs_12_26_9']
    macd_hist = row.get('MACDh_12_26_9', macd - macd_signal)
    
    if pd.isna(macd) or pd.isna(macd_signal):
         return {
            'value': None,
            'signal_line': None,
            'histogram': None,
            'signal': 'insufficient_data', 
            'strength': 0, 
            'recommendation': 'no_data'
        }
    
    prev_macd = row.get('prev_MACD_12_26_9', macd)
    prev_signal = row.get('prev_MACDs_12_26_9', macd_signal)
    
    if prev_macd <= prev_signal and macd > macd_signal:
        signal = 'bullish_crossover'
        strength = 85
        recommendation = 'strong_buy'

    elif prev_macd >= prev_signal and macd < macd_signal:
        signal = 'bearish_crossover'
        strength = 85
        recommendation = 'strong_sell'

    elif macd > macd_signal:
        if macd != 0:
            strength = min(100, int(65 + abs(macd_hist) / abs(macd) * 35))
        else:
            strength = 65
        signal = 'bullish'
        recommendation = 'buy'

    elif macd < macd_signal:
        if macd != 0:
            strength = min(100, int(65 + abs(macd_hist) / abs(macd) * 35))
        else:
            strength = 65
        signal = 'bearish'
        recommendation = 'sell'
    else:
        signal = 'neutral'
        strength = 50
        recommendation = 'hold'
    
    return {
        'value': macd,
        'signal_line': macd_signal,
        'histogram': macd_hist,
        'signal': signal,
        'strength': strength,
        'recommendation': recommendation
    }