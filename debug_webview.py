import sys, os, json
from PySide6.QtCore import Qt, QUrl
from PySide6.QtWidgets import QApplication, QMainWindow, QVBoxLayout, QWidget
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWebEngineCore import QWebEngineProfile, QWebEnginePage

class DebugPage(QWebEnginePage):
    def javaScriptConsoleMessage(self, level, message, lineNumber, sourceID):
        levels = {
            QWebEnginePage.InfoMessageLevel: "INFO",
            QWebEnginePage.WarningMessageLevel: "WARN",
            QWebEnginePage.ErrorMessageLevel: "ERROR"
        }
        print(f"[JS {levels.get(level, 'DEBUG')}] {sourceID}:{lineNumber} -> {message}")

class DebugWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        
        # Let's just run main_window! We can override its web_view page!
        from app.ui.main_window import MainWindow
        from app.database.engine import init_db
        init_db()
        self.main_win = MainWindow()
        
        # Override the page to intercept console logs!
        class MyPage(QWebEnginePage):
            def javaScriptConsoleMessage(self, level, message, lineNumber, sourceID):
                print(f"[JS] {message}")
                
        self.main_win.web_view.setPage(MyPage(self.main_win.web_view))
        self.main_win.web_view.page().setWebChannel(self.main_win.channel)
        self.main_win.web_view.setUrl(QUrl.fromLocalFile(os.path.join(os.getcwd(), "app/assets/www/html/orders_list.html")))
        
        self.setCentralWidget(self.main_win.web_view)
        self.show()

app = QApplication.instance()
if not app:
    app = QApplication(sys.argv)
win = DebugWindow()
# Close after 10 seconds automatically
from PySide6.QtCore import QTimer
QTimer.singleShot(10000, app.quit)
app.exec()
