import sqlite3
import os
import sys

db_path = "scratch/restore_tmp/tailor_shop.db"
print(f"Checking extracted DB: {db_path}")

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    cur.execute("PRAGMA integrity_check;")
    integrity = cur.fetchone()[0]
    print(f"Integrity check: {integrity}")
    if integrity.lower() != "ok":
        print("INTEGRITY CHECK FAILED!")
        sys.exit(1)
        
    counts = {}
    for table in ['customers', 'orders', 'payments', 'workers', 'work_entries', 'shop_settings']:
        try:
            cur.execute(f"SELECT COUNT(*) FROM {table}")
            counts[table] = cur.fetchone()[0]
        except Exception as e:
            counts[table] = f"ERROR: {e}"
            
    print("Row counts:")
    for t, c in counts.items():
        print(f"  - {t}: {c}")
        
    conn.close()
    
except Exception as e:
    print(f"Failed to open database: {e}")
    sys.exit(1)
