from datetime import datetime

# Import analysis functions
from .analysis_functions.RSI import analyze_rsi 
from .analysis_functions.RSI_EMA import analyze_rsi_ema 
from .analysis_functions.MACD import analyze_macd 
from .analysis_functions.BollingerBands import analyze_bbands 
from .analysis_functions.Momentum import analyze_momentum
from .analysis_functions.TrendStrength import analyze_trend_strength
from .analysis_functions.PriceAction import analyze_price_action


def analyze_crypto_row(row, prev_row=None):
    """
    Master function that takes one row, runs all analyses, and returns combined result
    """
    # Add previous row data if available for crossover detection
    if prev_row is not None:
        row['prev_RSI'] = prev_row.get('RSI')
        row['prev_RSI_EMA'] = prev_row.get('RSI_EMA')
        row['prev_MACD_12_26_9'] = prev_row.get('MACD_12_26_9')
        row['prev_MACDs_12_26_9'] = prev_row.get('MACDs_12_26_9')
    
    # Run individual analyses
    rsi_result = analyze_rsi(row)
    rsi_ema_result = analyze_rsi_ema(row)
    macd_result = analyze_macd(row)
    bb_result = analyze_bbands(row)
    momentum_result = analyze_momentum(row, prev_row)
    trend_result = analyze_trend_strength(row)
    price_action_result = analyze_price_action(row, prev_row)
    
    # Calculate combined score (weighted average)
    weights = {
        'rsi': 2,          # Higher weight to RSI
        'rsi_ema': 1.5,
        'macd': 2.5,       # Highest weight to MACD
        'bb': 2,
        'momentum': 3,      # Highest weight - catches trends early
        'trend': 2 ,
        'price_action': 1.5
    }
    
    weighted_strength = (
        rsi_result['strength'] * weights['rsi'] +
        (100 - rsi_ema_result['strength'] if 'bearish' in rsi_ema_result['signal'] else rsi_ema_result['strength']) * weights['rsi_ema'] +
        macd_result['strength'] * weights['macd'] +
        bb_result['strength'] * weights['bb'] +
        momentum_result['strength'] * weights['momentum'] +
        trend_result['strength'] * weights['trend'] + 
        price_action_result['strength'] * weights['price_action']
    )
    total_weight = sum(weights.values())
    combined_score = int(weighted_strength / total_weight)
    
    # Determine overall signal based on combined score
    if combined_score >= 80:
        combined_signal = 'STRONG_BUY'
        buy_probability = combined_score
    elif combined_score >= 65:
        combined_signal = 'BUY'
        buy_probability = combined_score
    elif combined_score >= 45:
        combined_signal = 'NEUTRAL'
        buy_probability = 50
    elif combined_score >= 25:
        combined_signal = 'SELL'
        buy_probability = 100 - combined_score
    else:
        combined_signal = 'STRONG_SELL'
        buy_probability = 0
    
    # Prepare result for database
    result = {
        'symbol': row['symbol'],
        'timestamp': row['timestamp'],
        'closing_price': row['close'],
        
        # RSI
        'rsi_value': rsi_result['value'],
        'rsi_signal': rsi_result['signal'],
        'rsi_strength': rsi_result['strength'],
        'rsi_recommendation': rsi_result['recommendation'],
        
        # RSI-EMA
        'rsi_ema_value': rsi_ema_result['value'],
        'rsi_ema_signal': rsi_ema_result['signal'],
        'rsi_ema_strength': rsi_ema_result['strength'],
        'rsi_ema_recommendation': rsi_ema_result['recommendation'],
        
        # MACD
        'macd_value': macd_result['value'],
        'macd_signal_line': macd_result['signal_line'],
        'macd_signal': macd_result['signal'],
        'macd_strength': macd_result['strength'],
        'macd_recommendation': macd_result['recommendation'],
        
        # BBANDS
        'bb_upper': bb_result['upper'],
        'bb_lower': bb_result['lower'],
        'bb_middle': bb_result['middle'],
        'bb_signal': bb_result['signal'],
        'bb_strength': bb_result['strength'],
        'bb_recommendation': bb_result['recommendation'],
        
        # Combined results
        'combined_score': combined_score,
        'combined_signal': combined_signal,
        'buy_probability': buy_probability,
        'analysis_date': datetime.now()
    }
    
    return result