import json, os, subprocess
f=os.path.join(os.environ['HOME'], 'Library', 'Application Support', 'TailorShopManager', 'cloudflare_config.json')
t = json.load(open(f))['token']
p = subprocess.Popen(["cloudflared", "tunnel", "run", "--token", t], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("Started cloudflared with PID:", p.pid)
