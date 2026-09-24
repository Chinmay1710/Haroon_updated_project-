import re
import sys

filepath = "app/web/api_bridge.py"

with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

# Remove PySide6 imports
content = re.sub(r'from PySide6.*?import.*?\n', '', content)
content = re.sub(r'class WebBridge\(QObject\):', 'class ApiBridge:\n    """Headless API Bridge for Web App"""', content)
content = re.sub(r'\s+super\(\)\.__init__\(parent\)', '', content)
content = re.sub(r'def __init__\(self, services, parent=None\):', 'def __init__(self, services):', content)
content = re.sub(r'\s+navigate_requested = Signal\(str\).*?\n', '\n', content)
content = re.sub(r'\s+backup_requested = Signal\(\).*?\n', '\n', content)
content = re.sub(r'\s+restore_requested = Signal\(\).*?\n', '\n', content)
content = re.sub(r'\s+notification_requested = Signal\(str, str\).*?\n', '\n', content)
content = re.sub(r'\s+dictation_result_requested = Signal\(str, str, str\).*?\n', '\n', content)
content = re.sub(r'\s+customer_added = Signal\(\).*?\n', '\n', content)
content = re.sub(r'\s+order_added = Signal\(\).*?\n', '\n', content)
content = re.sub(r'\s+save_pdf_requested = Signal\(str, str\).*?\n', '\n', content)

# Remove @Slot decorators
content = re.sub(r'\s+@Slot\(str\)', '', content)
content = re.sub(r'\s+@Slot\(str, str\)', '', content)

# Remove self.dictation_service (it depends on QObject)
content = re.sub(r'\s+from app\.services\.dictation_service import DictationService\s+self\.dictation_service = DictationService\(self\)\s+self\.dictation_service\.dictation_finished\.connect\(self\.dictation_result_requested\.emit\)', '', content)

with open(filepath, "w", encoding="utf-8") as f:
    f.write(content)

print("api_bridge.py modified.")
