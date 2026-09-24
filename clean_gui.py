import re

with open("app/web/api_bridge.py", "r", encoding="utf-8") as f:
    content = f.read()

# Remove clipboard and desktop services
content = re.sub(
    r'elif action == "copy_to_clipboard":.*?response = \{"status": "success"\}',
    'elif action == "copy_to_clipboard":\n                response = {"status": "success", "message": "Ignored on web"}',
    content,
    flags=re.DOTALL
)

content = re.sub(
    r'elif action == "open_url":.*?response = \{"status": "success"\}',
    'elif action == "open_url":\n                response = {"status": "success", "message": "Ignored on web"}',
    content,
    flags=re.DOTALL
)

content = re.sub(
    r'elif action == "open_whatsapp_url":.*?response = \{"status": "success"\}',
    'elif action == "open_whatsapp_url":\n                response = {"status": "success", "url": payload.get("url", "")}',
    content,
    flags=re.DOTALL
)

with open("app/web/api_bridge.py", "w", encoding="utf-8") as f:
    f.write(content)

print("GUI imports removed.")
