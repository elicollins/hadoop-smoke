#!/usr/bin/env bash

. def.sh
. util.sh

# Initialize and start the file system
run_hdfs_cmd namenode -format

exec_hdfs start

run_hdfs_cmd dfsadmin -safemode leave

run_hdfs_cmd fs -chown hdfs:hadoop /

run_hdfs_cmd fs -mkdir /user/$USER
run_hdfs_cmd fs -chmod 755 /user/$USER
run_hdfs_cmd fs -chown $USER:$USER /user/$USER

run_hdfs_cmd fs -mkdir /tmp
run_hdfs_cmd fs -chmod 777 /tmp

run_hdfs_cmd fs -mkdir /mapred/system
run_hdfs_cmd fs -chmod 755 /mapred/system
run_hdfs_cmd fs -chown -R mapred:hadoop /mapred

# Create a file as a normal user
tmp=`mktemp`
run_cmd fs -put $tmp $(basename $tmp)
run_cmd fs -lsr /
