#!/bin/bash
nohup /opt/ibga/monitor_ibg.sh > monitor_ibg.log 2>&1 &
exec /opt/ibga/manager.sh 2>&1 | tee -a $IBGA_LOG_EXPORT_DIR/docker.log
