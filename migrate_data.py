import os
import sys
from sqlalchemy import create_engine, MetaData
from sqlalchemy.orm import sessionmaker

# Path to local SQLite
SQLITE_URL = "sqlite:////Users/chinmay/Library/Application Support/TailorShopManager/data/tailor_shop.db"

# Path to remote Postgres (Neon DB)
# Ensure we use postgresql:// for SQLAlchemy
NEON_URL = os.environ.get("DATABASE_URL")
if NEON_URL and NEON_URL.startswith("postgres://"):
    NEON_URL = NEON_URL.replace("postgres://", "postgresql://", 1)

import sqlite3
import datetime

def migrate_data():
    if not NEON_URL:
        print("Please set DATABASE_URL environment variable.")
        return

    print("Connecting to Neon DB (Destination)...")
    neon_engine = create_engine(NEON_URL, pool_pre_ping=True)
    neon_meta = MetaData()
    neon_meta.reflect(bind=neon_engine)
    
    # Tables in correct order (Postgres topological sort)
    tables = [t.name for t in neon_meta.sorted_tables]

    # Connect to SQLite raw
    sqlite_path = "/Users/chinmay/Library/Application Support/TailorShopManager/data/tailor_shop.db"
    conn = sqlite3.connect(sqlite_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    with neon_engine.connect() as neon_conn:
        with neon_conn.begin():
            for table_name in tables:
                print(f"Migrating data for table: {table_name}...")
                try:
                    cursor.execute(f"SELECT * FROM {table_name}")
                    rows = cursor.fetchall()
                except sqlite3.OperationalError:
                    print(f"  - Table {table_name} does not exist in SQLite. Skipping.")
                    continue
                    
                if not rows:
                    print(f"  - Table {table_name} is empty. Skipping.")
                    continue
                    
                # Fix up data for postgres
                columns = rows[0].keys()
                pg_table = neon_meta.tables[table_name]
                
                data = []
                for row in rows:
                    row_dict = dict(row)
                    # Clean up data based on PG types
                    for col_name in columns:
                        val = row_dict[col_name]
                        col_type_str = str(pg_table.columns[col_name].type).lower()
                        
                        if val == "inches" and "time" in col_type_str:
                            row_dict[col_name] = datetime.datetime.now()
                        elif val == "" and "time" in col_type_str:
                            row_dict[col_name] = None
                            
                        # Force boolean cast for boolean columns (Postgres requires strictly bool)
                        if "bool" in col_type_str:
                            if val in (0, '0', 'False', 'false', '', None):
                                row_dict[col_name] = False
                            elif val in (1, '1', 'True', 'true'):
                                row_dict[col_name] = True
                            else:
                                # For garbage data like '₹'
                                row_dict[col_name] = True
                    data.append(row_dict)
                
                # Delete existing data on destination just in case
                neon_conn.execute(pg_table.delete())
                
                # Insert into neon
                print(f"  - Inserting {len(data)} rows into {table_name}...")
                neon_conn.execute(pg_table.insert(), data)
                
            print("All tables migrated successfully!")
            
    # Fix sequences for auto-incrementing primary keys in Postgres
    print("Fixing PostgreSQL sequences...")
    with neon_engine.connect() as neon_conn:
        with neon_conn.begin():
            for table_name in tables:
                if 'id' in neon_meta.tables[table_name].columns:
                    seq_name = f"{table_name}_id_seq"
                    try:
                        neon_conn.execute(f"SELECT setval('{seq_name}', COALESCE((SELECT MAX(id)+1 FROM {table_name}), 1), false);")
                        print(f"  - Sequence {seq_name} reset.")
                    except Exception as e:
                        print(f"  - Could not reset sequence for {table_name}: {e}")

if __name__ == "__main__":
    migrate_data()
