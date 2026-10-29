#!/bin/bash
# Runs all cases against one plugin build.
# usage: matrix.sh <plugin.so|-> [first-port]
DIR=$(cd "$(dirname "$0")" && pwd)
LIB=$1 port=${2:-19000}
while read name lvl tier src; do
  port=$((port+1)); printf "%-44s " "$name"
  "$DIR/answerer.sh" "$LIB" $port $lvl $tier $src | paste -sd' '
done <<'EOT'
8Mbps(L4.0,main)_offer_L6.0/main_->_sends 180 0 8000
8Mbps(L4.0,main)_offer_L4.0/high_->_sends 120 1 8000
8Mbps(L4.0,main)_offer_L4.0/main_->_sends 120 0 8000
8Mbps(L4.0,main)_offer_L3.1/main_->_refuses 93 0 8000
30Mbps(L4.0,high)_offer_L4.0/high_->_sends 120 1 30000
30Mbps(L4.0,high)_offer_L4.0/main_->_refuses 120 0 30000
EOT
port=$((port+1)); printf "%-44s " "offerer_8Mbps_->_sends"; "$DIR/offerer.sh" "$LIB" $port 8000
