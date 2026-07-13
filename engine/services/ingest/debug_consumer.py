"""Consume and print messages from raw-quotes for debugging.

Usage (from engine/ dir):
  docker compose exec ingest python -u debug_consumer.py
  docker compose exec ingest python -u debug_consumer.py --count 10
"""
import argparse
import json

from confluent_kafka import Consumer

parser = argparse.ArgumentParser()
parser.add_argument("--count", type=int, default=5, help="Number of messages to print")
parser.add_argument("--topic", default="raw-quotes")
parser.add_argument("--bootstrap", default="engine-kafka-1:9092")
args = parser.parse_args()

c = Consumer({
    "bootstrap.servers": args.bootstrap,
    "group.id": "debug-consumer",
    "auto.offset.reset": "earliest",
})
c.subscribe([args.topic])

print(f"Consuming {args.count} messages from '{args.topic}'...\n")

received = 0
while received < args.count:
    msg = c.poll(5.0)
    if msg is None:
        print("(waiting...)")
        continue
    if msg.error():
        print(f"Error: {msg.error()}")
        continue
    payload = json.loads(msg.value())
    received += 1
    print(f"[{received}] partition={msg.partition()} offset={msg.offset()}")
    print(json.dumps(payload, indent=2))
    print()

c.close()
print("Done.")
