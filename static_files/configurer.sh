#!/usr/bin/env sh

NODE_ID=${ID:-0}
CLUSTER_SIZE=${CLUSTER_SIZE:-1}

export ID=${ID:-0}
export CLUSTER_SIZE=${CLUSTER_SIZE:-4}

# Clean up and env set up
export GOPATH=$HOME/go
export GOBIN=$GOPATH/bin
export BUILD_PATH=/sei-protocol/sei-chain/build
export PATH=$GOBIN:$PATH:/usr/local/go/bin:$BUILD_PATH
echo "export GOPATH=$HOME/go" >> /root/.bashrc
echo "GOBIN=$GOPATH/bin" >> /root/.bashrc
echo "export PATH=$GOBIN:$PATH:/usr/local/go/bin:$BUILD_PATH" >> /root/.bashrc
/bin/bash -c "source /root/.bashrc"

ID=${ID} NUM_ACCOUNTS=10 /usr/bin/configure_init.sh