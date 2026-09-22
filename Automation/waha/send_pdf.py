
import os
import base64
import sys
from datetime import datetime
from pathlib import Path

import requests
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas


PDF_PATH = Path("report.pdf")


def required_env(name: str) -> str:
    """Return a required environment variable or raise a useful error."""

    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(
            f"Missing required environment variable: {name}. "
            f"Set it before running {Path(__file__).name}."
        )
    return value


def generate_pdf(path: Path):
    """Generate a simple PDF document."""

    pdf = canvas.Canvas(str(path), pagesize=A4)

    width, height = A4

    # Title
    pdf.setFont("Helvetica-Bold", 20)
    pdf.drawString(50, height - 70, "Automated PDF Report")

    # Date
    pdf.setFont("Helvetica", 11)
    pdf.drawString(
        50,
        height - 110,
        f"Generated: {datetime.now():%Y-%m-%d %H:%M:%S}"
    )

    # Content
    pdf.setFont("Helvetica", 12)

    lines = [
        "Hello from Python!",
        "",
        "This PDF was generated automatically.",
        "It is being delivered through WAHA and WhatsApp.",
        "",
        "WAHA Server: waha.local.jazziro.com",
        "Session: " + required_env("WAHA_SESSION"),
    ]

    y = height - 160

    for line in lines:
        pdf.drawString(50, y, line)
        y -= 25

    pdf.save()

    print(f"PDF generated: {path.resolve()}")


def send_pdf(path: Path):
    """Send a PDF document through WAHA."""

    waha_url = required_env("WAHA_URL")
    waha_api_key = required_env("WAHA_API_KEY")
    chat_id = required_env("WAHA_CHAT_ID")
    waha_session = required_env("WAHA_SESSION")

    # Read PDF and encode as Base64
    pdf_bytes = path.read_bytes()

    pdf_base64 = base64.b64encode(
        pdf_bytes
    ).decode("ascii")

    # WAHA API request
    payload = {
        "session": waha_session,
        "chatId": chat_id,
        "caption": "Here is your generated PDF report.",
        "file": {
            "mimetype": "application/pdf",
            "filename": path.name,
            "data": pdf_base64
        }
    }

    headers = {
        "X-Api-Key": waha_api_key,
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    response = requests.post(
        f"{waha_url.rstrip('/')}/api/sendFile",
        json=payload,
        headers=headers,
        timeout=120
    )

    # Raise an error if WAHA rejects the request
    if not response.ok:
        print(f"WAHA error ({response.status_code}):")
        print(response.text)
        response.raise_for_status()

    print("PDF submitted successfully to WAHA!")
    print(response.json())


if __name__ == "__main__":
    try:
        generate_pdf(PDF_PATH)
        send_pdf(PDF_PATH)
    except RuntimeError as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        sys.exit(1)
