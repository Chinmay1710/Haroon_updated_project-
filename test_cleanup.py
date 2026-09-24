import sys, os
sys.path.append(os.getcwd())
from app.services.backup_service import BackupService

b = BackupService()
print("Backup created at:", b.create_backup())

backup_dir = "/Users/chinmay/Library/Application Support/TailorShopManager/backups"
print("Files left in backups:")
for f in os.listdir(backup_dir):
    print(" -", f)

