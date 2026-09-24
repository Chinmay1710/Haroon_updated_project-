import json
import os

local_file = 'cloudflare_config.json'
with open(local_file, 'r') as f:
    local_data = json.load(f)

raw_token = local_data['token']
if 'cloudflared.exe service install ' in raw_token:
    raw_token = raw_token.replace('cloudflared.exe service install ', '').strip()

# update local file for consistency
local_data['token'] = raw_token
with open(local_file, 'w') as f:
    json.dump(local_data, f, indent=2)

app_data_file = os.path.expanduser('~/Library/Application Support/TailorShopManager/cloudflare_config.json')
with open(app_data_file, 'r') as f:
    app_data = json.load(f)

app_data['token'] = raw_token
with open(app_data_file, 'w') as f:
    json.dump(app_data, f, indent=2)

print("Token successfully extracted and saved.")
