#!/bin/bash
day=`date +%Y%m%d`
nohup /opt/ibga/monitor_ibg.sh > monitor_$day.log 2>&1 &
exec /opt/ibga/manager.sh 2>&1 | tee -a $IBGA_LOG_EXPORT_DIR/docker_$day.log
