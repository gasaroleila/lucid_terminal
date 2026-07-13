import json
import os
import signal
import time
from typing import TypedDict

from confluent_kafka import Producer
from langchain_groq import ChatGroq
from langgraph.graph import StateGraph, END
from newsapi import NewsApiClient

GROQ_API_KEY = os.environ["GROQ_API_KEY"]
NEWS_API_KEY = os.environ["NEWS_API_KEY"]
KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "kafka:9092")
SYMBOLS = os.environ.get("SYMBOLS", "AAPL,MSFT,GOOGL,AMZN,TSLA").split(",")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "900"))  # 15 min default
TOPIC = "sentiment"

FINANCIAL_SOURCES = ",".join([
    "bloomberg", "reuters", "the-wall-street-journal", "financial-times",
    "business-insider", "cnbc", "fortune", "the-verge", "techcrunch",
    "ars-technica", "wired",
])

newsapi = NewsApiClient(api_key=NEWS_API_KEY)
producer = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})
llm = ChatGroq(model="openai/gpt-oss-20b", temperature=0, api_key=GROQ_API_KEY)
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


# -- LangGraph pipeline --

SYMBOL_NAMES = {
    "AAPL": "Apple", "MSFT": "Microsoft", "GOOGL": "Google/Alphabet",
    "AMZN": "Amazon", "TSLA": "Tesla", "NVDA": "NVIDIA", "META": "Meta",
}


class SentimentState(TypedDict):
    headline: str
    symbol: str
    relevant: bool
    score: float
    reasoning: str


def classify_relevance(state: SentimentState) -> SentimentState:
    company = SYMBOL_NAMES.get(state["symbol"], state["symbol"])
    prompt = (
        f'Is this headline about the publicly traded company {company} ({state["symbol"]}) '
        f'in a financial context? Answer ONLY "yes" or "no".\n\n'
        f'Headline: {state["headline"]}'
    )
    response = llm.invoke(prompt)
    relevant = response.content.strip().lower().startswith("yes")
    return {**state, "relevant": relevant}


def score_headline(state: SentimentState) -> SentimentState:
    prompt = (
        f"Analyze this financial news headline for {state['symbol']}. "
        f"Return ONLY a JSON object with two fields: "
        f'"score" (float from -1.0 bearish to 1.0 bullish) and '
        f'"reasoning" (one sentence).\n\n'
        f"Headline: {state['headline']}"
    )
    response = llm.invoke(prompt)
    try:
        data = json.loads(response.content)
        return {**state, "score": float(data["score"]), "reasoning": data["reasoning"]}
    except (json.JSONDecodeError, KeyError):
        return {**state, "score": 0.0, "reasoning": "Failed to parse LLM response"}


def route_after_classify(state: SentimentState) -> str:
    return "score" if state["relevant"] else END


graph = StateGraph(SentimentState)
graph.add_node("classify", classify_relevance)
graph.add_node("score", score_headline)
graph.set_entry_point("classify")
graph.add_conditional_edges("classify", route_after_classify, {"score": "score", END: END})
graph.add_edge("score", END)
pipeline = graph.compile()


# -- Main loop --

def fetch_and_score():
    # Search for our symbols specifically, restricted to financial sources
    query = " OR ".join(f'"{SYMBOL_NAMES.get(s, s)}"' for s in SYMBOLS)
    try:
        response = newsapi.get_everything(
            q=query,
            language="en",
            sort_by="publishedAt",
            domains="bloomberg.com,reuters.com,wsj.com,cnbc.com,ft.com,businessinsider.com,fortune.com,marketwatch.com,seekingalpha.com,barrons.com",
            page_size=20,
        )
    except Exception as e:
        print(f"NewsAPI error: {e}")
        return

    articles = response.get("articles", [])
    print(f"Fetched {len(articles)} financial headlines")

    scored = 0
    skipped = 0

    for article in articles:
        headline = article.get("title", "")
        if not headline:
            continue

        # match headline to a symbol
        matched_symbol = None
        for sym in SYMBOLS:
            company = SYMBOL_NAMES.get(sym, sym)
            if sym.lower() in headline.lower() or company.lower() in headline.lower():
                matched_symbol = sym
                break
        if not matched_symbol:
            continue  # skip headlines that don't mention any of our symbols

        result = pipeline.invoke({
            "headline": headline,
            "symbol": matched_symbol,
            "relevant": False,
            "score": 0.0,
            "reasoning": "",
        })

        if not result["relevant"]:
            skipped += 1
            print(f"  [SKIP] {matched_symbol}: {headline[:60]}...")
            continue

        msg = {
            "symbol": result["symbol"],
            "headline": headline,
            "score": result["score"],
            "reasoning": result["reasoning"],
            "source": article.get("source", {}).get("name", ""),
            "url": article.get("url", ""),
            "timestamp": time.time(),
        }

        producer.produce(
            TOPIC,
            key=result["symbol"],
            value=json.dumps(msg),
            callback=delivery_report,
        )
        scored += 1
        print(f"  [{result['score']:+.2f}] {result['symbol']}: {headline[:60]}...")

    producer.flush(timeout=5)
    print(f"Scored {scored}, skipped {skipped} irrelevant")


if __name__ == "__main__":
    print(f"Sentiment service started: {len(SYMBOLS)} symbols, polling every {POLL_INTERVAL}s")

    # Run immediately on startup
    fetch_and_score()

    while running:
        print(f"Next poll in {POLL_INTERVAL}s...")
        for _ in range(POLL_INTERVAL):
            if not running:
                break
            time.sleep(1)
        if running:
            fetch_and_score()

    producer.flush(timeout=5)
    print("Shutdown complete.")
