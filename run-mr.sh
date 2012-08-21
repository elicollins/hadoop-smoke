#!/usr/bin/env bash
. def.sh
. util.sh

J=$HADOOP_HOME/hadoop-examples-*.jar

if [ 1 -eq 1 ]; then
    run_cmd fs -rmr /user/$USER/PiEstimator*
    run_cmd jar $J pi -Dmapred.map.tasks=3 2 10
fi

while (true); do

if [ 1 -eq 1 ]; then
    run_cmd fs -rmr /user/$USER/output
    run_cmd fs -rmr /user/$USER/input
    run_cmd fs -mkdir /user/$USER/input
    for i in {0..9} ; do
        run_cmd fs -put data/rfc1813.txt /user/$USER/input/rfc1813.txt.$i
    done
    run_cmd jar $J wordcount -files data/rfc1813.txt input output
fi

done
