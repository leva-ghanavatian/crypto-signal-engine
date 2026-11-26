import pandas as pd

def analyze_momentum(row, prev_row=None):
    """
    Analyze price momentum and rate of change to detect trends early
    
    Parameters:
    - row: Current candle data
    - prev_row: Previous candle data
    """
    close = row['close']
    
    # Get different timeframe price changes
    # Price change from 1 period ago
    price_change_1 = row.get('price_change_1', 0)
    
    # Get ROC (Rate of Change) if available from pandas_ta
    roc = row.get('ROC_10', 0)  # 10-period Rate of Change
    
    # Calculate percentage changes if we have previous row
    if prev_row is not None:
        prev_close = prev_row.get('close', close)
        price_change_pct = ((close - prev_close) / prev_close) * 100
        
        # Acceleration (change in momentum)
        prev_change = prev_row.get('price_change_pct', 0)
        acceleration = price_change_pct - prev_change
    else:
        price_change_pct = 0
        acceleration = 0
    
    # Get Volume Price Trend
    vpt = row.get('VPT', 0)
    
    # Determine momentum signal
    momentum_score = 0
    
    # Strong positive momentum (> 2% increase)
    if price_change_pct > 2:
        signal = 'strong_bullish_momentum'
        strength = min(100, 70 + int(price_change_pct * 5))
        recommendation = 'early_buy'
        momentum_score = 25
    # Moderate positive momentum (0.5-2% increase)
    elif price_change_pct > 0.5:
        signal = 'bullish_momentum'
        strength = 60 + int(price_change_pct * 10)
        recommendation = 'watch_buy'
        momentum_score = 15
    # Small positive movement
    elif price_change_pct > 0:
        signal = 'slight_bullish'
        strength = 55
        recommendation = 'neutral_bullish'
        momentum_score = 8
    # Small negative movement
    elif price_change_pct > -0.5:
        signal = 'slight_bearish'
        strength = 45
        recommendation = 'neutral_bearish'
        momentum_score = 5
    # Moderate negative momentum
    elif price_change_pct > -2:
        signal = 'bearish_momentum'
        strength = 30 + int(abs(price_change_pct) * 5)
        recommendation = 'watch_sell'
        momentum_score = 2
    # Strong negative momentum
    else:
        signal = 'strong_bearish_momentum'
        strength = min(100, 30 + int(abs(price_change_pct) * 10))
        recommendation = 'early_sell'
        momentum_score = 0
    
    # Boost score if acceleration is increasing
    if acceleration > 0.5:
        momentum_score += 10
        signal += "_accelerating"
    
    # ROC confirmation
    if roc > 2:
        momentum_score += 5
    elif roc < -2:
        momentum_score -= 5
    
    return {
        'value': price_change_pct,
        'roc': roc,
        'acceleration': acceleration,
        'signal': signal,
        'strength': strength,
        'momentum_score': momentum_score,
        'recommendation': recommendation
    }