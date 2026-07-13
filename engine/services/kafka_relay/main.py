"""Kafka relay — consumes raw-quotes + sentiment and serves them
over a TCP socket as newline-delimited JSON for the OCaml engine.

Protocol: each line is a JSON object with a "topic" field:
  {"topic":"raw-quotes","symbol":"AAPL","price":187.12,...}
  {"topic":"sentiment","symbol":"AAPL","score":0.65,...}
"""

import json
import os
import signal
import socket
import threading
import time

from confluent_kafka import Consumer, KafkaError

KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "kafka:9092")
LISTEN_HOST = os.environ.get("RELAY_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("RELAY_PORT", "9100"))
TOPICS = ["raw-quotes", "sentiment"]

running = True
clients = []
clients_lock = threading.Lock()


def shutdown(sig, frame):
    global running
    print(f"Received {signal.Signals(sig).name}, shutting down...")
    running = False


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)


def accept_clients(server_sock):
    """Accept incoming TCP connections from the OCaml engine."""
    while running:
        try:
            server_sock.settimeout(1.0)
            conn, addr = server_sock.accept()
            with clients_lock:
                clients.append(conn)
            print(f"Client connected: {addr}")
        except socket.timeout:
            continue
        except OSError:
            break


def broadcast(line: str):
    """Send a line to all connected clients."""
    data = (line + "\n").encode()
    with clients_lock:
        dead = []
        for conn in clients:
            try:
                conn.sendall(data)
            except (BrokenPipeError, ConnectionResetError, OSError):
                dead.append(conn)
        for conn in dead:
            clients.remove(conn)
            conn.close()
            print("Client disconnected")


def consume_loop():
    """Consume from Kafka and broadcast to connected clients."""
    consumer = Consumer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": "kafka-relay",
        "auto.offset.reset": "latest",
    })
    consumer.subscribe(TOPICS)
    print(f"Subscribed to Kafka topics: {TOPICS}")

    msg_count = 0
    while running:
        msg = consumer.poll(1.0)
        if msg is None:
            continue
        if msg.error():
            if msg.error().code() != KafkaError._PARTITION_EOF:
                print(f"Kafka error: {msg.error()}")
            continue

        payload = json.loads(msg.value().decode())
        payload["topic"] = msg.topic()
        line = json.dumps(payload)
        broadcast(line)

        msg_count += 1
        if msg_count % 100 == 0:
            print(f"Relayed {msg_count} messages")

    consumer.close()


if __name__ == "__main__":
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(5)
    print(f"Relay listening on {LISTEN_HOST}:{LISTEN_PORT}")

    accept_thread = threading.Thread(target=accept_clients, args=(server,), daemon=True)
    accept_thread.start()

    try:
        consume_loop()
    finally:
        server.close()
        with clients_lock:
            for conn in clients:
                conn.close()
        print("Shutdown complete.")
