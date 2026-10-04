import os
import sys

# Add the project root to the python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.database.engine import get_engine, Base

# Import all models to ensure they are registered with Base.metadata
import app.models.customer      # noqa: F401
import app.models.measurement   # noqa: F401
import app.models.order         # noqa: F401
import app.models.payment       # noqa: F401
import app.models.expense       # noqa: F401
import app.models.settings      # noqa: F401
import app.models.worker        # noqa: F401
import app.models.stock         # noqa: F401

def reset_database():
    try:
        engine = get_engine()
        print(f"Connected to database: {engine.url.render_as_string(hide_password=True)}")
        
        print("Dropping all tables...")
        Base.metadata.drop_all(engine)
        
        print("Creating all tables from scratch...")
        Base.metadata.create_all(engine)
        
        print("✅ Successfully reset database! All orders and customers will now start from 1.")
    except Exception as e:
        print(f"❌ Error resetting database: {e}")

if __name__ == "__main__":
    print("\n" + "="*50)
    print("DANGER: WIPE ENTIRE DATABASE")
    print("="*50)
    confirm = input("⚠️ Are you sure you want to DELETE ALL DATA? This cannot be undone! (yes/no): ")
    if confirm.strip().lower() == "yes":
        reset_database()
    else:
        print("Cancelled.")
