# WAHA PDF Sender

Set required variables, then run:

```bash
python -m venv .venv
source .venv/bin/activate
pip install reportlab requests
python send_pdf.py
```

Required variables: `WAHA_URL`, `WAHA_API_KEY`, `WAHA_CHAT_ID`, `WAHA_SESSION`.
