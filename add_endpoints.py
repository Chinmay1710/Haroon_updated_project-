import re

def modify_file(filepath):
    with open(filepath, "r") as f:
        content = f.read()

    # Add handlers
    new_handlers = """
def handle_get_pending_orders(payload):
    from app.models.order import Order
    session = get_session()
    try:
        # Get only orders with remaining amount > 0
        orders = session.query(Order).filter(
            Order.status != 'CANCELLED',
            Order.total_amount > Order.paid_amount
        ).order_by(Order.order_date.desc()).all()
        
        data = []
        for o in orders:
            data.append({
                "id": o.id,
                "order_number": o.order_number,
                "customer_name": o.customer.name if o.customer else "Unknown",
                "customer_id": o.customer.id if o.customer else None,
                "customer_mobile": o.customer.mobile if o.customer else "",
                "total_amount": o.total_amount,
                "remaining_amount": o.remaining_amount,
                "delivery_date": o.delivery_date.isoformat() if o.delivery_date else "",
                "updated_at": o.updated_at.isoformat() if hasattr(o, "updated_at") and o.updated_at else ""
            })
        return {"status": "success", "data": data}
    finally:
        session.close()

def handle_get_recent_payments(payload):
    from app.models.payment import Payment
    session = get_session()
    try:
        limit = payload.get("limit", 100)
        payments = session.query(Payment).order_by(Payment.payment_date.desc(), Payment.id.desc()).limit(limit).all()
        data = []
        for p in payments:
            data.append({
                "id": p.id,
                "order_id": p.order_id,
                "order_number": p.order.order_number if p.order else "",
                "customer_name": p.customer.name if p.customer else "",
                "customer_mobile": p.customer.mobile if p.customer else "",
                "amount": p.amount,
                "payment_date": p.payment_date.isoformat() if p.payment_date else "",
                "payment_method": p.payment_method,
                "remaining_amount": getattr(p.order, 'remaining_amount', 0) if p.order else 0,
                "updated_at": p.updated_at.isoformat() if hasattr(p, "updated_at") and p.updated_at else ""
            })
        return {"status": "success", "data": data}
    finally:
        session.close()
"""
    if "def handle_get_pending_orders" not in content:
        # Insert before ROUTER_MAP
        content = content.replace("ROUTER_MAP = {", new_handlers + "\nROUTER_MAP = {")

    # Update ROUTER_MAP
    if '"get_pending_orders": handle_get_pending_orders,' not in content:
        content = content.replace('"get_all_orders": handle_get_all_orders,', 
            '"get_all_orders": handle_get_all_orders,\n    "get_pending_orders": handle_get_pending_orders,')
    if '"get_recent_payments": handle_get_recent_payments,' not in content:
        content = content.replace('"get_all_payments": handle_get_all_payments,', 
            '"get_all_payments": handle_get_all_payments,\n    "get_recent_payments": handle_get_recent_payments,')

    with open(filepath, "w") as f:
        f.write(content)
    print(f"Updated {filepath}")

modify_file("app/web/admin_routes.py")
modify_file("app/ui/web_bridge.py")
