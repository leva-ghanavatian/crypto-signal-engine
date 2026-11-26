import pandas as pd
from sqlalchemy import create_engine
import urllib

def get_buy_recommendation(symbol=None, min_probability=70):
    """
    Fetch analysis results and return buy recommendations as percentages
    
    Parameters:
    - symbol: Specific symbol (optional, None for all)
    - min_probability: Minimum probability to show (default 70%)
    """
    try:
        # Connect to database
        params = urllib.parse.quote_plus(
            f'DRIVER={{ODBC Driver 17 for SQL Server}};'
            f'SERVER=localhost;'
            f'DATABASE=db_Trading;'
            f'Trusted_Connection=yes'
        )
        conn_str = f'mssql+pyodbc:///?odbc_connect={params}'
        engine = create_engine(conn_str)
        
        # Build query
        if symbol:
            query = f"""
                SELECT TOP 1 symbol, close, combined_score, combined_signal, buy_probability,
                       rsi_signal, macd_signal, bb_signal, analysis_date
                FROM tab_analysis_results 
                WHERE symbol = '{symbol}'
                ORDER BY timestamp DESC
            """
        else:
            query = f"""
                SELECT DISTINCT symbol, close, combined_score, combined_signal, buy_probability,
                       rsi_signal, macd_signal, bb_signal, analysis_date
                FROM (
                    SELECT *, ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY timestamp DESC) as rn
                    FROM tab_analysis_results
                ) t
                WHERE rn = 1 AND buy_probability >= {min_probability}
                ORDER BY buy_probability DESC
            """
        
        results = pd.read_sql(query, engine)
        
        if results.empty:
            print(f"📊 No strong buy signals found above {min_probability}%")
            return results
        
        # Print formatted recommendations
        print("\n" + "="*80)
        print(f"📈 BUY RECOMMENDATIONS (Probability > {min_probability}%)")
        print("="*80)
        
        for _, row in results.iterrows():
            print(f"\n🎯 {row['symbol']}")
            print(f"   💰 Price: {row['close']:,.0f}")
            print(f"   📊 Buy Probability: {row['buy_probability']:.1f}%")
            print(f"   🟢 Signal: {row['combined_signal']}")
            print(f"\n   📋 Indicator Details:")
            print(f"      • RSI: {row['rsi_signal']}")
            print(f"      • MACD: {row['macd_signal']}")
            print(f"      • Bollinger Bands: {row['bb_signal']}")
            print(f"   📅 Analysis: {row['analysis_date']}")
            print("-"*50)
        
        return results
        
    except Exception as e:
        print(f"❌ Error fetching recommendations: {e}")
        return pd.DataFrame()