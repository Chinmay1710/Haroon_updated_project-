import re

with open("app/web/api_bridge.py", "r", encoding="utf-8") as f:
    content = f.read()

# Replace create_backup block
content = re.sub(
    r'elif action == "create_backup":.*?elif action == "restore_backup":',
    'elif action == "create_backup":\n                response = {"status": "error", "message": "Cloud Backup Active"}\n\n            elif action == "restore_backup":',
    content,
    flags=re.DOTALL
)

# Replace restore_backup block
content = re.sub(
    r'elif action == "restore_backup":.*?elif action == "erase_all_data":',
    'elif action == "restore_backup":\n                response = {"status": "error", "message": "Use Cloud Console"}\n\n            elif action == "erase_all_data":',
    content,
    flags=re.DOTALL
)

# Replace erase_all_data block
content = re.sub(
    r'elif action == "erase_all_data":.*?# ────────────────────────────────────────────────────────────',
    'elif action == "erase_all_data":\n                response = {"status": "error", "message": "Disabled for security"}\n\n            # ────────────────────────────────────────────────────────────',
    content,
    flags=re.DOTALL
)

with open("app/web/api_bridge.py", "w", encoding="utf-8") as f:
    f.write(content)

print("Fixed backup blocks.")
