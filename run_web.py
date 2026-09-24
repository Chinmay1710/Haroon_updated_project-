"""
Standalone web server runner.
Run this to start the Tailor Shop web server without the desktop GUI.
The full admin panel will be accessible at /app/dashboard or /admin.
The worker portal remains at /.
"""
import uvicorn
import os
import sys

if __name__ == "__main__":
    # Ensure project root is in path
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    
    # Initialize database
    from app.config import ensure_dirs
    ensure_dirs()
    from app.database.engine import init_db
    init_db()
    
    from app.web.server import app
    
    print("=========================================")
    print(" Haroon Tailor Web App is starting...")
    print(" Admin Portal: http://localhost:8000/admin")
    print("               http://localhost:8000/app/dashboard")
    print(" Worker Portal: http://localhost:8000/")
    print("=========================================")
    
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
