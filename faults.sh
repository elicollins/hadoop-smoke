#!/usr/bin/env bash
set -x

. def.sh
. util.sh

#list_mounts
#remove_mounts
#exit

# 01 23 45

fail_mount 0 rt2
fail_mount 1 rt2
#fail_mount 4 rp0

fail_all_mounts 5 rp1
#clear_mount_failures 5

