FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# INGEST_MODE=live -> Finnhub WebSocket, INGEST_MODE=simulate -> fake data
CMD ["sh", "-c", "if [ \"$INGEST_MODE\" = 'live' ]; then python -u main.py; else python -u simulator.py; fi"]
