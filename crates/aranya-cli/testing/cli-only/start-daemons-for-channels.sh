#!/bin/bash

set -e

echo "Setting up daemon directories..."
for i in {1..3}; do 
    mkdir -p /tmp/aranya$i/{run,state,cache,logs,config}
done

# Start 3 daemons using the 3 different config files
for i in {1..3}; do
    echo "Starting daemon $i..."
    ../../../../target/release/aranya-daemon --config config_daemon$i.json > /tmp/aranya$i/daemon.log 2>&1 &
    daemon_pid=$!
    echo "Daemon $i started with PID: $daemon_pid"
    
    # Store PID for later reference
    echo $daemon_pid > /tmp/aranya$i/daemon.pid
    
    # Wait a bit for this daemon to start
    sleep 2
done

echo "All 3 daemons started!"

# Wait for daemons to fully initialize
echo "Waiting for daemons to initialize..."
sleep 5

# Verify daemons are running and have created their API keys
for i in {1..3}; do
    if [ ! -f "/tmp/aranya$i/run/api.pk" ]; then
        echo "ERROR: Daemon $i failed to create api.pk"
        echo "Daemon $i log:"
        tail -n 20 /tmp/aranya$i/daemon.log
        exit 1
    fi
    
    if [ ! -S "/tmp/aranya$i/run/uds.sock" ]; then
        echo "ERROR: Daemon $i failed to create UDS socket"
        exit 1
    fi
    
    echo "Daemon $i is ready (PID: $(cat /tmp/aranya$i/daemon.pid))"
done

echo "All daemons are ready!"