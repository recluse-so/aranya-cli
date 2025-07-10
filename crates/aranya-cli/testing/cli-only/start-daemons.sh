#!/bin/bash


for i in {1..5}; do 
    mkdir -p /tmp/aranya$i/{run,state,cache,logs,config}
done

# Start 5 daemons using the 5 different config files
for i in {1..5}; do
    echo "Starting daemon $i..."
    ../../../../target/release/aranya-daemon --config config_daemon$i.json > /tmp/aranya$i/daemon.log 2>&1 &
    daemon_pid=$!
    echo "Daemon $i started with PID: $daemon_pid"
    
    # Store PID for later reference
    echo $daemon_pid > /tmp/aranya$i/daemon.pid
done

echo "All daemons started!"

# wait for daemons to start
sleep 1