import re

with open("app/ui/web_bridge.py", "r") as f:
    content = f.read()

# Add safe_float at the top if not exists
if "def safe_float" not in content:
    imports_end = content.find("logger = get_logger")
    safe_float_code = """
def safe_float(val, default=0.0):
    try:
        if val == "" or val is None:
            return default
        return float(val)
    except (ValueError, TypeError):
        return default

"""
    # Insert after logger
    logger_line_end = content.find("\n", imports_end) + 1
    content = content[:logger_line_end] + safe_float_code + content[logger_line_end:]

# Replace float(payload.get(...)) with safe_float(payload.get(...))
content = re.sub(r'float\(payload\.get', 'safe_float(payload.get', content)

with open("app/ui/web_bridge.py", "w") as f:
    f.write(content)

