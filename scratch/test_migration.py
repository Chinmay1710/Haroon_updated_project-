import sys
import os
import sqlite3
import shutil

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.config import DATABASE_PATH, BACKUP_DEFAULT_DIR
from app.database.engine import init_db, get_engine
from app.utils.logger import get_logger

logger = get_logger("test_migration")

# OVERRIDE DATABASE PATH TO PREVENT DELETING LIVE DATA
import app.config
import app.database.engine
TEST_DB_PATH = os.path.join(app.config.APP_DATA_DIR, "data", "test_tailor_shop.db")
app.config.DATABASE_PATH = TEST_DB_PATH
app.database.engine.DATABASE_PATH = TEST_DB_PATH
DATABASE_PATH = TEST_DB_PATH

def setup_old_db():
    if os.path.exists(DATABASE_PATH):
        os.remove(DATABASE_PATH)
    
    # Create old schema
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    
    # Create shop_settings WITHOUT dictation_language
    cursor.execute("""
        CREATE TABLE shop_settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            shop_name VARCHAR(200),
            owner_name VARCHAR(200),
            phone VARCHAR(20),
            address TEXT,
            currency VARCHAR(10),
            measurement_unit VARCHAR(10),
            date_format VARCHAR(20),
            receipt_paper_size VARCHAR(10),
            backup_location TEXT,
            auto_backup BOOLEAN,
            is_setup_done BOOLEAN,
            twilio_account_sid VARCHAR(255),
            twilio_auth_token VARCHAR(255),
            twilio_sender_number VARCHAR(20),
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL
        )
    """)
    cursor.execute("INSERT INTO shop_settings (shop_name, created_at, updated_at) VALUES ('Test Shop', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
    
    # Create workers WITHOUT worker_role
    cursor.execute("""
        CREATE TABLE workers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(100) NOT NULL,
            phone VARCHAR(20),
            login_pin VARCHAR(4),
            is_active BOOLEAN,
            created_at DATETIME NOT NULL
        )
    """)
    cursor.execute("INSERT INTO workers (name, created_at) VALUES ('Worker 1', CURRENT_TIMESTAMP)")
    
    # Create work_entries WITHOUT is_settled
    cursor.execute("""
        CREATE TABLE work_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            worker_id INTEGER,
            item_type VARCHAR(100),
            quantity INTEGER,
            rate_per_piece REAL,
            total_amount REAL,
            date DATETIME,
            created_at DATETIME NOT NULL
        )
    """)
    cursor.execute("INSERT INTO work_entries (worker_id, item_type, quantity, rate_per_piece, total_amount, date, created_at) VALUES (1, 'Shirt', 2, 100, 200, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
    
    # Create customers, orders, payments, etc.
    cursor.execute("""
        CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(100) NOT NULL,
            phone VARCHAR(20),
            address TEXT,
            created_at DATETIME NOT NULL
        )
    """)
    cursor.execute("INSERT INTO customers (name, phone, created_at) VALUES ('John Doe', '1234567890', CURRENT_TIMESTAMP)")
    
    cursor.execute("""
        CREATE TABLE orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER,
            order_number VARCHAR(50),
            status VARCHAR(20),
            total_amount REAL,
            created_at DATETIME NOT NULL
        )
    """)
    cursor.execute("INSERT INTO orders (customer_id, order_number, status, total_amount, created_at) VALUES (1, 'ORD-001', 'NEW', 1500, CURRENT_TIMESTAMP)")

    cursor.execute("""
        CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER,
            amount REAL,
            date DATETIME,
            created_at DATETIME NOT NULL
        )
    """)
    cursor.execute("INSERT INTO payments (order_id, amount, date, created_at) VALUES (1, 500, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")

    conn.commit()
    conn.close()

def get_counts():
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    
    counts = {}
    for table in ['customers', 'orders', 'payments', 'workers', 'work_entries', 'shop_settings']:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            counts[table] = cursor.fetchone()[0]
        except Exception:
            counts[table] = 0
            
    conn.close()
    return counts

def check_schema():
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info('shop_settings')")
    shop_cols = [r[1] for r in cursor.fetchall()]
    
    cursor.execute("PRAGMA table_info('workers')")
    worker_cols = [r[1] for r in cursor.fetchall()]
    
    cursor.execute("PRAGMA table_info('work_entries')")
    entry_cols = [r[1] for r in cursor.fetchall()]
    
    conn.close()
    
    return {
        'dictation_language_exists': 'dictation_language' in shop_cols,
        'worker_role_exists': 'worker_role' in worker_cols,
        'is_settled_exists': 'is_settled' in entry_cols
    }

def main():
    print("--- Setting up OLD schema database ---")
    setup_old_db()
    
    counts_before = get_counts()
    print("Counts Before Migration:", counts_before)
    
    schema_before = check_schema()
    print("Schema Before Migration:", schema_before)
    assert not schema_before['dictation_language_exists']
    assert not schema_before['worker_role_exists']
    assert not schema_before['is_settled_exists']
    
    # 1. Run Migration
    print("\n--- Running from app.database.engine import close_db; close_db(); init_db() Migration ---")
    from app.database.engine import close_db; close_db(); init_db()
    
    # 2. Check Results
    counts_after = get_counts()
    print("\nCounts After Migration:", counts_after)
    
    schema_after = check_schema()
    print("Schema After Migration:", schema_after)
    
    assert counts_before == counts_after, "DATA LOSS OCCURRED!"
    assert schema_after['dictation_language_exists'], "Migration failed to add dictation_language"
    assert schema_after['worker_role_exists'], "Migration failed to add worker_role"
    assert schema_after['is_settled_exists'], "Migration failed to add is_settled"
    
    print("\n[SUCCESS] Old Schema Migration completed safely.")
    
    # 3. Test Idempotency (Running again)
    print("\n--- Testing Idempotency (Running from app.database.engine import close_db; close_db(); init_db() again) ---")
    from app.database.engine import close_db; close_db(); init_db()
    print("[SUCCESS] Idempotency confirmed.")
    
    # 4. Test Fresh DB
    print("\n--- Testing Fresh DB ---")
    os.remove(DATABASE_PATH)
    from app.database.engine import close_db; close_db(); init_db()
    
    schema_fresh = check_schema()
    assert schema_fresh['dictation_language_exists']
    print("[SUCCESS] Fresh DB initialized successfully.")
    
if __name__ == "__main__":
    main()
