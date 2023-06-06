#!/usr/bin/env sh

# checkout write tag
git clone https://github.com/sei-protocol/sei-chain /sei-protocol/sei-chain &
pid=$!

while [ -d "/proc/$pid" ]; do
    echo "Waiting for git clone to finish..."
    sleep 1
done
