#!/usr/bin/env sh

git clone https://github.com/sei-protocol/sei-chain --depth=1 /sei-protocol/sei-chain &
pid=$!

while [ -d "/proc/$pid" ]; do
    echo "Waiting for git clone to finish..."
    sleep 1
done