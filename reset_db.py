import os
import sys

# Try to get database URL from environment or prompt
db_url = os.environ.get("DATABASE_URL")
if not db_url:
    print("No DATABASE_URL found in environment variables.")
    print("If you want to clear the REMOTE database, run this script like this:")
    print('DATABASE_URL="your-render-postgresql-url" python3 reset_db.py')
    print("\nIf you want to clear your LOCAL database, just press ENTER.")
    print("To abort, press CTRL+C.")
    
    choice = input("\nContinue with local database? (y/N): ")
    if choice.lower() != 'y':
        sys.exit(0)

# Set it so engine.py picks it up
if db_url:
    os.environ["DATABASE_URL"] = db_url

from app.database.engine import get_session, get_engine, Base
from app.models.customer import Customer
from app.models.order import Order, OrderItem, OrderMeasurement
from app.models.payment import Payment
from app.models.measurement import MeasurementProfile, MeasurementValue
from app.models.expense import Expense
from app.models.worker import Worker, WorkEntry, WorkerAdvance
from app.models.stock import StockItem, StockUsage

engine = get_engine()
session = get_session()

print("\nWARNING: This will PERMANENTLY DELETE all data from the database.")
print(f"Connected to: {engine.url}")
confirm = input("Type 'DELETE' to confirm: ")

if confirm == 'DELETE':
    print("Deleting all data...")
    try:
        # Delete in order to respect foreign key constraints
        session.query(StockUsage).delete()
        session.query(StockItem).delete()
        
        session.query(WorkerAdvance).delete()
        session.query(WorkEntry).delete()
        session.query(Worker).delete()
        
        session.query(Expense).delete()
        
        session.query(Payment).delete()
        session.query(OrderMeasurement).delete()
        session.query(OrderItem).delete()
        session.query(Order).delete()
        
        session.query(MeasurementValue).delete()
        session.query(MeasurementProfile).delete()
        
        session.query(Customer).delete()
        
        session.commit()
        print("✅ Database successfully wiped clean!")
    except Exception as e:
        session.rollback()
        print(f"❌ Error while deleting data: {e}")
        
        # Fallback to dropping all tables and recreating them
        print("Attempting to drop and recreate all tables instead...")
        try:
            Base.metadata.drop_all(engine)
            Base.metadata.create_all(engine)
            print("✅ Database tables dropped and recreated fresh!")
        except Exception as e2:
            print(f"❌ Failed to drop/recreate tables: {e2}")
    finally:
        session.close()
else:
    print("Aborted.")
