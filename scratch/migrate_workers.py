import os
import sys
import sqlite3

# Import from config to get the correct database path
sys.path.append("/Users/chinmay/Documents/Haroon_tailer")
from app.config import DATABASE_PATH

def migrate_workers():
    print(f"Connecting to database at {DATABASE_PATH}")
    if not os.path.exists(DATABASE_PATH):
        print("Database does not exist!")
        return

    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    
    # Check existing columns
    cursor.execute("PRAGMA table_info(workers)")
    columns = [info[1] for info in cursor.fetchall()]
    
    if "pin" not in columns:
        print("Adding column 'pin'")
        cursor.execute("ALTER TABLE workers ADD COLUMN pin VARCHAR(4) NOT NULL DEFAULT '0000'")
        
    if "worker_type" not in columns:
        print("Adding column 'worker_type'")
        cursor.execute("ALTER TABLE workers ADD COLUMN worker_type VARCHAR(20) NOT NULL DEFAULT 'PIECE_RATE'")
        
    if "worker_role" not in columns:
        print("Adding column 'worker_role'")
        cursor.execute("ALTER TABLE workers ADD COLUMN worker_role VARCHAR(20) NOT NULL DEFAULT 'STITCHING'")
        
    if "daily_rate" not in columns:
        print("Adding column 'daily_rate'")
        cursor.execute("ALTER TABLE workers ADD COLUMN daily_rate FLOAT NOT NULL DEFAULT 0.0")

    conn.commit()
    conn.close()
    print("Migration successful.")

if __name__ == '__main__':
    migrate_workers()
