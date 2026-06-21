#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

if [ ! -d ".venv" ]; then
  echo "Creating virtual environment..."
  python3 -m venv .venv
fi

source .venv/bin/activate

echo "Installing / updating dependencies..."
pip install -q -r requirements.txt

echo "Starting BoardGameSnap..."
streamlit run app.py --server.headless true
