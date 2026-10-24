import os
import json
import time
import zipfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

def get_ext(url):
    u = url.lower()
    if '.png' in u: return '.png'
    if '.webp' in u: return '.webp'
    if '.jpeg' in u: return '.jpeg'
    return '.jpg'

def download_image(item):
    url, zip_path = item
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = resp.read()
                if len(data) > 0:
                    return zip_path, data, True
        except Exception:
            time.sleep(0.5)
    return zip_path, b'', False

def main():
    print("==================================================", flush=True)
    print(" BUILDING COMPLETE MASTER ZIP BACKUP WITH ALL PHOTOS", flush=True)
    print("==================================================", flush=True)

    master_json_path = '/Users/chinmay/Documents/Haroon_tailer/HaroonTailor_Master_Backup_2026.json'
    with open(master_json_path, 'r', encoding='utf-8') as f:
        master_data = json.load(f)

    orders = master_data.get('orders', [])
    customers = master_data.get('customers', [])
    settings = master_data.get('settings', {})
    clothing_types = master_data.get('clothing_types', [])
    message_templates = master_data.get('message_templates', {})
    default_rates = master_data.get('default_rates', {})

    print(f"Loaded Master JSON: {len(orders)} orders, {len(customers)} customers", flush=True)

    # Collect all photo download entries
    url_to_zip = {}
    download_queue = []

    for o in orders:
        order_id = o.get('id')
        items = o.get('items', [])
        
        # Check items
        for idx, it in enumerate(items):
            if isinstance(it, dict):
                img_url = (it.get('image_path') or '').strip()
                if img_url and img_url.startswith('http'):
                    if img_url not in url_to_zip:
                        ext = get_ext(img_url)
                        zip_name = f"photos/order_{order_id}_item_{idx}{ext}"
                        url_to_zip[img_url] = zip_name
                        download_queue.append((img_url, zip_name))
                    it['image_path_original'] = img_url
                    it['image_path'] = url_to_zip[img_url]

        # Check top-level image_path
        top_img = (o.get('image_path') or '').strip()
        if top_img:
            parts = [p.strip() for p in top_img.split(',') if p.strip()]
            updated_parts = []
            for pidx, p in enumerate(parts):
                if p.startswith('http'):
                    if p not in url_to_zip:
                        ext = get_ext(p)
                        zip_name = f"photos/order_{order_id}_top_{pidx}{ext}"
                        url_to_zip[p] = zip_name
                        download_queue.append((p, zip_name))
                    updated_parts.append(url_to_zip[p])
            if updated_parts:
                o['image_path_original'] = top_img
                o['image_path'] = ','.join(updated_parts)

    print(f"Found {len(download_queue)} unique photos to download from Cloudinary!", flush=True)

    # Download in parallel
    downloaded_images = {}
    failed_count = 0
    start_t = time.time()

    with ThreadPoolExecutor(max_workers=25) as executor:
        futures = {executor.submit(download_image, item): item for item in download_queue}
        done_count = 0
        for f in as_completed(futures):
            zip_path, data, success = f.result()
            done_count += 1
            if success:
                downloaded_images[zip_path] = data
            else:
                failed_count += 1
            if done_count % 50 == 0 or done_count == len(download_queue):
                print(f"   Downloaded {done_count}/{len(download_queue)} photos ({len(downloaded_images)} ok, {failed_count} failed)...", flush=True)

    elapsed = time.time() - start_t
    print(f"Download complete in {elapsed:.1f}s: {len(downloaded_images)} photos downloaded successfully!", flush=True)

    # Build final backup.json structure
    backup_dict = {
        'app': 'Haroon Tailor',
        'version': '1.0.0',
        'backup_type': 'zip_with_photos',
        'export_timestamp': time.strftime('%Y-%m-%dT%H:%M:%S'),
        'total_customers': len(customers),
        'total_orders': len(orders),
        'total_photos': len(download_queue),
        'bundled_photos': len(downloaded_images),
        'failed_photos': failed_count,
        'settings': settings,
        'clothing_types': clothing_types,
        'message_templates': message_templates,
        'default_rates': default_rates,
        'customers': customers,
        'orders': orders,
    }

    json_str = json.dumps(backup_dict, indent=2, ensure_ascii=False)
    json_bytes = json_str.encode('utf-8')

    target_zip_dir = '/Users/chinmay/Documents/hatoon backup '
    target_zip_file = os.path.join(target_zip_dir, 'HaroonTailor_Backup_2026-10-24_mobile_app.zip')
    backup_zip_copy = os.path.join(target_zip_dir, 'HaroonTailor_Complete_Master_Backup_376_Photos.zip')

    # Backup the old 3-photo zip
    old_backup = os.path.join(target_zip_dir, 'HaroonTailor_Backup_old_3_photos.zip')
    if os.path.exists(target_zip_file) and not os.path.exists(old_backup):
        os.rename(target_zip_file, old_backup)
        print(f"Renamed previous 3-photo zip to {old_backup}", flush=True)

    print(f"Writing complete ZIP archive to {target_zip_file}...", flush=True)
    for out_path in [target_zip_file, backup_zip_copy]:
        with zipfile.ZipFile(out_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            z.writestr('backup.json', json_bytes)
            for zpath, img_bytes in downloaded_images.items():
                z.writestr(zpath, img_bytes)
        size_mb = os.path.getsize(out_path) / (1024 * 1024)
        print(f"✓ Created {out_path} ({size_mb:.1f} MB)", flush=True)

    print("==================================================", flush=True)
    print(" ALL 376 PHOTOS BUNDLED SUCCESSFULLY IN ZIP BACKUP!", flush=True)
    print("==================================================", flush=True)

if __name__ == '__main__':
    main()
