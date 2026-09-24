import sys
import os

# Ensure project root is in path
sys.path.insert(0, os.path.abspath("."))

from app.database.firebase_engine import get_collection

try:
    doc = get_collection("shop_settings").document("singleton").get()
    if doc.exists:
        data = doc.to_dict()
        print("Settings in Firebase:")
        for k, v in data.items():
            print(f"  {k}: {v}")
    else:
        print("No settings document found.")
except Exception as e:
    print(f"Error: {e}")
