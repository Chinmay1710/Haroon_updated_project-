"""
admin_routes.py - REST API endpoints that mirror web_bridge.py dispatch actions.

This allows the desktop HTML pages to work in a phone browser by replacing
QWebChannel calls with standard HTTP fetch() calls.
"""

import os
import json
import logging
from datetime import date, datetime, timedelta
from typing import Optional, List

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.database.engine import get_session
from app.config import APP_DATA_DIR, UPLOADS_DIR, MEASUREMENT_TEMPLATES

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin-api", tags=["admin"])


# ─── Pydantic Models ─────────────────────────────────────────────────────────

class CustomerCreate(BaseModel):
    name: str
    mobile: str = ""
    address: str = ""
    notes: str = ""

class CustomerUpdate(BaseModel):
    id: int
    name: str
    mobile: str = ""
    address: str = ""
    notes: str = ""

class MeasurementCreate(BaseModel):
    customer_id: int
    template_type: str = "Shirt"
    name: str = ""
    values: dict = {}
    notes: str = ""

class OrderItemCreate(BaseModel):
    clothing_type: str = "Custom"
    quantity: int = 1
    price: float = 0
    measurement_profile_id: Optional[int] = None
    measurements: dict = {}
    save_profile: bool = False
    image_base64: Optional[List[str]] = None
    notes: str = ""

class OrderCreate(BaseModel):
    customerId: int
    items: List[OrderItemCreate] = []
    deliveryDate: Optional[str] = None
    notes: str = ""
    advance: float = 0
    paymentMethod: str = "Cash"
    send_whatsapp: bool = False

class OrderUpdate(BaseModel):
    orderId: int
    items: list = []
    deliveryDate: Optional[str] = None
    notes: str = ""

class OrderStatusUpdate(BaseModel):
    order_id: Optional[int] = None
    id: Optional[int] = None
    status: str
    send_whatsapp: bool = False
    delivered_item_ids: Optional[List[int]] = None

class PaymentCreate(BaseModel):
    order_id: int
    amount: float
    payment_method: str = "Cash"
    send_whatsapp: bool = False

class ExpenseCreate(BaseModel):
    name: str
    category: str
    amount: float
    expense_date: Optional[str] = None
    note: str = ""

class WorkerCreate(BaseModel):
    name: str
    phone: str = ""
    pin: str = ""
    worker_type: str = "PIECE_RATE"
    worker_role: str = "STITCHING"
    daily_rate: float = 0.0

class GarmentRateSet(BaseModel):
    garment_type: str
    rate: float

class EntryApprove(BaseModel):
    entry_id: int
    status: str

class EntryEdit(BaseModel):
    entry_id: int
    quantity: int = 0
    extra_amount: float = 0.0
    total_amount: float = 0.0

class AdvanceRecord(BaseModel):
    worker_id: int
    amount: float
    notes: str = ""

class ManualWorkSubmit(BaseModel):
    worker_id: int
    items: list = []
    extra_desc: str = ""
    extra_amount: float = 0
    is_present: bool = False

class StockItemCreate(BaseModel):
    name: str
    category: str = ""
    quantity: float = 0
    unit: str = ""
    min_quantity: float = 0
    unit_cost: float = 0

class StockItemUpdate(BaseModel):
    id: int
    name: str = ""
    category: str = ""
    unit: str = ""
    min_quantity: float = 0
    unit_cost: float = 0

class StockAdjust(BaseModel):
    id: int
    amount: float
    operation: str

class SettingsUpdate(BaseModel):
    shop_name: Optional[str] = None
    owner_name: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    currency: Optional[str] = None
    measurement_unit: Optional[str] = None
    dictation_language: Optional[str] = None


# ─── Helper ──────────────────────────────────────────────────────────────────

def _get_services():
    """Lazy-import services to avoid circular imports at module load time."""
    from app.services.customer_service import CustomerService
    from app.services.order_service import OrderService
    from app.services.payment_service import PaymentService
    from app.services.measurement_service import MeasurementService
    from app.services.expense_service import ExpenseService
    from app.services.report_service import ReportService
    from app.services.worker_service import worker_service
    from app.services.stock_service import stock_service
    return {
        "customer": CustomerService(),
        "order": OrderService(),
        "payment": PaymentService(),
        "measurement": MeasurementService(),
        "expense": ExpenseService(),
        "report": ReportService(),
        "worker": worker_service,
        "stock": stock_service,
    }

def _get_shop_name() -> str:
    try:
        from app.repositories.settings_repo import SettingsRepository
        session = get_session()
        try:
            settings = SettingsRepository(session).get_settings()
            return settings.shop_name or "Tailor Shop"
        finally:
            session.close()
    except Exception:
        return "Tailor Shop"

def _build_whatsapp_url(phone: str, message: str) -> str:
    import urllib.parse
    clean_phone = phone.strip().replace("+", "").replace(" ", "").replace("-", "")
    if clean_phone.startswith("0"):
        clean_phone = "91" + clean_phone[1:]
    if len(clean_phone) == 10:
        clean_phone = "91" + clean_phone
    encoded_msg = urllib.parse.quote(message)
    return f"https://wa.me/{clean_phone}?text={encoded_msg}"


# ─── Generic dispatch endpoint (catches any action the shim sends) ───────────

@router.post("/dispatch")
async def dispatch_action(request: Request):
    """
    Universal dispatch endpoint that mirrors the QWebChannel bridge.
    The shim JS sends {action, payload} and we route it here.
    """
    body = await request.json()
    action = body.get("action", "")
    payload = body.get("payload", {})
    
    # Ensure fresh session state
    session = get_session()
    try:
        session.commit()
    except Exception:
        pass
    
    try:
        handler = ACTION_HANDLERS.get(action)
        if handler:
            result = handler(payload)
            return result
        else:
            return {"status": "error", "message": f"Unknown action: {action}"}
    except Exception as e:
        logger.error(f"Error in admin dispatch ({action}): {e}", exc_info=True)
        return {"status": "error", "message": str(e)}


# ─── Action Handlers ─────────────────────────────────────────────────────────

def handle_get_settings(payload):
    from app.repositories.settings_repo import SettingsRepository
    session = get_session()
    try:
        repo = SettingsRepository(session)
        s = repo.get_settings()
        data = {
            "shop_name": s.shop_name,
            "owner_name": s.owner_name,
            "phone": s.phone,
            "address": s.address,
            "currency_symbol": s.currency,
            "measurement_unit": s.measurement_unit,
            "twilio_account_sid": s.twilio_account_sid,
            "twilio_auth_token": s.twilio_auth_token,
            "twilio_sender_number": s.twilio_sender_number,
            "dictation_language": s.dictation_language,
        }
        return {"status": "success", "data": data}
    finally:
        session.close()

def handle_update_settings(payload):
    from app.repositories.settings_repo import SettingsRepository
    session = get_session()
    try:
        repo = SettingsRepository(session)
        repo.update_settings(**payload)
        session.commit()
        return {"status": "success"}
    finally:
        session.close()


def handle_get_worker_portal_url(payload):
    from app.web.tunnel import GLOBAL_TUNNEL_URL
    if GLOBAL_TUNNEL_URL:
        return {"status": "success", "data": {"url": GLOBAL_TUNNEL_URL}}
    return {"status": "error", "message": "Portal is not running"}


# ─── DASHBOARD ───────────────────────────────────────────────────────────────

def handle_get_dashboard_stats(payload):
    services = _get_services()
    order_srv = services["order"]
    
    target_date = None
    date_str = payload.get("date")
    if date_str:
        try:
            target_date = datetime.strptime(date_str, "%Y-%m-%d").date()
        except ValueError:
            pass
    
    dash_data = order_srv.get_dashboard_data(target_date)
    
    recent_orders = []
    for o in dash_data["recent_orders"]:
        recent_orders.append({
            "id": o.id,
            "order_number": o.order_number,
            "customer_name": o.customer.name if o.customer else "Unknown",
            "status": o.status
        })
    
    deliveries = []
    for o in dash_data["today_deliveries_list"]:
        deliveries.append({
            "id": o.id,
            "order_number": o.order_number,
            "customer_name": o.customer.name if o.customer else "Unknown",
            "status": o.status,
            "remaining": o.remaining_amount,
            "items": "Various"
        })
    
    data = {
        "orders_today": dash_data["orders_today"],
        "sales_today": dash_data["today_sales"],
        "pending_payments": dash_data["pending_payments"],
        "deliveries_today": dash_data["deliveries_today"],
        "status_counts": dash_data["status_counts"],
        "recent_orders": recent_orders,
        "deliveries": deliveries
    }
    
    # Add worker dues and stock info
    try:
        from app.models.worker import Worker, WorkEntry, WorkerAdvance
        from app.models.stock import StockItem
        from sqlalchemy import func
        w_session = get_session()
        try:
            total_earned = w_session.query(func.sum(WorkEntry.total_amount)).filter(
                WorkEntry.status == "APPROVED",
                WorkEntry.is_settled == False  # noqa: E712
            ).scalar() or 0.0
            total_advanced = w_session.query(func.sum(WorkerAdvance.amount)).filter(
                WorkerAdvance.is_settled == False  # noqa: E712
            ).scalar() or 0.0
            data["worker_total_dues"] = total_earned - total_advanced
            
            low_stock = w_session.query(func.count(StockItem.id)).filter(
                StockItem.quantity <= StockItem.min_quantity
            ).scalar() or 0
            data["low_stock_count"] = low_stock
            
            all_stock = w_session.query(StockItem).all()
            total_stock_val = sum(item.quantity * getattr(item, 'unit_cost', 0.0) for item in all_stock)
            data["total_stock_value"] = total_stock_val
        finally:
            w_session.close()
    except Exception as e:
        logger.error(f"Failed to get worker/stock dashboard data: {e}")
        data["worker_total_dues"] = 0
        data["low_stock_count"] = 0
        data["total_stock_value"] = 0
    
    return {"status": "success", "data": data}


# ─── CUSTOMERS ───────────────────────────────────────────────────────────────

def handle_get_customers(payload):
    from app.models.customer import Customer
    from app.models.order import Order
    from sqlalchemy.orm import joinedload
    
    session = get_session()
    try:
        session.expunge_all()
        customers = session.query(Customer).options(
            joinedload(Customer.orders)
        ).filter(Customer.is_active == True).order_by(Customer.id.desc()).all()  # noqa: E712
        
        if isinstance(customers, tuple):
            customers = customers[0]
        
        data = []
        for c in customers:
            orders = c.orders
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
        return {"status": "success", "data": data}
    finally:
        session.close()


def handle_get_customer_details(payload):
    from app.models.customer import Customer
    from app.models.order import Order
    from app.models.measurement import MeasurementProfile
    
    session = get_session()
    try:
        cust_id = payload.get("id")
        c = session.query(Customer).filter(Customer.id == cust_id).first()
        if not c:
            raise Exception("Customer not found")
        
        orders = session.query(Order).filter(Order.customer_id == c.id).all()
        
        order_data = []
        for o in orders:
            order_data.append({
                "id": o.id,
                "order_number": o.order_number,
                "clothing_type": o.items[0].clothing_type if o.items else "Custom",
                "image_path": o.items[0].image_path if o.items and o.items[0].image_path else "",
                "order_date": o.order_date.isoformat() if o.order_date else "",
                "delivery_date": o.delivery_date.isoformat() if o.delivery_date else "",
                "status": o.status,
                "total_amount": o.total_amount,
                "remaining_amount": o.remaining_amount
            })
        
        profiles = session.query(MeasurementProfile).filter(MeasurementProfile.customer_id == c.id).all()
        profile_data = []
        for p in profiles:
            vals = {}
            for v in p.values:
                vals[v.field_name] = v.field_value
            profile_data.append({
                "id": p.id,
                "template_type": p.template_type,
                "updated_at": p.updated_at.isoformat() if p.updated_at else "",
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
        return {"status": "success", "data": data}
    finally:
        session.close()


def handle_create_customer(payload):
    services = _get_services()
    cust_srv = services["customer"]
    customer = cust_srv.create_customer(
        name=payload.get('name'),
        mobile=payload.get('mobile'),
        address=payload.get('address'),
        notes=payload.get('notes')
    )
    return {"status": "success", "data": {"id": customer.id}}


def handle_update_customer(payload):
    services = _get_services()
    cust_srv = services["customer"]
    cust_id = payload.get("id")
    cust_srv.update_customer(
        cust_id,
        name=payload.get('name'),
        mobile=payload.get('mobile'),
        address=payload.get('address'),
        notes=payload.get('notes')
    )
    return {"status": "success"}


def handle_delete_customer(payload):
    from app.models.customer import Customer
    customer_id = int(payload.get("id"))
    del_session = get_session()
    try:
        c = del_session.query(Customer).filter(Customer.id == customer_id).first()
        if c:
            del_session.delete(c)
            del_session.commit()
            return {"status": "success"}
        else:
            return {"status": "error", "message": f"Customer not found (ID: {customer_id})"}
    except Exception as e:
        del_session.rollback()
        return {"status": "error", "message": str(e)}
    finally:
        del_session.close()


def handle_get_customer_qr_url(payload):
    base_url = payload.get("origin")
    
    if not base_url:
        from app.web.tunnel import GLOBAL_TUNNEL_URL
        base_url = GLOBAL_TUNNEL_URL

    if base_url:
        # Strip trailing slash if present
        base_url = base_url.rstrip("/")
        # We assume the mobile customer form is served at /static/customer_form.html
        qr_url = f"{base_url}/static/customer_form.html"
        
        # Generate QR base64
        try:
            import qrcode
            import io
            import base64
            qr = qrcode.QRCode(version=1, box_size=10, border=4)
            qr.add_data(qr_url)
            qr.make(fit=True)
            img = qr.make_image(fill_color="black", back_color="white")
            buffered = io.BytesIO()
            img.save(buffered, format="PNG")
            img_str = base64.b64encode(buffered.getvalue()).decode()
            base64_url = f"data:image/png;base64,{img_str}"
        except Exception as e:
            logger.error(f"Error generating QR: {e}")
            base64_url = ""
        return {"status": "success", "data": {"url": qr_url, "base64": base64_url}}
    
    return {"status": "error", "message": "Server URL could not be determined"}


# ─── MEASUREMENTS ────────────────────────────────────────────────────────────

def handle_get_all_measurements(payload):
    from app.models.measurement import MeasurementProfile
    from sqlalchemy.orm import joinedload
    
    session = get_session()
    try:
        session.expunge_all()
        measurements = session.query(MeasurementProfile).options(
            joinedload(MeasurementProfile.customer),
            joinedload(MeasurementProfile.values)
        ).all()
        
        data = []
        for m in measurements:
            customer = m.customer
            data.append({
                "id": m.id,
                "name": m.name,
                "customer_name": customer.name if customer else "Unknown",
                "customer_mobile": customer.mobile if customer else "",
                "template_type": m.template_type,
                "values_count": len(m.values),
                "updated_at": m.updated_at.isoformat()
            })
        return {"status": "success", "data": data}
    finally:
        session.close()


def handle_get_measurements_for_customer(payload):
    services = _get_services()
    cust_id = payload.get("customer_id")
    meas_srv = services["measurement"]
    measurements = meas_srv.get_profiles_for_customer(cust_id)
    data = []
    for m in measurements:
        vals = {}
        for v in m.values:
            vals[v.field_name] = v.field_value
        data.append({
            "id": m.id,
            "template_type": m.template_type,
            "values": vals,
            "updated_at": m.updated_at.isoformat()
        })
    return {"status": "success", "data": data}


def handle_create_measurement(payload):
    services = _get_services()
    cust_id = payload.get("customer_id")
    template = payload.get("template_type", "Shirt")
    name = payload.get("name", f"{template} Profile")
    values = payload.get("values", {})
    notes = payload.get("notes", "")
    
    if not cust_id:
        raise ValueError("customer_id is required")
    
    meas_srv = services["measurement"]
    m = meas_srv.create_profile(
        customer_id=cust_id,
        template_type=template,
        name=name,
        values=values,
        notes=notes
    )
    return {"status": "success", "data": {"id": m.id}}


# ─── ORDERS ──────────────────────────────────────────────────────────────────

def handle_create_order(payload):
    services = _get_services()
    order_srv = services["order"]
    
    deliv_str = payload.get("deliveryDate")
    deliv_date = None
    if deliv_str:
        deliv_date = datetime.strptime(deliv_str, "%Y-%m-%d").date()
    
    items = payload.get("items", [])
    if not items:
        items = [{
            "clothing_type": payload.get("clothingType", "Custom"),
            "quantity": payload.get("quantity", 1),
            "price": float(payload.get("price", 0)),
            "measurement_profile_id": payload.get("measurementId")
        }]
    
    order = order_srv.create_order(
        customer_id=payload.get("customerId"),
        items=items,
        order_date=datetime.now().date(),
        delivery_date=deliv_date,
        special_instructions=payload.get("notes", ""),
        advance_amount=float(payload.get("advance", 0)),
        payment_method=payload.get("paymentMethod", "Cash")
    )
    
    # Build WhatsApp URL if requested
    whatsapp_url = None
    send_whatsapp = payload.get("send_whatsapp", True)
    if send_whatsapp:
        customer_srv = services["customer"]
        customer = customer_srv.get_customer(payload.get("customerId")) if payload.get("customerId") else None
        if customer and customer.mobile:
            shop_name = _get_shop_name()
            paid_amt = order.total_amount - order.remaining_amount
            msg = (
                f"✨ {customer.name}! ✨\n\n"
                f"{shop_name} को चुनने के लिए धन्यवाद! आपका ऑर्डर #{order.order_number} सफलतापूर्वक दर्ज कर लिया गया है।\n\n"
                f"👔 कुल बिल: ₹{order.total_amount}\n"
                f"✅ जमा किए: ₹{paid_amt}\n"
                f"⏳ बकाया राशि: ₹{order.remaining_amount}\n\n"
                f"जैसे ही आपके कपड़े तैयार हो जाएंगे, हम आपको सूचित कर देंगे!\n\n"
                f"नोट: शुक्रवार को दुकान बंद रहती है।\n\n"
                f"धन्यवाद,\n{shop_name}"
            )
            whatsapp_url = _build_whatsapp_url(customer.mobile, msg)
    
    return {
        "status": "success",
        "data": {"id": order.id, "order_number": order.order_number, "whatsapp_url": whatsapp_url}
    }


def handle_update_order(payload):
    services = _get_services()
    order_srv = services["order"]
    order_id = payload.get("orderId")
    
    deliv_str = payload.get("deliveryDate")
    deliv_date = None
    if deliv_str:
        deliv_date = datetime.strptime(deliv_str, "%Y-%m-%d").date()
    
    items = payload.get("items", [])
    order = order_srv.update_order(
        order_id=order_id,
        items=items,
        delivery_date=deliv_date,
        special_instructions=payload.get("notes", "")
    )
    
    return {
        "status": "success",
        "data": {"id": order.id, "order_number": order.order_number}
    }


def handle_get_all_orders(payload):
    services = _get_services()
    order_srv = services["order"]
    orders = order_srv.get_all_orders()
    if isinstance(orders, tuple):
        orders = orders[0]
    
    data = []
    for o in orders:
        data.append({
            "id": o.id,
            "order_number": o.order_number,
            "customer_name": o.customer.name if o.customer else "Unknown",
            "customer_id": o.customer.id if o.customer else None,
            "customer_mobile": o.customer.mobile if o.customer else "",
            "items": ", ".join([f"{i.quantity}x {i.clothing_type}" for i in o.items]) if o.items else "Custom",
            "image_path": o.items[0].image_path if o.items and o.items[0].image_path else "",
            "order_date": o.order_date.isoformat() if o.order_date else "",
            "delivery_date": o.delivery_date.isoformat() if o.delivery_date else "",
            "status": o.status,
            "total_amount": o.total_amount,
            "remaining_amount": o.remaining_amount,
            "updated_at": o.updated_at.isoformat() if hasattr(o, "updated_at") and o.updated_at else ""
        })
    data.sort(key=lambda x: x["updated_at"] if x.get("updated_at") else str(x["id"]), reverse=True)
    return {"status": "success", "data": data}


def handle_get_order_details(payload):
    from app.models.order import Order
    from app.web.tunnel import GLOBAL_TUNNEL_URL
    
    session = get_session()
    try:
        order_id = payload.get("id")
        o = session.query(Order).filter(Order.id == order_id).first()
        if not o:
            raise Exception("Order not found")
        
        c = o.customer
        
        payments = []
        for p in o.payments:
            payments.append({
                "id": p.id,
                "amount": p.amount,
                "payment_date": p.payment_date.isoformat() if p.payment_date else "",
                "payment_method": p.payment_method
            })
        
        tunnel_url = GLOBAL_TUNNEL_URL or "http://localhost:8000"
        scan_url = f"{tunnel_url}/scan?order_id={o.id}"
        
        data = {
            "id": o.id,
            "order_number": o.order_number,
            "customer_id": c.id if c else None,
            "customer_name": c.name if c else "Unknown",
            "customer_mobile": c.mobile if c else "",
            "customer_address": c.address if c else "",
            "order_date": o.order_date.isoformat() if o.order_date else "",
            "delivery_date": o.delivery_date.isoformat() if o.delivery_date else "",
            "status": o.status,
            "total_amount": o.total_amount,
            "advance_amount": o.advance_amount,
            "remaining_amount": o.remaining_amount,
            "special_instructions": o.special_instructions or "",
            "scan_url": scan_url,
            "payments": payments,
            "items": []
        }
        
        for item in o.items:
            image_path_out = ""
            if item.image_path:
                # For web, serve images via /uploads/ route
                paths = item.image_path.split(',')
                abs_paths = []
                for p in paths:
                    p = p.strip()
                    if p:
                        filename = os.path.basename(p)
                        abs_paths.append(f"/uploads/items/{filename}")
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
            for m in item.measurements:
                item_data["measurements"][m.field_name] = m.field_value
            data["items"].append(item_data)
        
        return {"status": "success", "data": data}
    finally:
        session.close()


def handle_update_order_status(payload):
    services = _get_services()
    order_srv = services["order"]
    status = payload.get("status")
    order_id = payload.get("order_id") or payload.get("id")
    send_whatsapp = payload.get("send_whatsapp", False)
    delivered_item_ids = payload.get("delivered_item_ids")
    
    from app.models.order import Order, OrderItem
    session = get_session()
    try:
        order = session.query(Order).filter(Order.id == order_id).first()
        if order and delivered_item_ids is not None:
            for item in order.items:
                if item.id in delivered_item_ids:
                    item.is_delivered = True
            all_delivered = all(item.is_delivered for item in order.items) if order.items else True
            if all_delivered:
                status = "DELIVERED"
            else:
                status = "PARTIALLY_DELIVERED"
        
        if order:
            order.status = status
        session.commit()
    except Exception as e:
        session.rollback()
        raise e
    finally:
        session.close()
    
    # Build WhatsApp URL if requested
    whatsapp_url = None
    if send_whatsapp and (status == "STITCHING_COMPLETE" or status == "DELIVERED"):
        order = order_srv.get_order(order_id)
        shop_name = _get_shop_name()
        if order and order.customer and order.customer.mobile:
            items_str = ", ".join(f"{item.quantity} {item.clothing_type}" for item in order.items) if order.items else "कपड़े"
            msg = (
                f"🎉 {order.customer.name}! 🎉\n\n"
                f"आपका ऑर्डर #{order.order_number} ({items_str}) अब बिल्कुल तैयार है! आप इसे {shop_name} से ले जा सकते हैं।\n\n"
                f"कृपया अपनी सुविधा अनुसार दुकान पर आएं और अपने सिले हुए कपड़े प्राप्त करें।\n\n"
                f"नोट: शुक्रवार को दुकान बंद रहती है।\n\n"
                f"जल्द मिलेंगे!\n{shop_name}"
            )
            whatsapp_url = _build_whatsapp_url(order.customer.mobile, msg)
    
    return {"status": "success", "data": {"whatsapp_url": whatsapp_url}}


def handle_generate_payment_reminder_whatsapp(payload):
    from app.repositories.settings_repo import SettingsRepository
    session = get_session()
    try:
        settings = SettingsRepository(session).get_settings()
        shop_name = settings.shop_name if settings else "Haroon Tailor"
    finally:
        session.close()
    
    services = _get_services()
    order_id = payload.get("order_id")
    order_srv = services.get("order")
    order = order_srv.get_order(order_id) if order_srv else None
    
    if order and order.customer and order.customer.mobile:
        msg = (
            f"{order.customer.name},\n\n"
            f"यह एक रिमाइंडर है कि आपके ऑर्डर {order.order_number} का ₹{order.remaining_amount} बकाया है। "
            f"कृपया अपनी सुविधा अनुसार इसे जल्द से जल्द चुका दें।\n\n"
            f"नोट: शुक्रवार को दुकान बंद रहती है।\n\n"
            f"धन्यवाद!\n{shop_name}"
        )
        whatsapp_url = _build_whatsapp_url(order.customer.mobile, msg)
        return {"status": "success", "data": {"whatsapp_url": whatsapp_url}}
    return {"status": "error", "message": "Customer mobile not found or order not found"}


# ─── PAYMENTS ────────────────────────────────────────────────────────────────

def handle_get_all_payments(payload):
    from app.repositories.payment_repo import PaymentRepository
    session = get_session()
    try:
        repo = PaymentRepository(session)
        payments = repo.get_all()
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
                "updated_at": p.updated_at.isoformat() if hasattr(p, "updated_at") and p.updated_at else ""
            })
        data.sort(key=lambda x: x["updated_at"] if x.get("updated_at") else str(x["id"]), reverse=True)
        return {"status": "success", "data": data}
    finally:
        session.close()


def handle_get_payments_dashboard(payload):
    from app.models.payment import Payment
    from app.models.order import Order
    from sqlalchemy import func
    
    session = get_session()
    try:
        today = date.today()
        total_collected = session.query(func.sum(Payment.amount)).scalar() or 0.0
        today_payments = session.query(func.sum(Payment.amount)).filter(
            Payment.payment_date == today
        ).scalar() or 0.0
        pending_payments = session.query(
            func.sum(Order.total_amount - Order.paid_amount)
        ).filter(
            Order.status != 'CANCELLED',
            Order.total_amount > Order.paid_amount
        ).scalar() or 0.0
        
        data = {
            "total_collected": total_collected,
            "pending_payments": pending_payments,
            "today_payments": today_payments
        }
        return {"status": "success", "data": data}
    finally:
        session.close()


def handle_create_payment(payload):
    services = _get_services()
    pay_srv = services["payment"]
    order_id = payload.get("order_id")
    send_whatsapp = payload.get("send_whatsapp", True)
    
    payment = pay_srv.add_payment(
        order_id=order_id,
        amount=float(payload.get("amount")),
        payment_method=payload.get("payment_method", "Cash"),
        payment_date=date.today()
    )
    
    if send_whatsapp:
        order_srv = services["order"]
        order = order_srv.get_order(order_id)
        if order and order.customer and order.customer.mobile:
            shop_name = _get_shop_name()
            paid_amt = order.total_amount - order.remaining_amount
            msg = (
                f"✨ {order.customer.name}! ✨\n\n"
                f"हमने आपके ऑर्डर #{order.order_number} के लिए ₹{payment.amount} का भुगतान प्राप्त कर लिया है।\n\n"
                f"✅ कुल जमा: ₹{paid_amt}\n"
                f"⏳ बकाया राशि: ₹{order.remaining_amount}\n\n"
                f"नोट: शुक्रवार को दुकान बंद रहती है।\n\n"
                f"धन्यवाद,\n{shop_name}"
            )
            whatsapp_url = _build_whatsapp_url(order.customer.mobile, msg)
            return {"status": "success", "data": {"whatsapp_url": whatsapp_url}}
    
    return {"status": "success"}


def handle_get_worker_payment_summary(payload):
    from app.models.worker import Worker, WorkEntry, WorkerAdvance
    from sqlalchemy import func
    
    session = get_session()
    try:
        workers = session.query(Worker).filter(Worker.is_active == True).all()  # noqa: E712
        worker_list = []
        total_dues = 0.0
        total_advances = 0.0
        total_earned = 0.0
        
        for w in workers:
            earned = session.query(func.sum(WorkEntry.total_amount)).filter(
                WorkEntry.worker_id == w.id,
                WorkEntry.status == "APPROVED",
                WorkEntry.is_settled == False  # noqa: E712
            ).scalar() or 0.0
            
            advanced = session.query(func.sum(WorkerAdvance.amount)).filter(
                WorkerAdvance.worker_id == w.id,
                WorkerAdvance.is_settled == False  # noqa: E712
            ).scalar() or 0.0
            
            remaining = earned - advanced
            total_earned += earned
            total_advances += advanced
            total_dues += remaining
            
            recent_advances = session.query(WorkerAdvance).filter(
                WorkerAdvance.worker_id == w.id,
                WorkerAdvance.is_settled == False  # noqa: E712
            ).order_by(WorkerAdvance.date.desc()).limit(5).all()
            
            advances_list = [{
                "id": a.id,
                "amount": a.amount,
                "date": a.date.isoformat() if a.date else "",
                "notes": a.notes or ""
            } for a in recent_advances]
            
            worker_list.append({
                "id": w.id,
                "name": w.name,
                "phone": w.phone or "",
                "worker_type": w.worker_type,
                "total_earned": earned,
                "total_advance": advanced,
                "remaining_due": remaining,
                "recent_advances": advances_list
            })
        
        return {"status": "success", "data": {
            "workers": worker_list,
            "summary": {
                "total_earned": total_earned,
                "total_advances": total_advances,
                "total_dues": total_dues,
                "worker_count": len(worker_list)
            }
        }}
    finally:
        session.close()


def handle_get_stock_payment_summary(payload):
    from app.models.stock import StockItem, StockUsage
    from app.models.worker import Worker
    from sqlalchemy import func
    
    session = get_session()
    try:
        items = session.query(StockItem).order_by(StockItem.name).all()
        stock_list = []
        total_stock_value = 0.0
        low_stock_count = 0
        
        for item in items:
            stock_value = item.quantity * (item.unit_cost if hasattr(item, 'unit_cost') else 0.0)
            total_stock_value += stock_value
            
            if item.quantity <= item.min_quantity:
                low_stock_count += 1
            
            recent_usage = session.query(
                StockUsage, Worker.name
            ).join(
                Worker, StockUsage.worker_id == Worker.id
            ).filter(
                StockUsage.stock_item_id == item.id
            ).order_by(StockUsage.date.desc()).limit(3).all()
            
            usage_list = [{
                "worker_name": u[1],
                "quantity": u[0].quantity,
                "date": u[0].date.isoformat() if u[0].date else ""
            } for u in recent_usage]
            
            stock_list.append({
                "id": item.id,
                "name": item.name,
                "category": item.category,
                "quantity": item.quantity,
                "unit": item.unit,
                "unit_cost": item.unit_cost if hasattr(item, 'unit_cost') else 0.0,
                "total_value": stock_value,
                "min_quantity": item.min_quantity,
                "is_low": item.quantity <= item.min_quantity,
                "recent_usage": usage_list
            })
        
        return {"status": "success", "data": {
            "items": stock_list,
            "summary": {
                "total_value": total_stock_value,
                "total_items": len(stock_list),
                "low_stock_count": low_stock_count
            }
        }}
    finally:
        session.close()


# ─── DELIVERIES ──────────────────────────────────────────────────────────────

def handle_get_deliveries_dashboard(payload):
    from app.models.order import Order
    from sqlalchemy.orm import joinedload
    
    today = date.today()
    tomorrow = today + timedelta(days=1)
    
    session = get_session()
    try:
        orders = session.query(Order).options(
            joinedload(Order.customer),
        ).filter(
            Order.status.in_(["STITCHING_COMPLETE", "DELIVERED"])
        ).order_by(Order.updated_at.desc()).all()
        
        deliveries_list = []
        counts = {"due_today": 0, "due_tomorrow": 0, "upcoming": 0, "overdue": 0}
        
        for o in orders:
            if o.delivery_date:
                if o.delivery_date < today:
                    counts["overdue"] += 1
                elif o.delivery_date == today:
                    counts["due_today"] += 1
                elif o.delivery_date == tomorrow:
                    counts["due_tomorrow"] += 1
                else:
                    counts["upcoming"] += 1
            
            deliveries_list.append({
                "id": o.id,
                "order_number": o.order_number,
                "customer_name": o.customer.name if o.customer else "",
                "mobile": o.customer.mobile if o.customer else "",
                "items": "Various",
                "delivery_date": o.delivery_date.isoformat() if o.delivery_date else "",
                "status": o.status,
                "total_amount": o.total_amount,
                "advance_paid": getattr(o, "advance_amount", getattr(o, "paid_amount", 0)),
                "remaining_amount": o.remaining_amount,
                "updated_at": o.updated_at.isoformat() if hasattr(o, "updated_at") and o.updated_at else ""
            })
    finally:
        session.close()
    
    deliveries_list.sort(key=lambda x: x["updated_at"] if x.get("updated_at") else str(x["id"]), reverse=True)
    return {"status": "success", "data": {"counts": counts, "deliveries": deliveries_list}}


# ─── EXPENSES ────────────────────────────────────────────────────────────────

def handle_get_expenses_dashboard(payload):
    services = _get_services()
    exp_srv = services["expense"]
    expenses = exp_srv.get_all_expenses()
    data = []
    for e in expenses:
        data.append({
            "id": e.id,
            "date": e.expense_date.isoformat() if e.expense_date else "",
            "category": e.category,
            "amount": e.amount,
            "name": e.name,
            "note": e.note or ""
        })
    
    today = date.today()
    week_start = today - timedelta(days=today.weekday())
    month_start = today.replace(day=1)
    
    stats = {"today": 0, "week": 0, "month": 0}
    for e in expenses:
        if e.expense_date:
            if e.expense_date == today:
                stats["today"] += e.amount
            if e.expense_date >= week_start:
                stats["week"] += e.amount
            if e.expense_date >= month_start:
                stats["month"] += e.amount
    
    return {"status": "success", "data": {"expenses": data, "stats": stats}}


def handle_create_expense(payload):
    services = _get_services()
    exp_srv = services["expense"]
    
    exp_date_str = payload.get("expense_date")
    exp_date = date.fromisoformat(exp_date_str) if exp_date_str else date.today()
    
    exp_srv.create_expense(
        name=payload.get("name"),
        category=payload.get("category"),
        amount=payload.get("amount"),
        expense_date=exp_date,
        note=payload.get("note")
    )
    return {"status": "success"}


def handle_delete_expense(payload):
    services = _get_services()
    exp_srv = services["expense"]
    exp_id = payload.get("id")
    if exp_id:
        exp_srv.delete_expense(int(exp_id))
        return {"status": "success"}
    return {"status": "error", "message": "Expense ID is required"}


# ─── REPORTS ─────────────────────────────────────────────────────────────────

def handle_get_report_data(payload):
    services = _get_services()
    rep_srv = services["report"]
    data = rep_srv.get_this_month_report()
    return {"status": "success", "data": {
        "total_sales": data.get("total_sales", 0),
        "total_orders": data.get("total_orders", 0),
        "total_expenses": data.get("total_expenses", 0),
        "net_profit": data.get("estimated_profit", 0)
    }}


# ─── WORKERS ─────────────────────────────────────────────────────────────────

def handle_get_all_workers(payload):
    services = _get_services()
    worker_srv = services["worker"]
    workers = worker_srv.get_all_workers()
    return {"status": "success", "data": {"workers": workers}}


def handle_add_worker(payload):
    services = _get_services()
    worker_srv = services["worker"]
    w = worker_srv.add_worker(
        name=payload.get("name"),
        phone=payload.get("phone"),
        pin=payload.get("pin"),
        worker_type=payload.get("worker_type", "PIECE_RATE"),
        worker_role=payload.get("worker_role", "STITCHING"),
        daily_rate=float(payload.get("daily_rate", 0.0))
    )
    return {"status": "success", "data": {"worker": w}}


def handle_assign_task(payload):
    services = _get_services()
    worker_srv = services["worker"]
    t = worker_srv.assign_task(payload.get("worker_id"), payload.get("order_item_id"), payload.get("payout_amount"))
    return {"status": "success", "data": {"task": t}}


def handle_get_worker_tasks(payload):
    services = _get_services()
    worker_srv = services["worker"]
    t = worker_srv.get_worker_tasks(payload.get("worker_id"))
    return {"status": "success", "data": {"tasks": t}}


def handle_get_garment_rates(payload):
    services = _get_services()
    worker_srv = services["worker"]
    rates = worker_srv.get_garment_rates()
    return {"status": "success", "data": {"rates": rates}}


def handle_set_garment_rate(payload):
    services = _get_services()
    worker_srv = services["worker"]
    rate = worker_srv.set_garment_rate(payload.get("garment_type"), float(payload.get("rate", 0)))
    return {"status": "success", "data": {"rate": rate}}


def handle_delete_garment_rate(payload):
    services = _get_services()
    worker_srv = services["worker"]
    success = worker_srv.delete_garment_rate(payload.get("garment_type"))
    return {"status": "success" if success else "error"}


def handle_get_all_pending_entries(payload):
    services = _get_services()
    worker_srv = services["worker"]
    entries = worker_srv.get_all_pending_entries()
    return {"status": "success", "data": {"entries": entries}}


def handle_approve_entry(payload):
    services = _get_services()
    worker_srv = services["worker"]
    success = worker_srv.approve_entry(payload.get("entry_id"), payload.get("status"))
    return {"status": "success" if success else "error"}


def handle_edit_pending_entry(payload):
    services = _get_services()
    worker_srv = services["worker"]
    result = worker_srv.edit_pending_entry(
        entry_id=payload.get("entry_id"),
        new_quantity=int(payload.get("quantity", 0)),
        new_extra_amount=float(payload.get("extra_amount", 0.0)),
        new_total_amount=float(payload.get("total_amount", 0.0))
    )
    if "error" in result:
        return {"status": "error", "message": result["error"]}
    return {"status": "success"}


def handle_record_advance(payload):
    services = _get_services()
    worker_srv = services["worker"]
    advance = worker_srv.record_advance(
        payload.get("worker_id"), float(payload.get("amount", 0)), payload.get("notes", "")
    )
    return {"status": "success", "data": {"advance": advance}}


def handle_get_worker_ledger(payload):
    services = _get_services()
    worker_srv = services["worker"]
    ledger = worker_srv.get_worker_ledger(payload.get("worker_id"))
    return {"status": "success", "data": {"ledger": ledger}}


def handle_delete_worker(payload):
    services = _get_services()
    worker_srv = services["worker"]
    worker_id = payload.get("worker_id") or payload.get("id")
    success = worker_srv.delete_worker(int(worker_id))
    if success:
        return {"status": "success"}
    return {"status": "error", "message": "Worker not found"}


def handle_get_worker_history(payload):
    services = _get_services()
    worker_srv = services["worker"]
    worker_id = payload.get("worker_id")
    history_data = worker_srv.get_worker_history(int(worker_id))
    return {"status": "success", "data": history_data}


def handle_settle_worker_account(payload):
    services = _get_services()
    worker_srv = services["worker"]
    worker_id = payload.get("worker_id")
    success = worker_srv.settle_worker_account(int(worker_id))
    if success:
        return {"status": "success"}
    return {"status": "error", "message": "Worker not found"}


def handle_submit_manual_work(payload):
    services = _get_services()
    worker_srv = services["worker"]
    worker_id = payload.get("worker_id")
    items = payload.get("items", [])
    extra_desc = payload.get("extra_desc", "")
    extra_amount = float(payload.get("extra_amount", 0))
    is_present = bool(payload.get("is_present", False))
    
    if items:
        for i, item in enumerate(items):
            ext_amt = extra_amount if i == 0 else 0
            ext_desc = extra_desc if i == 0 else ""
            worker_srv.submit_work_entry(
                worker_id=worker_id,
                garment_type=item.get("garment_type"),
                quantity=int(item.get("quantity", 1)),
                bill_number="Manual Log",
                extra_work_description=ext_desc,
                extra_amount=ext_amt,
                auto_approve=True,
                is_present=is_present if i == 0 else False
            )
    else:
        worker_srv.submit_work_entry(
            worker_id=worker_id,
            garment_type=None,
            quantity=0,
            bill_number="Manual Log",
            extra_work_description=extra_desc,
            extra_amount=extra_amount,
            auto_approve=True,
            is_present=is_present
        )
    return {"status": "success"}


# ─── STOCK ───────────────────────────────────────────────────────────────────

def handle_get_all_stock(payload):
    from app.services.stock_service import stock_service
    items = stock_service.get_all_stock()
    data = [{
        "id": i.id, "name": i.name, "category": i.category,
        "quantity": i.quantity, "unit": i.unit,
        "min_quantity": i.min_quantity,
        "unit_cost": getattr(i, 'unit_cost', 0.0)
    } for i in items]
    return {"status": "success", "data": data}


def handle_get_low_stock(payload):
    from app.services.stock_service import stock_service
    items = stock_service.get_low_stock_items()
    data = [{
        "id": i.id, "name": i.name, "category": i.category,
        "quantity": i.quantity, "unit": i.unit,
        "min_quantity": i.min_quantity,
        "unit_cost": getattr(i, 'unit_cost', 0.0)
    } for i in items]
    return {"status": "success", "data": data}


def handle_add_stock_item(payload):
    from app.services.stock_service import stock_service
    item = stock_service.add_stock_item(
        name=payload.get("name"),
        category=payload.get("category"),
        quantity=float(payload.get("quantity", 0)),
        unit=payload.get("unit"),
        min_quantity=float(payload.get("min_quantity", 0)),
        unit_cost=float(payload.get("unit_cost", 0))
    )
    return {"status": "success", "data": item}


def handle_update_stock_item(payload):
    from app.services.stock_service import stock_service
    item = stock_service.update_stock_item(
        item_id=payload.get("id"),
        name=payload.get("name"),
        category=payload.get("category"),
        unit=payload.get("unit"),
        min_quantity=float(payload.get("min_quantity", 0)),
        unit_cost=float(payload.get("unit_cost", 0))
    )
    return {"status": "success", "data": item}


def handle_adjust_stock(payload):
    from app.services.stock_service import stock_service
    item = stock_service.adjust_stock(
        item_id=payload.get("id"),
        amount=float(payload.get("amount", 0)),
        operation=payload.get("operation")
    )
    return {"status": "success", "data": item}


def handle_delete_stock_item(payload):
    from app.services.stock_service import stock_service
    success = stock_service.delete_stock_item(payload.get("id"))
    return {"status": "success" if success else "error"}


def handle_get_stock_usage_history(payload):
    services = _get_services()
    worker_srv = services["worker"]
    history = worker_srv.get_stock_usage_history()
    return {"status": "success", "data": {"history": history}}


# ─── Desktop-only stubs (printing, backup, etc.) ─────────────────────────────

def handle_navigate_to(payload):
    """On mobile, navigation is handled client-side by the shim."""
    return {"status": "success"}

def handle_open_whatsapp_url(payload):
    """On mobile, just return the URL - the shim opens it via window.open()."""
    url = payload.get("url", "")
    return {"status": "success", "data": {"url": url}}

def handle_print_receipt(payload):
    return {"status": "error", "message": "Printing is only available on the desktop app."}

def handle_print_stitching_slip(payload):
    return {"status": "error", "message": "Printing is only available on the desktop app."}

def handle_print_pos_document(payload):
    return {"status": "error", "message": "Printing is only available on the desktop app."}

def handle_print_html_document(payload):
    return {"status": "error", "message": "Printing is only available on the desktop app."}

def handle_save_pdf(payload):
    return {"status": "error", "message": "PDF saving is only available on the desktop app."}

def handle_start_dictation(payload):
    return {"status": "error", "message": "Voice dictation is only available on the desktop app."}

def handle_stop_dictation(payload):
    return {"status": "error", "message": "Voice dictation is only available on the desktop app."}

def handle_copy_to_clipboard(payload):
    return {"status": "success"}

def handle_open_url(payload):
    url = payload.get("url", "")
    return {"status": "success", "data": {"url": url}}

def handle_create_backup(payload):
    return {"status": "error", "message": "Backup is only available on the desktop app."}

def handle_restore_backup(payload):
    return {"status": "error", "message": "Restore is only available on the desktop app."}

def handle_erase_all_data(payload):
    return {"status": "error", "message": "Data reset is only available on the desktop app."}


# ─── Action handler map (matches web_bridge.py dispatch action names) ─────────

ACTION_HANDLERS = {
    # Navigation / Desktop-only
    "navigate_to": handle_navigate_to,
    "copy_to_clipboard": handle_copy_to_clipboard,
    "open_url": handle_open_url,
    "open_whatsapp_url": handle_open_whatsapp_url,
    
    # Printing (desktop-only stubs)
    "print_receipt": handle_print_receipt,
    "print_stitching_slip": handle_print_stitching_slip,
    "print_pos_document": handle_print_pos_document,
    "print_html_document": handle_print_html_document,
    "save_pdf": handle_save_pdf,
    
    # Dictation (desktop-only stubs)
    "start_dictation": handle_start_dictation,
    "stop_dictation": handle_stop_dictation,
    
    # Settings
    "get_settings": handle_get_settings,
    "update_settings": handle_update_settings,
    "get_worker_portal_url": handle_get_worker_portal_url,
    
    # Dashboard
    "get_dashboard_stats": handle_get_dashboard_stats,
    
    # Customers
    "get_customers": handle_get_customers,
    "get_customer_details": handle_get_customer_details,
    "create_customer": handle_create_customer,
    "update_customer": handle_update_customer,
    "delete_customer": handle_delete_customer,
    "get_customer_qr_url": handle_get_customer_qr_url,
    
    # Measurements
    "get_all_measurements": handle_get_all_measurements,
    "get_measurements_for_customer": handle_get_measurements_for_customer,
    "create_measurement": handle_create_measurement,
    
    # Orders
    "create_order": handle_create_order,
    "update_order": handle_update_order,
    "get_all_orders": handle_get_all_orders,
    "get_order_details": handle_get_order_details,
    "update_order_status": handle_update_order_status,
    "generate_payment_reminder_whatsapp": handle_generate_payment_reminder_whatsapp,
    
    # Payments
    "get_all_payments": handle_get_all_payments,
    "get_payments_dashboard": handle_get_payments_dashboard,
    "create_payment": handle_create_payment,
    "get_worker_payment_summary": handle_get_worker_payment_summary,
    "get_stock_payment_summary": handle_get_stock_payment_summary,
    
    # Deliveries
    "get_deliveries_dashboard": handle_get_deliveries_dashboard,
    
    # Expenses
    "get_expenses_dashboard": handle_get_expenses_dashboard,
    "create_expense": handle_create_expense,
    "delete_expense": handle_delete_expense,
    
    # Reports
    "get_report_data": handle_get_report_data,
    
    # Workers
    "get_all_workers": handle_get_all_workers,
    "add_worker": handle_add_worker,
    "assign_task": handle_assign_task,
    "get_worker_tasks": handle_get_worker_tasks,
    "get_garment_rates": handle_get_garment_rates,
    "set_garment_rate": handle_set_garment_rate,
    "delete_garment_rate": handle_delete_garment_rate,
    "get_all_pending_entries": handle_get_all_pending_entries,
    "approve_entry": handle_approve_entry,
    "edit_pending_entry": handle_edit_pending_entry,
    "record_advance": handle_record_advance,
    "get_worker_ledger": handle_get_worker_ledger,
    "delete_worker": handle_delete_worker,
    "get_worker_history": handle_get_worker_history,
    "settle_worker_account": handle_settle_worker_account,
    "submit_manual_work": handle_submit_manual_work,
    
    # Stock
    "get_all_stock": handle_get_all_stock,
    "get_low_stock": handle_get_low_stock,
    "add_stock_item": handle_add_stock_item,
    "update_stock_item": handle_update_stock_item,
    "adjust_stock": handle_adjust_stock,
    "delete_stock_item": handle_delete_stock_item,
    "get_stock_usage_history": handle_get_stock_usage_history,
    
    # Backup (desktop-only stubs)
    "create_backup": handle_create_backup,
    "restore_backup": handle_restore_backup,
    "erase_all_data": handle_erase_all_data,
}
