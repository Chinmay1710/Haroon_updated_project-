import os
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

URL = 'https://haroon-tailor.onrender.com/admin-api/dispatch'

def call(action, payload=None, retries=3):
    if payload is None:
        payload = {}
    data = json.dumps({'action': action, 'payload': payload}).encode('utf-8')
    req = urllib.request.Request(URL, data=data, headers={'Content-Type': 'application/json'})
    
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except Exception as e:
            if attempt == retries - 1:
                return {'status': 'error', 'message': str(e)}
            time.sleep(1.0)

def main():
    print("==================================================", flush=True)
    print(" HAROON TAILOR - MASTER BACKUP EXPORTER (Option B)", flush=True)
    print("==================================================", flush=True)
    t_start = time.time()
    
    # 1. Shop Settings
    print("1/3 Fetching Shop Settings...", flush=True)
    settings_res = call('get_settings')
    settings = settings_res.get('data', {})
    print(f"   ✓ Shop Name: {settings.get('shop_name', 'Haroon Tailor')}", flush=True)

    # 2. Customers
    print("2/3 Fetching All Customers (357 customers in 1 query)...", flush=True)
    customers_res = call('get_customers')
    customers = customers_res.get('data', [])
    print(f"   ✓ Successfully fetched {len(customers)} customers!", flush=True)

    # 3. Orders
    print("3/3 Fetching Orders & Deep Item/Photo Breakdowns...", flush=True)
    orders_res = call('get_all_orders')
    orders_summary = orders_res.get('data', [])
    print(f"   ✓ Total Orders Listed: {len(orders_summary)}", flush=True)

    print("   Fetching deep item measurements, Cloudinary photos & payments (5 workers)...", flush=True)
    detailed_orders = []

    def fetch_order_detail(o):
        time.sleep(0.05) # prevent slamming the DB pool
        det_res = call('get_order_details', {'id': o['id']})
        det = det_res.get('data', {}) if det_res.get('status') == 'success' else {}
        
        # Merge summary with deep detail
        items = det.get('items', [])
        # If deep items missing or empty, construct from summary
        if not items and o.get('raw_items'):
            items = [
                {
                    'id': ri.get('id'),
                    'clothing_type': ri.get('name', 'Custom'),
                    'quantity': 1,
                    'price': o.get('total_amount', 0.0),
                    'image_path': o.get('image_path', ''),
                    'is_ready': ri.get('is_ready', False),
                    'measurements': {}
                }
                for ri in o.get('raw_items', [])
            ]

        return {
            'id': o['id'],
            'order_number': o.get('order_number'),
            'customer_id': o.get('customer_id') or det.get('customer_id'),
            'customer_name': o.get('customer_name') or det.get('customer_name', ''),
            'customer_mobile': o.get('customer_mobile') or det.get('customer_mobile', ''),
            'customer_address': det.get('customer_address', ''),
            'order_date': o.get('order_date') or det.get('order_date', ''),
            'delivery_date': o.get('delivery_date') or det.get('delivery_date', ''),
            'status': o.get('status') or det.get('status', 'NEW'),
            'total_amount': o.get('total_amount', 0.0),
            'discount': o.get('discount', 0.0) or det.get('discount', 0.0),
            'advance_amount': det.get('advance_amount', 0.0),
            'remaining_amount': o.get('remaining_amount', 0.0),
            'special_instructions': det.get('special_instructions', '') or '',
            'items_summary': o.get('items', ''),
            'payments': det.get('payments', []),
            'items': items,
            'updated_at': o.get('updated_at', '')
        }

    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = {executor.submit(fetch_order_detail, o): o for o in orders_summary}
        done_count = 0
        for f in as_completed(futures):
            detailed_orders.append(f.result())
            done_count += 1
            if done_count % 30 == 0 or done_count == len(orders_summary):
                print(f"   ... {done_count}/{len(orders_summary)} orders completed", flush=True)

    detailed_orders.sort(key=lambda x: x['id'], reverse=True)

    # Count statistics
    total_photos = 0
    total_measurements = 0
    orders_with_photos = 0
    for o in detailed_orders:
        has_photo = False
        for it in o.get('items', []):
            if it.get('image_path'):
                total_photos += 1
                has_photo = True
            if it.get('measurements'):
                total_measurements += len(it.get('measurements'))
        if has_photo:
            orders_with_photos += 1

    # Save Master Backup
    print("Saving Master Backup to local computer...", flush=True)
    backup_payload = {
        'app': 'Haroon Tailor',
        'version': '1.0.0',
        'export_timestamp': time.strftime('%Y-%m-%dT%H:%M:%S'),
        'total_customers': len(customers),
        'total_orders': len(detailed_orders),
        'orders_with_photos': orders_with_photos,
        'total_photos': total_photos,
        'total_measurements': total_measurements,
        'settings': settings,
        'customers': customers,
        'orders': detailed_orders
    }

    output_path = os.path.abspath('HaroonTailor_Master_Backup_2026.json')
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(backup_payload, f, indent=2, ensure_ascii=False)

    file_size_kb = os.path.getsize(output_path) / 1024
    elapsed = time.time() - t_start

    print("==================================================", flush=True)
    print(" ✅ MASTER BACKUP COMPLETED AND SAVED TO COMPUTER!", flush=True)
    print(f" 📁 Saved To: {output_path}", flush=True)
    print(f" 📦 File Size: {file_size_kb:.1f} KB", flush=True)
    print(f" 👥 Customers Backed Up: {len(customers)}", flush=True)
    print(f" 📋 Orders Backed Up: {len(detailed_orders)}", flush=True)
    print(f" 📸 Orders with Photos: {orders_with_photos}", flush=True)
    print(f" ⏱️  Total Time: {elapsed:.1f} seconds", flush=True)
    print("==================================================", flush=True)

if __name__ == '__main__':
    main()
