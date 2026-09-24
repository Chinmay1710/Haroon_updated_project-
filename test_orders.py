import sys
import os
sys.path.append(os.getcwd())
from app.database.engine import init_db
from app.services.order_service import OrderService

init_db()
srv = OrderService()
try:
    orders = srv.get_all_orders()
    print(f"Total orders: {len(orders)}")
    for o in orders:
        print(f"Order: {o.id} - {o.order_number}")
except Exception as e:
    import traceback
    traceback.print_exc()
