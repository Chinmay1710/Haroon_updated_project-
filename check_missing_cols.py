import os
import sys

# Ensure the app module can be imported
sys.path.insert(0, os.path.abspath('.'))

from sqlalchemy import inspect
from app.database.engine import get_engine, Base
import app.models.customer
import app.models.measurement
import app.models.order
import app.models.payment
import app.models.expense
import app.models.settings
import app.models.worker
import app.models.stock

engine = get_engine()
insp = inspect(engine)

missing_columns = []

for table_name, table in Base.metadata.tables.items():
    if not insp.has_table(table_name):
        print(f"Table missing entirely: {table_name}")
        continue
    
    existing_cols = {c["name"] for c in insp.get_columns(table_name)}
    for col in table.columns:
        if col.name not in existing_cols:
            missing_columns.append(f"{table_name}.{col.name}")
            print(f"Missing column detected: {table_name}.{col.name} (type {col.type})")

print(f"Total missing columns in local DB: {len(missing_columns)}")
