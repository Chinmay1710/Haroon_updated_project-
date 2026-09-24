import os
import sys
from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.config import DATABASE_PATH
from app.database.firebase_engine import get_firestore_client, get_collection
from app.utils.logger import get_logger

logger = get_logger("migration")

def migrate_table(conn, table_name, collection_name):
    try:
        rows = conn.execute(text(f"SELECT * FROM {table_name}")).mappings().all()
        ref = get_collection(collection_name)
        for r in rows:
            data = dict(r)
            if "_sa_instance_state" in data: del data["_sa_instance_state"]
            ref.document(str(r['id'])).set(data)
        logger.info(f"✅ Migrated {len(rows)} records from {table_name}.")
        return rows
    except OperationalError:
        logger.warning(f"⚠️ Table {table_name} does not exist. Skipping.")
        return []

def migrate():
    if not os.path.exists(DATABASE_PATH):
        logger.error(f"Database not found at {DATABASE_PATH}. Nothing to migrate.")
        return

    logger.info("Connecting to local SQLite database...")
    engine = create_engine(f"sqlite:///{DATABASE_PATH}")
    db = get_firestore_client()
    
    with engine.connect() as conn:
        tables = [
            ("customers", "customers"),
            ("measurement_profiles", "measurement_profiles"),
            ("measurement_values", "measurement_values"),
            ("orders", "orders"),
            ("order_items", "order_items"),
            ("measurement_snapshots", "measurement_snapshots"),
            ("payments", "payments"),
            ("expenses", "expenses"),
            ("stock_items", "stock_items"),
            ("stock_usage", "stock_usage"),
            ("workers", "workers"),
            ("work_entries", "work_entries"),
            ("worker_advances", "worker_advances"),
            ("garment_rates", "garment_rates")
        ]
        
        migrated_data = {}
        for sql_table, fb_collection in tables:
            rows = migrate_table(conn, sql_table, fb_collection)
            migrated_data[fb_collection] = rows
            
        # Update IDs
        logger.info("Updating Auto-Increment counters in Firebase...")
        counters = get_collection("_counters")
        
        for collection_name, rows in migrated_data.items():
            max_id = max([r['id'] for r in rows]) if rows else 0
            if max_id > 0:
                counters.document(collection_name).set({"seq": max_id})
                
    logger.info("Migration to Firebase completed successfully!")
    logger.info("You can now safely run the application. It will read/write exclusively to Firebase.")

if __name__ == "__main__":
    migrate()
