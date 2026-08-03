"""Minimal Flask API used to demonstrate container + CI security gates."""

from __future__ import annotations

import os

from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/healthz")
def healthz():
    return jsonify(status="ok"), 200


@app.get("/")
def root():
    return jsonify(
        service="portfolio-secure-cicd",
        message="Hardened sample app — see docs/CASE_STUDY.md",
    ), 200


def create_app() -> Flask:
    return app


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
