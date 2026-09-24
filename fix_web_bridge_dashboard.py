import re

with open("app/ui/web_bridge.py", "r", encoding="utf-8") as f:
    content = f.read()

# Fix get_payments_dashboard
content = re.sub(
    r'(elif action == "get_payments_dashboard":.*?)(elif action == "create_payment":)',
    r'''elif action == "get_payments_dashboard":
                from app.repositories.firebase.payment_repo import PaymentRepository
                try:
                    pr = PaymentRepository()
                    total_collected = sum(p.amount for p in pr.get_all())
                    today_payments = pr.get_today_total()
                    pending_payments = pr.get_total_pending()
                    
                    data = {
                        "total_collected": total_collected,
                        "pending_payments": pending_payments,
                        "today_payments": today_payments
                    }
                    response = {"status": "success", "data": data}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}
                    
            \2''',
    content,
    flags=re.DOTALL
)

# Fix get_worker_payment_summary
content = re.sub(
    r'(elif action == "get_worker_payment_summary":.*?)(elif action == "get_stock_payment_summary":)',
    r'''elif action == "get_worker_payment_summary":
                try:
                    worker_srv = self.services["worker"]
                    workers = worker_srv.get_all_workers()
                    
                    worker_list = []
                    total_dues = 0.0
                    total_advances = 0.0
                    total_earned = 0.0
                    
                    # Also need pending entries to calculate un-settled earned amounts
                    pending_entries = worker_srv.get_all_pending_entries()
                    
                    for w in workers:
                        # Earned but not settled
                        earned = sum(e.total_amount for e in pending_entries if e.worker_id == w.id and e.status == 'APPROVED' and not getattr(e, 'is_settled', False))
                        
                        # Advances not settled
                        advances = worker_srv.get_worker_ledger(w.id).get('advances', [])
                        advanced = sum(a['amount'] for a in advances if not a.get('is_settled', False))
                        
                        balance = earned - advanced
                        
                        total_earned += earned
                        total_advances += advanced
                        total_dues += balance
                        
                        # Get 5 recent entries and 5 recent advances
                        recent_entries = [e for e in pending_entries if e.worker_id == w.id][:5]
                        recent_advances_data = advances[:5]
                        
                        worker_list.append({
                            "id": w.id,
                            "name": w.name,
                            "role": w.worker_role,
                            "earned": earned,
                            "advanced": advanced,
                            "balance": balance,
                            "recent_entries": [
                                {
                                    "date": e.entry_date.isoformat() if hasattr(e.entry_date, 'isoformat') else e.entry_date,
                                    "task": f"{e.quantity}x {e.order_item.clothing_type if hasattr(e, 'order_item') and e.order_item else 'Item'}",
                                    "amount": e.total_amount
                                } for e in recent_entries
                            ],
                            "recent_advances": [
                                {
                                    "date": a.get('date', ''),
                                    "amount": a.get('amount', 0),
                                    "notes": a.get('notes', '')
                                } for a in recent_advances_data
                            ]
                        })
                        
                    data = {
                        "workers": worker_list,
                        "total_dues": total_dues,
                        "total_advances": total_advances,
                        "total_earned": total_earned
                    }
                    response = {"status": "success", "data": data}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}

            \2''',
    content,
    flags=re.DOTALL
)

# Fix get_stock_payment_summary
content = re.sub(
    r'(elif action == "get_stock_payment_summary":.*?)(elif action == "get_deliveries_dashboard":)',
    r'''elif action == "get_stock_payment_summary":
                try:
                    from app.services.stock_service import stock_service
                    items = stock_service.get_all_stock()
                    
                    total_value = 0.0
                    low_stock_count = 0
                    stock_list = []
                    
                    for item in items:
                        val = item.quantity * item.unit_cost
                        total_value += val
                        if item.quantity <= item.min_quantity:
                            low_stock_count += 1
                            
                        # mock usage
                        recent_usage = []
                            
                        stock_list.append({
                            "id": item.id,
                            "name": item.name,
                            "quantity": item.quantity,
                            "unit": item.unit,
                            "unit_cost": item.unit_cost,
                            "total_value": val,
                            "status": "Low Stock" if item.quantity <= item.min_quantity else "Normal",
                            "recent_usage": recent_usage
                        })
                        
                    data = {
                        "total_value": total_value,
                        "low_stock_count": low_stock_count,
                        "items": stock_list
                    }
                    response = {"status": "success", "data": data}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}

            \2''',
    content,
    flags=re.DOTALL
)

# Fix get_deliveries_dashboard
content = re.sub(
    r'(elif action == "get_deliveries_dashboard":.*?)(elif action == "get_deliveries_calendar":)',
    r'''elif action == "get_deliveries_dashboard":
                try:
                    from app.repositories.firebase.order_repo import OrderRepository
                    from datetime import date
                    or_repo = OrderRepository()
                    
                    orders = or_repo.get_all()
                    
                    today = date.today().isoformat()
                    
                    upcoming_count = sum(1 for o in orders if o.status not in ["DELIVERED", "CANCELLED"] and o.delivery_date and o.delivery_date >= today)
                    overdue_count = sum(1 for o in orders if o.status not in ["DELIVERED", "CANCELLED"] and o.delivery_date and o.delivery_date < today)
                    ready_count = sum(1 for o in orders if o.status == "STITCHING_COMPLETE")
                    in_progress_count = sum(1 for o in orders if o.status in ["NEW", "CUTTING_COMPLETE"])
                    
                    order_list = []
                    for o in orders:
                        if o.status in ["DELIVERED", "CANCELLED"]:
                            continue
                            
                        order_list.append({
                            "id": o.id,
                            "order_number": o.order_number,
                            "customer_name": o.customer.name if getattr(o, "customer", None) else "Unknown",
                            "customer_mobile": o.customer.mobile if getattr(o, "customer", None) else "",
                            "delivery_date": o.delivery_date if o.delivery_date else "",
                            "status": o.status,
                            "remaining_amount": o.remaining_amount,
                            "items": ", ".join([i.clothing_type for i in o.items]) if getattr(o, "items", None) else "Custom",
                            "is_overdue": o.delivery_date < today if o.delivery_date else False
                        })
                        
                    order_list.sort(key=lambda x: x["delivery_date"] or "9999-99-99")
                    
                    data = {
                        "upcoming_count": upcoming_count,
                        "overdue_count": overdue_count,
                        "ready_count": ready_count,
                        "in_progress_count": in_progress_count,
                        "orders": order_list
                    }
                    response = {"status": "success", "data": data}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}

            \2''',
    content,
    flags=re.DOTALL
)

with open("app/ui/web_bridge.py", "w", encoding="utf-8") as f:
    f.write(content)

print("web_bridge.py updated successfully!")
