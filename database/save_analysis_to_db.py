from sqlalchemy import create_engine
import urllib

def save_analysis_results(results_df):
    """
    Save analysis results to database
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
        
        # Save to analysis table
        results_df.to_sql('tab_analysis_results', engine, 
                         index=False, if_exists='replace')
        
        print(f"✅ Saved {len(results_df)} analysis results to database")
        
    except Exception as e:
        print(f"❌ Error saving analysis: {e}")