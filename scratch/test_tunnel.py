from app.web.tunnel import NgrokTunnel
import time
t = NgrokTunnel(port=8000)
print("URL:", t.start())
time.sleep(5)
import psutil
for p in psutil.process_iter(['name']):
    if 'cloudflared' in p.info['name']:
        print("Found cloudflared!")
