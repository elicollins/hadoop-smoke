#!/bin/bash
if ! jps | grep -q DataNode ; then
 echo ERROR: datanode not up
fi
