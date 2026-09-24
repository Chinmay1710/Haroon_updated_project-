import sys
import os
import sqlite3
from sqlalchemy import create_engine, text

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database.engine import get_engine, Base
from app.config import DATABASE_PATH

# Import all models
import app.models.customer
import app.models.measurement
import app.models.order
import app.models.payment
import app.models.expense
import app.models.settings
import app.models.worker
import app.models.stock

def get_db_columns(db_path, table_name):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute(f"PRAGMA table_info('{table_name}')")
    cols = {row['name']: row['type'] for row in cursor.fetchall()}
    conn.close()
    return cols

def main():
    print(f"Checking DB at {DATABASE_PATH}")
    if not os.path.exists(DATABASE_PATH):
        print("Database not found!")
        return

    # Base.metadata contains the SQLAlchemy defined schema
    for table_name, table in Base.metadata.tables.items():
        db_cols = get_db_columns(DATABASE_PATH, table_name)
        if not db_cols:
            print(f"Table {table_name} does not exist in DB!")
            continue
        
        sa_cols = {col.name: str(col.type) for col in table.columns}
        
        missing = set(sa_cols.keys()) - set(db_cols.keys())
        if missing:
            print(f"Table {table_name} is missing columns in DB: {missing}")
            for m in missing:
                print(f"  - {m}: {sa_cols[m]}")

if __name__ == "__main__":
    main()
