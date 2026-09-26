from __future__ import annotations
"""Safe database schema auto-migrations for SQLite."""

import os
import sqlite3
import datetime
from sqlalchemy import text
from app.config import DATABASE_PATH, BACKUP_DEFAULT_DIR
from app.utils.logger import get_logger

logger = get_logger("migrations")


def safe_db_backup(source_db_path: str) -> str | None:
    """Safely back up the SQLite database using native backup API."""
    if not os.path.exists(source_db_path):
        return None  # No database to back up

    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_filename = f"TailorShop_PreMigrationBackup_{timestamp}.db"
    backup_path = os.path.join(BACKUP_DEFAULT_DIR, backup_filename)

    try:
        # Connect to source and destination
        src_conn = sqlite3.connect(source_db_path)
        dest_conn = sqlite3.connect(backup_path)
        
        # Perform safe backup (locks safely, flushes WAL)
        with dest_conn:
            src_conn.backup(dest_conn)
            
        src_conn.close()
        dest_conn.close()
        logger.info(f"Safe pre-migration backup created at {backup_path}")
        return backup_path
    except Exception as e:
        logger.error(f"Failed to create pre-migration backup: {e}")
        raise RuntimeError(f"Migration aborted due to backup failure: {e}")


def get_sqlite_type(alchemy_type) -> str:
    """Map SQLAlchemy types to safe SQLite types for ALTER TABLE."""
    type_str = str(alchemy_type).upper()
    if "INT" in type_str:
        return "INTEGER"
    if "FLOAT" in type_str or "REAL" in type_str or "NUMERIC" in type_str:
        return "REAL"
    if "BOOL" in type_str:
        return "BOOLEAN"
    if "DATETIME" in type_str or "DATE" in type_str or "TIME" in type_str:
        return "DATETIME"
    return "TEXT"


def get_sqlite_default(col) -> str:
    """Determine a safe SQLite DEFAULT clause based on column."""
    if col.server_default:
        return f"DEFAULT {col.server_default.arg}"
        
    # Standard SQLite safe defaults for ADD COLUMN if not explicitly provided
    sqlite_type = get_sqlite_type(col.type)
    if sqlite_type == "INTEGER" or sqlite_type == "REAL":
        return "DEFAULT 0"
    if sqlite_type == "BOOLEAN":
        return "DEFAULT 0" # False
    if sqlite_type == "DATETIME":
        return "DEFAULT '2024-01-01 00:00:00'"
    return "DEFAULT ''"


def auto_migrate(engine, Base):
    """
    Idempotent, additive-only migration.
    Inspects all tables in the live database and adds missing columns 
    defined in the SQLAlchemy metadata. Works for both SQLite and Postgres.
    """
    logger.info("Starting safe database auto-migration check...")
    
    if engine.dialect.name == "sqlite" and not os.path.exists(DATABASE_PATH):
        logger.info("No existing database found. Skipping migration. create_all() will handle it.")
        return

    from sqlalchemy import inspect
    insp = inspect(engine)
    
    # Dry run
    needs_migration = False
    try:
        for table_name, table in Base.metadata.tables.items():
            if not insp.has_table(table_name):
                continue
            existing_cols = {c["name"] for c in insp.get_columns(table_name)}
            for col in table.columns:
                if col.name not in existing_cols:
                    needs_migration = True
                    break
            if needs_migration:
                break
    except Exception as e:
        logger.error(f"Failed during migration dry-run: {e}")
        return

    if not needs_migration:
        logger.info("Database schema is up to date. No migration required.")
        return

    if engine.dialect.name == "sqlite":
        safe_db_backup(DATABASE_PATH)
    
    try:
        with engine.begin() as conn:
            for table_name, table in Base.metadata.tables.items():
                if not insp.has_table(table_name):
                    continue
                
                existing_cols = {c["name"] for c in insp.get_columns(table_name)}
                
                for col in table.columns:
                    if col.name not in existing_cols:
                        logger.info(f"Missing column detected: {table_name}.{col.name}")
                        
                        col_type = get_sqlite_type(col.type) if engine.dialect.name == "sqlite" else str(col.type.compile(engine.dialect))
                        
                        default_clause = ""
                        if engine.dialect.name == "sqlite":
                            default_clause = get_sqlite_default(col)
                        else:
                            if col.server_default:
                                default_clause = f"DEFAULT {col.server_default.arg}"
                            elif str(col.type).startswith("BOOLEAN") or str(col.type).startswith("BOOL"):
                                default_clause = "DEFAULT FALSE"
                            elif "INT" in str(col.type) or "FLOAT" in str(col.type) or "REAL" in str(col.type):
                                default_clause = "DEFAULT 0"
                            elif str(col.type).startswith("VARCHAR") or str(col.type).startswith("STRING"):
                                default_clause = "DEFAULT ''"
                        
                        alter_sql = f"ALTER TABLE {table_name} ADD COLUMN {col.name} {col_type} {default_clause}"
                        
                        logger.info(f"Executing: {alter_sql}")
                        conn.execute(text(alter_sql))
                        logger.info(f"Successfully added column {table_name}.{col.name}")
                        
        logger.info("Auto-migration completed successfully.")
    except Exception as e:
        logger.error(f"FATAL ERROR during auto-migration: {e}")
        if engine.dialect.name == "sqlite":
            raise RuntimeError(f"Database migration failed. To prevent corruption, application will not start: {e}")
