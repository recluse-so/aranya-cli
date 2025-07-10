#!/bin/bash


for i in {1..3}; do 
    mkdir -p /tmp/aranya$i/{run,state,cache,logs,config}
done

# Start 3 daemons using the 3 different config files
for i in {1..3}; do
    echo "Starting daemon $i..."
    ../../target/release/aranya-daemon --config config_daemon$i.json > /tmp/aranya$i/daemon.log 2>&1 &
    daemon_pid=$!
    echo "Daemon $i started with PID: $daemon_pid"
    
    # Store PID for later reference
    echo $daemon_pid > /tmp/aranya$i/daemon.pid
done

echo "All 3 daemons started!"

# wait for daemons to start
sleep 1