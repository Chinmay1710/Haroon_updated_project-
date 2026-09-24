import re

with open("app/ui/web_bridge.py", "r", encoding="utf-8") as f:
    content = f.read()

# Fix get_dashboard_stats worker/stock part
content = re.sub(
    r'(try:\s*from app\.models\.worker import Worker.*?finally:\s*w_session\.close\(\))',
    r'''try:
                    worker_srv = self.services["worker"]
                    pending_entries = worker_srv.get_all_pending_entries()
                    total_earned = sum(e.total_amount for e in pending_entries if e.status == "APPROVED" and not getattr(e, 'is_settled', False))
                    
                    all_advances = []
                    for w in worker_srv.get_all_workers():
                        adv = worker_srv.get_worker_ledger(w.id).get('advances', [])
                        all_advances.extend(adv)
                    
                    total_advanced = sum(a['amount'] for a in all_advances if not a.get('is_settled', False))
                    data["worker_total_dues"] = total_earned - total_advanced
                    
                    from app.services.stock_service import stock_service
                    all_stock = stock_service.get_all_stock()
                    low_stock = sum(1 for i in all_stock if i.quantity <= i.min_quantity)
                    data["low_stock_count"] = low_stock
                    
                    total_stock_val = sum(item.quantity * getattr(item, 'unit_cost', 0.0) for item in all_stock)
                    data["total_stock_value"] = total_stock_val''',
    content,
    flags=re.DOTALL
)

# Fix get_customers
content = re.sub(
    r'(elif action == "get_customers":.*?)(elif action == "get_customer_details":)',
    r'''elif action == "get_customers":
                try:
                    cust_srv = self.services["customer"]
                    order_srv = self.services["order"]
                    customers = cust_srv.get_all_customers()
                    
                    data = []
                    for c in customers:
                        orders = order_srv.get_orders_for_customer(c.id)
                        count = len(orders)
                        pending_amount = sum(o.remaining_amount for o in orders)
                        last_order_date = max([o.order_date for o in orders if o.order_date], default=None)
                        data.append({
                            "id": c.id,
                            "name": c.name,
                            "mobile": c.mobile,
                            "address": c.address or "",
                            "notes": c.notes or "",
                            "orders_count": count,
                            "pending_amount": pending_amount,
                            "last_order": last_order_date.isoformat() if last_order_date else "-",
                            "is_active": c.is_active
                        })
                    response = {"status": "success", "data": data}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}
            
            \2''',
    content,
    flags=re.DOTALL
)

# Fix get_customer_details
content = re.sub(
    r'(elif action == "get_customer_details":.*?)(elif action == "create_customer":)',
    r'''elif action == "get_customer_details":
                try:
                    cust_id = payload.get("id")
                    c = self.services["customer"].get_customer(cust_id)
                    if not c:
                        raise Exception("Customer not found")
                        
                    orders = self.services["order"].get_orders_for_customer(c.id)
                    
                    order_data = []
                    for o in orders:
                        order_data.append({
                            "id": o.id,
                            "order_number": o.order_number,
                            "clothing_type": o.items[0].clothing_type if getattr(o, "items", None) else "Custom",
                            "image_path": o.items[0].image_path if getattr(o, "items", None) and o.items[0].image_path else "",
                            "order_date": o.order_date.isoformat() if o.order_date else "",
                            "delivery_date": o.delivery_date.isoformat() if getattr(o, "delivery_date", None) else "",
                            "status": o.status,
                            "total_amount": o.total_amount,
                            "remaining_amount": o.remaining_amount
                        })
                        
                    profiles = self.services["measurement"].get_profiles_for_customer(c.id)
                    profile_data = []
                    for p in profiles:
                        vals = {}
                        for v in p.values:
                            vals[v.field_name] = v.field_value
                        profile_data.append({
                            "id": p.id,
                            "template_type": p.template_type,
                            "updated_at": p.updated_at.isoformat() if hasattr(p, "updated_at") and p.updated_at else "",
                            "values": vals
                        })
                        
                    data = {
                        "customer": {
                            "id": c.id,
                            "name": c.name,
                            "mobile": c.mobile,
                            "address": c.address or "",
                            "notes": c.notes or ""
                        },
                        "orders": order_data,
                        "profiles": profile_data
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

# Fix delete_customer
content = re.sub(
    r'(elif action == "delete_customer":.*?)(elif action == "get_all_measurements":)',
    r'''elif action == "delete_customer":
                try:
                    customer_id = int(payload.get("id"))
                    from app.repositories.firebase.customer_repo import CustomerRepository
                    success = CustomerRepository().soft_delete(customer_id)
                    if success:
                        response = {"status": "success"}
                    else:
                        response = {"status": "error", "message": f"Customer not found (ID: {customer_id})"}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}

            # ────────────────────────────────────────────────────────────
            # MEASUREMENTS
            # ────────────────────────────────────────────────────────────
            \2''',
    content,
    flags=re.DOTALL
)

# Fix get_all_measurements
content = re.sub(
    r'(elif action == "get_all_measurements":.*?)(elif action == "get_measurements_for_customer":)',
    r'''elif action == "get_all_measurements":
                try:
                    meas_srv = self.services["measurement"]
                    measurements = meas_srv.get_all_profiles()
                    
                    data = []
                    for m in measurements:
                        customer = self.services["customer"].get_customer(m.customer_id) if hasattr(m, "customer_id") and m.customer_id else None
                        
                        data.append({
                            "id": m.id,
                            "name": m.name,
                            "customer_name": customer.name if customer else "Unknown",
                            "customer_mobile": customer.mobile if customer else "",
                            "template_type": m.template_type,
                            "values_count": len(m.values) if hasattr(m, "values") else 0,
                            "updated_at": m.updated_at if isinstance(m.updated_at, str) else (m.updated_at.isoformat() if hasattr(m, "updated_at") and m.updated_at else "")
                        })
                    response = {"status": "success", "data": data}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}

            # ────────────────────────────────────────────────────────────
            # ────────────────────────────────────────────────────────────
            # MEASUREMENTS FOR CUSTOMER (WIZARD)
            # ────────────────────────────────────────────────────────────
            \2''',
    content,
    flags=re.DOTALL
)

# Fix get_order_details
content = re.sub(
    r'(elif action == "get_order_details":.*?)(elif action == "update_order_status":)',
    r'''elif action == "get_order_details":
                try:
                    order_id = payload.get("id")
                    o = self.services["order"].get_order(order_id)
                    if not o:
                        raise Exception("Order not found")
                        
                    c = o.customer
                    
                    payments = []
                    for p in o.payments:
                        payments.append({
                            "id": p.id,
                            "amount": p.amount,
                            "payment_date": p.payment_date.isoformat() if hasattr(p, "payment_date") and p.payment_date else "",
                            "payment_method": p.payment_method
                        })
                        
                    tunnel_url = tunnel.GLOBAL_TUNNEL_URL or "http://localhost:8000"
                    scan_url = f"{tunnel_url}/scan?order_id={o.id}"

                    data = {
                        "id": o.id,
                        "order_number": o.order_number,
                        "customer_id": c.id if c else None,
                        "customer_name": c.name if c else "Unknown",
                        "customer_mobile": c.mobile if c else "",
                        "customer_address": c.address if c else "",
                        "order_date": o.order_date.isoformat() if o.order_date else "",
                        "delivery_date": o.delivery_date.isoformat() if getattr(o, "delivery_date", None) else "",
                        "status": o.status,
                        "total_amount": o.total_amount,
                        "advance_amount": o.advance_amount,
                        "remaining_amount": o.remaining_amount,
                        "special_instructions": o.special_instructions or "",
                        "scan_url": scan_url,
                        "payments": payments,
                        "items": []
                    }
                    
                    for item in (o.items or []):
                        image_path_out = ""
                        if item.image_path:
                            paths = item.image_path.split(',')
                            abs_paths = []
                            for p in paths:
                                p = p.strip()
                                if p:
                                    filename = os.path.basename(p)
                                    abs_paths.append(f"file:///{os.path.join(UPLOADS_DIR, 'items', filename).replace(os.sep, '/')}")
                            image_path_out = ",".join(abs_paths)
                            
                        item_data = {
                            "id": item.id,
                            "clothing_type": item.clothing_type,
                            "quantity": item.quantity,
                            "price": item.price,
                            "notes": item.notes or "",
                            "image_path": image_path_out,
                            "is_delivered": getattr(item, "is_delivered", False),
                            "measurements": {}
                        }
                        for m in (item.measurements or []):
                            item_data["measurements"][m.field_name] = m.field_value
                        data["items"].append(item_data)
                        
                    response = {"status": "success", "data": data}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}
                
            \2''',
    content,
    flags=re.DOTALL
)

# Fix update_order_status
content = re.sub(
    r'(elif action == "update_order_status":.*?)(elif action == "add_order_item":)',
    r'''elif action == "update_order_status":
                order_srv = self.services["order"]
                status = payload.get("status")
                order_id = payload.get("order_id") or payload.get("id")
                send_whatsapp = payload.get("send_whatsapp", False)
                delivered_item_ids = payload.get("delivered_item_ids")
                
                try:
                    if delivered_item_ids is not None:
                        # Updating delivered items using firebase repo
                        from app.repositories.firebase.order_repo import OrderRepository
                        from app.utils.cache import invalidate_cache
                        or_repo = OrderRepository()
                        o = or_repo.get_by_id(order_id)
                        if o:
                            for item in o.items:
                                if item.id in delivered_item_ids:
                                    or_repo.items_col.document(str(item.id)).update({"is_delivered": True})
                            
                            # Check if all items delivered
                            updated_items = or_repo.items_col.where("order_id", "==", order_id).get()
                            all_delivered = all(i.to_dict().get("is_delivered", False) for i in updated_items)
                            
                            if all_delivered:
                                or_repo.update_status(order_id, "DELIVERED")
                            invalidate_cache("orders")
                            
                    else:
                        order_srv.update_order_status(order_id, status)
                        
                    if send_whatsapp:
                        o = order_srv.get_order(order_id)
                        if o and o.customer and o.customer.mobile:
                            shop_name = self._get_shop_name()
                            status_msg = ""
                            if status == "CUTTING_COMPLETE":
                                status_msg = "कटिंग पूरी हो गई है और सिलाई के लिए दे दिया गया है।"
                            elif status == "STITCHING_COMPLETE":
                                status_msg = "सिलाई पूरी हो गई है! आपके कपड़े अब डिलीवरी के लिए तैयार हैं।"
                            elif status == "DELIVERED":
                                status_msg = "डिलीवर कर दिया गया है। हमारे साथ जुड़ने के लिए धन्यवाद!"
                            
                            msg = (
                                f"✨ {o.customer.name}! ✨\n\n"
                                f"आपके ऑर्डर #{o.order_number} का स्टेटस अपडेट:\n\n"
                                f"👉 *{status_msg}*\n\n"
                                f"⏳ बकाया राशि: ₹{o.remaining_amount}\n\n"
                                f"नोट: शुक्रवार को दुकान बंद रहती है।\n\n"
                                f"धन्यवाद,\n{shop_name}"
                            )
                            whatsapp_url = self._build_whatsapp_url(o.customer.mobile, msg)
                            response = {"status": "success", "data": {"whatsapp_url": whatsapp_url}}
                        else:
                            response = {"status": "success"}
                    else:
                        response = {"status": "success"}
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = {"status": "error", "message": str(e)}

            \2''',
    content,
    flags=re.DOTALL
)

# Fix get_deliveries_calendar
content = re.sub(
    r'(elif action == "get_deliveries_calendar":.*?)(elif action == "get_today_deliveries":)',
    r'''elif action == "get_deliveries_calendar":
                try:
                    from app.repositories.firebase.order_repo import OrderRepository
                    or_repo = OrderRepository()
                    
                    orders = or_repo.get_all()
                    
                    order_list = []
                    for o in orders:
                        if o.status in ["DELIVERED", "CANCELLED"]:
                            continue
                            
                        order_list.append({
                            "id": o.id,
                            "title": f"#{o.order_number} - {o.customer.name if getattr(o, 'customer', None) else 'Unknown'}",
                            "start": o.delivery_date if getattr(o, "delivery_date", None) else "",
                            "status": o.status,
                            "remaining_amount": o.remaining_amount
                        })
                        
                    response = {"status": "success", "data": order_list}
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

print("web_bridge.py remaining handlers updated successfully!")
