#!/usr/bin/env sh

NODE_ID=${ID:-0}
CLUSTER_SIZE=${CLUSTER_SIZE:-1}


# Clean up and env set up
export GOPATH=$HOME/go
export GOBIN=$GOPATH/bin
export BUILD_PATH=/sei-protocol/sei-chain/build
export PATH=$GOBIN:$PATH:/usr/local/go/bin:$BUILD_PATH
echo "export GOPATH=$HOME/go" >> /root/.bashrc
echo "GOBIN=$GOPATH/bin" >> /root/.bashrc
echo "export PATH=$GOBIN:$PATH:/usr/local/go/bin:$BUILD_PATH" >> /root/.bashrc
/bin/bash -c "source /root/.bashrc"

# Step 1: Run init on all nodes
/usr/bin/configure_init.sh

# Step 4: Configure persistent peers
/usr/bin/persistent_peers.sh

# Step 5: Start the chain
/usr/bin/start_sei.sh

# Wait until the chain started
while [ $(cat build/generated/launch.complete |wc -l) -lt "$CLUSTER_SIZE" ]
do
  sleep 1
done
sleep 5
echo "All $CLUSTER_SIZE Nodes started successfully, starting oracle price feeder..."

# Step 6: Start oracle price feeder
/usr/bin/start_price_feeder.sh
echo "Oracle price feeder is started"

tail -f /dev/null