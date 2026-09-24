import os
import sys
import sqlite3

sys.path.append("/Users/chinmay/Documents/Haroon_tailer")
from app.config import DATABASE_PATH

def migrate_missing_columns():
    print(f"Connecting to database at {DATABASE_PATH}")
    if not os.path.exists(DATABASE_PATH):
        print("Database does not exist!")
        return

    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    
    # 1. work_entries table
    cursor.execute("PRAGMA table_info(work_entries)")
    columns = [info[1] for info in cursor.fetchall()]
    if "is_settled" not in columns:
        print("Adding column 'is_settled' to work_entries")
        cursor.execute("ALTER TABLE work_entries ADD COLUMN is_settled BOOLEAN NOT NULL DEFAULT 0")

    # 2. worker_advances table
    cursor.execute("PRAGMA table_info(worker_advances)")
    columns = [info[1] for info in cursor.fetchall()]
    if "is_settled" not in columns:
        print("Adding column 'is_settled' to worker_advances")
        cursor.execute("ALTER TABLE worker_advances ADD COLUMN is_settled BOOLEAN NOT NULL DEFAULT 0")

    conn.commit()
    conn.close()
    print("Migration successful.")

if __name__ == '__main__':
    migrate_missing_columns()
