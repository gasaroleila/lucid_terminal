"""spike_test.py — Message loss test under 1x and 10x traffic spikes.

Pipeline under test:
  [this script as producer] → Kafka(raw-quotes) → [kafka-relay] → TCP:9100 → [this script as consumer]

Requires: docker compose services 'kafka' and 'kafka-relay' running.
Run from engine/ dir:
  docker compose up -d kafka kafka-relay
  pip install confluent-kafka   # or run inside a venv
  python bench/spike_test.py
"""

import json
import os
import socket
import sys
import threading
import time

from confluent_kafka import Producer, KafkaError

KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "localhost:9092")
RELAY_HOST = os.environ.get("RELAY_HOST", "localhost")
RELAY_PORT = int(os.environ.get("RELAY_PORT", "9100"))
TOPIC = "raw-quotes"

NORMAL_RATE = 10        # messages/sec (matches simulator default)
SPIKE_MULTIPLIER = 10   # 10x spike
NORMAL_DURATION = 5     # seconds at normal rate
SPIKE_DURATION = 5      # seconds at spike rate
COOLDOWN = 3            # seconds to drain after sending


def produce_messages(rate, duration, start_seq):
    """Produce numbered messages at a given rate. Returns (count_sent, next_seq)."""
    producer = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})
    interval = 1.0 / rate
    sent = 0
    seq = start_seq
    end_time = time.time() + duration

    while time.time() < end_time:
        msg = {
            "symbol": "AAPL",
            "price": 187.0,
            "volume": 100,
            "timestamp": time.time(),
            "seq": seq,
        }
        producer.produce(TOPIC, key="AAPL", value=json.dumps(msg))
        producer.poll(0)
        seq += 1
        sent += 1
        time.sleep(interval)

    producer.flush(timeout=10)
    return sent, seq


def tcp_consumer(host, port, received, stop_event, disconnect_at_seq=None):
    """Connect to relay, read messages, count them. Optionally disconnect/reconnect."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((host, port))
    sock.settimeout(1.0)
    buf = b""
    disconnected = False

    while not stop_event.is_set():
        try:
            data = sock.recv(4096)
            if not data:
                break
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                    if "seq" in msg:
                        received.append(msg["seq"])
                        # Disconnect/reconnect test
                        if disconnect_at_seq and not disconnected and msg["seq"] >= disconnect_at_seq:
                            print(f"  [consumer] Disconnecting at seq {msg['seq']}...")
                            sock.close()
                            time.sleep(0.5)
                            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                            sock.connect((host, port))
                            sock.settimeout(1.0)
                            buf = b""
                            disconnected = True
                            print(f"  [consumer] Reconnected.")
                except (json.JSONDecodeError, KeyError):
                    pass
        except socket.timeout:
            continue
        except (ConnectionResetError, BrokenPipeError, OSError):
            break

    try:
        sock.close()
    except OSError:
        pass


def run_test(label, normal_rate, spike_rate, spike_duration, disconnect_at_seq=None):
    print(f"\n--- {label} ---")
    received = []
    stop_event = threading.Event()

    # Start consumer
    consumer_thread = threading.Thread(
        target=tcp_consumer,
        args=(RELAY_HOST, RELAY_PORT, received, stop_event, disconnect_at_seq),
        daemon=True,
    )
    consumer_thread.start()
    time.sleep(0.5)  # let consumer connect

    total_sent = 0
    seq = 0

    # Phase 1: normal rate
    print(f"  Sending {NORMAL_DURATION}s at {normal_rate} msg/s...")
    sent, seq = produce_messages(normal_rate, NORMAL_DURATION, seq)
    total_sent += sent
    print(f"  Sent {sent} messages at normal rate.")

    # Phase 2: spike rate
    if spike_rate > 0:
        print(f"  Sending {spike_duration}s at {spike_rate} msg/s (10x spike)...")
        sent, seq = produce_messages(spike_rate, spike_duration, seq)
        total_sent += sent
        print(f"  Sent {sent} messages at spike rate.")

    # Cooldown
    print(f"  Draining for {COOLDOWN}s...")
    time.sleep(COOLDOWN)
    stop_event.set()
    consumer_thread.join(timeout=5)

    unique_received = sorted(set(received))
    lost = total_sent - len(unique_received)
    dupes = len(received) - len(unique_received)

    # Check ordering per-symbol (all AAPL here)
    in_order = all(received[i] <= received[i + 1] for i in range(len(received) - 1))

    print(f"  Sent:      {total_sent}")
    print(f"  Received:  {len(unique_received)} unique ({len(received)} total, {dupes} duplicates)")
    print(f"  Lost:      {lost} ({100.0 * lost / max(total_sent, 1):.1f}%)")
    print(f"  In order:  {'yes' if in_order else 'NO'}")

    return total_sent, len(unique_received), lost, in_order


def main():
    print("=== Kafka Pipeline Spike Test ===")
    print(f"Kafka:  {KAFKA_BOOTSTRAP}")
    print(f"Relay:  {RELAY_HOST}:{RELAY_PORT}")
    print(f"Topic:  {TOPIC}")

    # Test 1: Normal rate only (baseline)
    r1 = run_test("Test 1: Normal rate (baseline)",
                   NORMAL_RATE, 0, 0)

    # Test 2: Normal then 10x spike
    r2 = run_test("Test 2: Normal → 10x spike",
                   NORMAL_RATE, NORMAL_RATE * SPIKE_MULTIPLIER, SPIKE_DURATION)

    # Test 3: 10x spike with consumer disconnect/reconnect mid-stream
    total_normal = NORMAL_RATE * NORMAL_DURATION
    disconnect_seq = total_normal + (NORMAL_RATE * SPIKE_MULTIPLIER * SPIKE_DURATION) // 2
    r3 = run_test("Test 3: 10x spike + consumer disconnect/reconnect",
                   NORMAL_RATE, NORMAL_RATE * SPIKE_MULTIPLIER, SPIKE_DURATION,
                   disconnect_at_seq=disconnect_seq)

    print("\n=== Summary ===")
    print(f"{'Test':<50} {'Sent':>6} {'Recv':>6} {'Lost':>6} {'Order':>6}")
    for label, (sent, recv, lost, order) in [
        ("1: Normal rate", r1),
        ("2: Normal → 10x spike", r2),
        ("3: 10x spike + disconnect/reconnect", r3),
    ]:
        print(f"{label:<50} {sent:>6} {recv:>6} {lost:>6} {'yes' if order else 'NO':>6}")


if __name__ == "__main__":
    main()
