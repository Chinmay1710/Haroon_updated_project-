import json, os, subprocess
f=os.path.join(os.environ['HOME'], 'Library', 'Application Support', 'TailorShopManager', 'cloudflare_config.json')
t = json.load(open(f))['token']
p = subprocess.Popen(["cloudflared", "tunnel", "run", "--token", t], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
import time
time.sleep(10)
p.kill()
stdout, _ = p.communicate()
print("Cloudflare output:")
print(stdout)
