import sys
import os
os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = "--no-sandbox --disable-gpu"
os.environ["QT_MAC_WANTS_LAYER"] = "1"
from PySide6.QtWidgets import QApplication, QMainWindow
from PySide6.QtWebEngineWidgets import QWebEngineView
app = QApplication(sys.argv)
window = QMainWindow()
view = QWebEngineView(window)
window.setCentralWidget(view)
view.setHtml("<h1>Hello World</h1>")
window.show()
sys.exit(app.exec())
