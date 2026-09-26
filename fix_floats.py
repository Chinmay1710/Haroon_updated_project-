import re

with open("app/web/admin_routes.py", "r") as f:
    content = f.read()

# Replace float(payload.get(...)) with safe_float(payload.get(...))
content = re.sub(r'float\(payload\.get', 'safe_float(payload.get', content)

# But wait, what about the manual fixes I just made?
# I did:
# daily_rate_raw = payload.get("daily_rate", 0.0)
# try: daily_rate = float(daily_rate_raw) if daily_rate_raw != "" else 0.0
# etc...
# I can just revert those manual fixes and use safe_float(payload.get(...))

