import os
import sys
sys.path.insert(0, os.path.abspath('.'))

from app.web.admin_routes import handle_add_worker

payload = {
    "name": "Test Worker 2",
    "phone": "1234567890",
    "pin": "1234",
    "worker_type": "PIECE_RATE",
    "worker_role": "STITCHING",
    "daily_rate": ""
}
print(handle_add_worker(payload))
