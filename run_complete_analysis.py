import urllib
import sys
import os
from sqlalchemy import create_engine
import pandas as pd

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from analysis.indicator_analyzer import analyze_crypto_row
from database.save_analysis_to_db import save_analysis_results
from database.get_buy_signals import get_buy_recommendation

def process_all_crypto_analyses():
    """
    Main function to process all rows from tab_calculated_60 and generate analyses
    """
    try:
        # Load raw data
        params = urllib.parse.quote_plus(
            f'DRIVER={{ODBC Driver 17 for SQL Server}};'
            f'SERVER=localhost;'
            f'DATABASE=db_Trading;'
            f'Trusted_Connection=yes'
        )
        conn_str = f'mssql+pyodbc:///?odbc_connect={params}'
        engine = create_engine(conn_str)
        
        # Read all data, sorted by symbol and timestamp
        df = pd.read_sql("""
            SELECT * FROM tab_calculated_60 
            ORDER BY symbol, timestamp
        """, engine)
        
        print(f"📊 Loaded {len(df)} rows from database")
        
        results_list = []
        
        # Process each symbol separately
        for symbol in df['symbol'].unique():
            symbol_df = df[df['symbol'] == symbol].sort_values('timestamp')
            print(f"📈 Analyzing {symbol}... {len(symbol_df)} candles")
            
            # Analyze each row with previous row context
            for i in range(len(symbol_df)):
                current_row = symbol_df.iloc[i]
                prev_row = symbol_df.iloc[i-1] if i > 0 else None
                
                result = analyze_crypto_row(current_row, prev_row)
                results_list.append(result)
        
        # Convert results to DataFrame
        results_df = pd.DataFrame(results_list)
        
        # Save to database
        save_analysis_results(results_df)
        print("saved")
        
        # Get top recommendations
        # recommendations = get_buy_recommendation(min_probability=65)
        
        return results_df
        
    except Exception as e:
        print(f"❌ Error processing analyses: {e}")
        return pd.DataFrame(), pd.DataFrame()
    
process_all_crypto_analyses()    