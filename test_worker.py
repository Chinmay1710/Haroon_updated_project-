import os
import sys
sys.path.insert(0, os.path.abspath('.'))

import app.models.customer
import app.models.measurement
import app.models.order
import app.models.payment
import app.models.expense
import app.models.settings
import app.models.worker
import app.models.stock

from app.services.worker_service import WorkerService
ws = WorkerService()
print(ws.get_all_workers())
