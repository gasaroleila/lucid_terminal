import json
import os
import random
import signal
import time

from confluent_kafka import Producer

KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "engine-kafka-1:9092")
TOPIC = "raw-quotes"
TICK_RATE = float(os.environ.get("TICK_RATE", "10"))  # ticks per second

SYMBOLS = {
    "AAPL": 187.00,
    "MSFT": 420.00,
    "NVDA": 130.00,
    "GOOGL": 175.00,
    "AMZN": 185.00,
    "TSLA": 250.00,
}

producer = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})
running = True


def shutdown(sig, frame):
    global running
    print(f"Received {signal.Signals(sig).name}, shutting down...")
    running = False


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)


def delivery_report(err, msg):
    if err:
        print(f"Delivery failed: {err}")


def simulate():
    prices = dict(SYMBOLS)
    tick_count = 0
    interval = 1.0 / TICK_RATE

    print(f"Simulator started: {len(prices)} symbols, {TICK_RATE} ticks/sec")

    while running:
        symbol = random.choice(list(prices.keys()))

        # small random walk with drift
        drift = random.gauss(0, 0.10)
        prices[symbol] = round(max(1.0, prices[symbol] + drift), 2)

        # occasional volume spike (~5% chance)
        if random.random() < 0.05:
            volume = random.randint(5000, 20000)
        else:
            volume = random.randint(100, 1000)

        quote = {
            "symbol": symbol,
            "price": prices[symbol],
            "volume": volume,
            "timestamp": time.time(),
            "ingested_at": time.time(),
            "simulated": True,
        }

        producer.produce(
            TOPIC,
            key=symbol,
            value=json.dumps(quote),
            callback=delivery_report,
        )
        producer.poll(0)

        tick_count += 1
        if tick_count % 100 == 0:
            producer.flush(timeout=5)
            print(f"Produced {tick_count} simulated quotes")

        time.sleep(interval)

    producer.flush(timeout=5)
    print(f"Shutdown complete. Total quotes: {tick_count}")


if __name__ == "__main__":
    simulate()
