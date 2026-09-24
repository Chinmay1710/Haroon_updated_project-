from PySide6.QtWidgets import QApplication
from PySide6.QtWebEngineCore import QWebEnginePage
import sys
app = QApplication(sys.argv)
page = QWebEnginePage()
def on_pdf(result, _):
    print("PDF result:", type(result))
    app.quit()
page.setHtml("<html><body>Hello</body></html>")
page.printToPdf("test.pdf")
page.pdfPrintingFinished.connect(lambda p, s: print("Finished", p, s) or app.quit())
app.exec()
