#!/usr/bin/env bash
. def.sh
. util.sh

tmp=`mktemp`
run_cmd fs -put $tmp $(basename $tmp)
run_cmd fs -lsr /

#run_cmd fs -cat /user/eli/output/part-r-00000
