import sqlite3
import os
from app.config import DATABASE_PATH

print(f"DATABASE PATH: {DATABASE_PATH}")
print(f"EXISTS: {os.path.exists(DATABASE_PATH)}")
if os.path.exists(DATABASE_PATH):
    print(f"SIZE: {os.path.getsize(DATABASE_PATH)} bytes")
    conn = sqlite3.connect(DATABASE_PATH)
    cur = conn.cursor()
    for table in ['customers', 'orders', 'payments']:
        try:
            cur.execute(f"SELECT COUNT(*) FROM {table}")
            print(f"{table.upper()} COUNT: {cur.fetchone()[0]}")
        except Exception as e:
            print(f"{table.upper()} COUNT: ERROR ({e})")
    conn.close()
