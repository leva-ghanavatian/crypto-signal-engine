import pandas as pd

def analyze_price_action(row, prev_row=None):
    """
    Analyze price action for early trend detection
    """
    close = row['close']
    high = row['high']
    low = row['low']
    open_price = row['open']
    
    if prev_row is None:
        return {
            'signal': 'insufficient_data',
            'strength': 50,
            'recommendation': 'hold'
        }
    
    prev_close = prev_row.get('close', close)
    prev_high = prev_row.get('high', high)
    prev_low = prev_row.get('low', low)
    prev_open = prev_row.get('open', open_price)
    
    # Calculate candlestick patterns
    body = abs(close - open_price)
    upper_wick = high - max(close, open_price)
    lower_wick = min(close, open_price) - low
    
    # Bullish engulfing
    is_bullish_engulfing = (close > prev_close and 
                           open_price < prev_close and 
                           close > prev_high)
    
    # Hammer (reversal pattern)
    is_hammer = (lower_wick > body * 2 and 
                upper_wick < body * 0.5 and
                body > 0)
    
    # Bullish piercing pattern
    is_piercing = (prev_close > prev_open and 
                  close > prev_open and 
                  close < prev_close)
    
    # Higher highs, higher lows (uptrend)
    is_higher_high = high > prev_high
    is_higher_low = low > prev_low
    
    # Momentum detection
    if is_bullish_engulfing:
        signal = 'bullish_engulfing'
        strength = 90
        recommendation = 'strong_buy_signal'
    elif is_hammer and close > open_price:
        signal = 'hammer_reversal'
        strength = 80
        recommendation = 'buy_signal'
    elif is_piercing:
        signal = 'piercing_pattern'
        strength = 75
        recommendation = 'buy_signal'
    elif is_higher_high and is_higher_low:
        signal = 'uptrend_confirmed'
        strength = 70
        recommendation = 'bullish'
    elif is_higher_high:
        signal = 'higher_highs'
        strength = 60
        recommendation = 'watch_bullish'
    elif is_higher_low:
        signal = 'higher_lows'
        strength = 55
        recommendation = 'watch_bullish'
    else:
        signal = 'neutral_price_action'
        strength = 50
        recommendation = 'neutral'
    
    return {
        'signal': signal,
        'strength': strength,
        'body': body,
        'upper_wick': upper_wick,
        'lower_wick': lower_wick,
        'recommendation': recommendation
    }