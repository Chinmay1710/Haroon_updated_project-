import re

with open("app/web/api_bridge.py", "r", encoding="utf-8") as f:
    content = f.read()

# Remove all decorators starting with @
content = re.sub(r'\s+@Slot\(.*?\)', '', content)
content = re.sub(r'@Slot\(.*?\)', '', content)

with open("app/web/api_bridge.py", "w", encoding="utf-8") as f:
    f.write(content)

print("Stripped Slot decorators.")
