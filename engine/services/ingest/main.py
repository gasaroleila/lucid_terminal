import asyncio
import json
import os
import signal
import time

import websockets
from confluent_kafka import Producer

FINNHUB_API_KEY = os.environ["FINNHUB_API_KEY"]
KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "kafka:9092")
TOPIC = "raw-quotes"
SYMBOLS = os.environ.get("SYMBOLS", "AAPL,MSFT,GOOGL,AMZN,TSLA").split(",")

producer = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})
running = True


def delivery_report(err, msg):
    if err:
        print(f"Delivery failed: {err}")


def shutdown(sig, frame):
    global running
    print(f"Received {signal.Signals(sig).name}, shutting down...")
    running = False


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)


async def ingest():
    uri = f"wss://ws.finnhub.io?token={FINNHUB_API_KEY}"

    while running:
        try:
            async with websockets.connect(uri) as ws:
                print(f"Connected to Finnhub WebSocket")

                for symbol in SYMBOLS:
                    await ws.send(json.dumps({"type": "subscribe", "symbol": symbol}))
                    print(f"Subscribed to {symbol}")

                print("Waiting for trades (only available during US market hours)...")
                trade_count = 0

                while running:
                    try:
                        raw = await asyncio.wait_for(ws.recv(), timeout=30)
                    except asyncio.TimeoutError:
                        print("No data in 30s (market may be closed), still connected...")
                        continue

                    msg = json.loads(raw)
                    if msg.get("type") != "trade":
                        continue

                    for trade in msg.get("data", []):
                        quote = {
                            "symbol": trade["s"],
                            "price": trade["p"],
                            "volume": trade["v"],
                            "timestamp": trade["t"] / 1000.0,
                            "ingested_at": time.time(),
                        }
                        producer.produce(
                            TOPIC,
                            key=quote["symbol"],
                            value=json.dumps(quote),
                            callback=delivery_report,
                        )

                    trade_count += len(msg.get("data", []))
                    if trade_count % 100 == 0:
                        print(f"Produced {trade_count} quotes to raw-quotes")

                    producer.poll(0)

        except (websockets.ConnectionClosed, OSError) as e:
            print(f"Connection lost: {e}, reconnecting in 5s...")
            await asyncio.sleep(5)

    producer.flush(timeout=5)
    print("Shutdown complete.")


if __name__ == "__main__":
    asyncio.run(ingest())
