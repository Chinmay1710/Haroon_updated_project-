import sys, os, json
from datetime import date
sys.path.append(os.getcwd())
from app.database.engine import init_db
from app.services.order_service import OrderService
from app.services.customer_service import CustomerService

init_db()
cs = CustomerService()
osrv = OrderService()

# Create a test customer if not exists
customers = cs.search_customers("test")
if not customers:
    c = cs.create_customer("test", "1234567890", "")
else:
    c = customers[0]

items = [{
    "clothing_type": "Shirt",
    "quantity": 1,
    "price": 100,
    "measurements": {"Chest": "40", "Length": "30"},
    "image_base64": None,
    "notes": "Test notes"
}]

order = osrv.create_order(
    customer_id=c.id,
    items=items,
    order_date=date.today(),
    delivery_date=None,
    special_instructions="Test",
    advance_amount=0,
    payment_method="Cash"
)

print("Created order", order.id)

# Now fetch it like web_bridge does
from app.database.engine import get_session
from app.models.order import Order
session = get_session()
o = session.query(Order).filter(Order.id == order.id).first()
for item in o.items:
    print("Item ID:", item.id)
    print("Measurements:", item.measurements)

session.close()
