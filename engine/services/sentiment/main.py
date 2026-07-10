"""
Sentiment Analysis Service — Weekend 4 starter.

Uses LangGraph to analyze news headlines and produce sentiment scores.
Publishes results to Kafka for the OCaml engine to consume.

Prerequisites:
    pip install langgraph langchain-openai confluent-kafka grpcio grpcio-tools

Architecture:
    [News Feed] → [LangGraph Pipeline] → [Kafka: sentiment-scores]
                                       → [gRPC Server for direct queries]
"""

import json
import time
import os
from concurrent import futures

# -- LangGraph imports (install: pip install langgraph langchain-openai) --
# from langgraph.graph import StateGraph, END
# from langchain_openai import ChatOpenAI

# -- Kafka (install: pip install confluent-kafka) --
# from confluent_kafka import Producer

# -- gRPC (install: pip install grpcio grpcio-tools) --
# import grpc
# from generated import sentiment_pb2, sentiment_pb2_grpc  # After protoc


# ═══════════════════════════════════════════════════════════════
#  STEP 1: Define the LangGraph sentiment pipeline
# ═══════════════════════════════════════════════════════════════

# Uncomment and fill in when you reach Weekend 4:

# class SentimentState:
#     """State that flows through the LangGraph pipeline."""
#     headline: str = ""
#     symbol: str = ""
#     sentiment_score: float = 0.0  # -1.0 (bearish) to 1.0 (bullish)
#     reasoning: str = ""
#
#
# def analyze_headline(state: SentimentState) -> SentimentState:
#     """Use an LLM to analyze sentiment of a news headline."""
#     llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)
#     prompt = f"""
#     Analyze the sentiment of this financial news headline for {state.symbol}.
#     Return a JSON object with:
#     - score: float from -1.0 (very bearish) to 1.0 (very bullish)
#     - reasoning: brief explanation
#
#     Headline: {state.headline}
#     """
#     response = llm.invoke(prompt)
#     data = json.loads(response.content)
#     state.sentiment_score = data["score"]
#     state.reasoning = data["reasoning"]
#     return state
#
#
# def build_pipeline():
#     """Build the LangGraph pipeline."""
#     graph = StateGraph(SentimentState)
#     graph.add_node("analyze", analyze_headline)
#     graph.set_entry_point("analyze")
#     graph.add_edge("analyze", END)
#     return graph.compile()


# ═══════════════════════════════════════════════════════════════
#  STEP 2: Kafka producer (publishes sentiment scores)
# ═══════════════════════════════════════════════════════════════

# def create_kafka_producer():
#     """Create a Kafka producer for publishing sentiment scores."""
#     conf = {
#         "bootstrap.servers": os.getenv("KAFKA_BOOTSTRAP", "localhost:9092"),
#         "client.id": "sentiment-producer",
#     }
#     return Producer(conf)
#
#
# def publish_sentiment(producer, symbol, score, reasoning):
#     """Publish a sentiment score to Kafka."""
#     message = {
#         "symbol": symbol,
#         "score": score,
#         "reasoning": reasoning,
#         "timestamp": time.time(),
#     }
#     producer.produce(
#         "sentiment-scores",
#         key=symbol.encode(),
#         value=json.dumps(message).encode(),
#     )
#     producer.flush()


# ═══════════════════════════════════════════════════════════════
#  STEP 3: gRPC server (for direct queries from OCaml engine)
# ═══════════════════════════════════════════════════════════════

# Define your protobuf schema in sentiment.proto:
#
# syntax = "proto3";
# service SentimentService {
#   rpc GetSentiment (SentimentRequest) returns (SentimentResponse);
#   rpc StreamSentiment (SentimentRequest) returns (stream SentimentResponse);
# }
# message SentimentRequest { string symbol = 1; }
# message SentimentResponse {
#   string symbol = 1;
#   float score = 2;
#   string reasoning = 3;
#   double timestamp = 4;
# }
#
# Generate with: python -m grpc_tools.protoc -I. --python_out=generated --grpc_python_out=generated sentiment.proto


# ═══════════════════════════════════════════════════════════════
#  Minimal working version (no external deps, for testing)
# ═══════════════════════════════════════════════════════════════

def simple_sentiment(headline: str) -> float:
    """Dead-simple keyword-based sentiment for testing without an LLM.
    Replace this with the LangGraph pipeline when ready."""
    positive = ["surge", "rally", "beat", "growth", "profit", "bullish", "up", "gain", "record"]
    negative = ["crash", "drop", "loss", "bearish", "down", "miss", "decline", "fear", "sell"]

    headline_lower = headline.lower()
    pos_count = sum(1 for w in positive if w in headline_lower)
    neg_count = sum(1 for w in negative if w in headline_lower)

    total = pos_count + neg_count
    if total == 0:
        return 0.0
    return (pos_count - neg_count) / total


if __name__ == "__main__":
    # Quick test
    test_headlines = [
        ("AAPL", "Apple reports record quarterly profit, stock surges"),
        ("GOOG", "Google faces antitrust fears, stock drops in pre-market"),
        ("ETH", "Ethereum network upgrade goes smoothly"),
        ("AAPL", "Apple warns of supply chain issues, misses revenue target"),
    ]

    print("Sentiment Analysis (simple keyword-based)")
    print("=" * 50)
    for symbol, headline in test_headlines:
        score = simple_sentiment(headline)
        label = "BULLISH" if score > 0.2 else "BEARISH" if score < -0.2 else "NEUTRAL"
        print(f"  [{label:>7}] {score:+.2f}  {symbol}: {headline}")
