#!/usr/bin/env bash

# Initial user setup
# sudo groupadd hadoop
# sudo useradd hdfs -m -G hadoop -s /bin/bash
# sudo useradd mapred -m -G hadoop -s /bin/bash

function is_slave () {
    local dir=$1
    if [ "$dir" = "dir-s1" ] ||
       [ "$dir" = "dir-s2" ] ||
       [ "$dir" = "dir-s3" ]
    then
        echo 0
    else
        echo 1
    fi
}

#
# Unpack the tarball to the deployment dir and create 
# conf dirs for each pseudo "host".
#
function deploy_hadoop () {
    local user=$1
    # Create the deployment dir
    if [ -d "$DEPLOY_HOME" ]; then
        sudo rm -rf $DEPLOY_HOME
    fi
    sudo mkdir $DEPLOY_HOME
    sudo chown -R $user:$user $DEPLOY_HOME
    tar -xzf $HADOOP_TARBALL -C $DEPLOY_HOME
    # Create dirs and configs for each pseudo host
    idx=0
    for dir in dir-nn dir-2nn dir-jt dir-s1 dir-s2 dir-s3
    do
        dir_path=$DEPLOY_HOME/$dir
        mkdir $dir_path
        cp -r conf/$DISTRO $dir_path/conf
        sed -i "s/_ROOT_/\/deploy\/$dir/g" $dir_path/conf/*
        sed -i "s/_USER_/$user/g" $dir_path/conf/*
        sudo chown -R root:hadoop $dir_path/conf
        sudo chmod a+rx $dir_path/conf
        for d in bin tmp logs pids dfs
        do
            mkdir $dir_path/$d
            sudo chgrp -R hadoop $dir_path/$d
            sudo chmod g+w $dir_path/$d
        done
        # Make JT local dirs
        if [ $dir == "dir-jt" ]; then
            for i in 1 2; do
                d=local$i
                mkdir -p $dir_path/$d/mapred
                sudo chown mapred:hadoop $dir_path/$d/mapred
            done
        fi
        # Setup the TC on each slave
        r=`is_slave $dir`
        if [ $r == 0 ]; then
            sudo chown hdfs:hadoop $dir_path/dfs
            for i in 1 2
            do
                d=local$i
                img=$DEPLOY_HOME/md-image$idx
                md=/dev/md$idx
                lp=/dev/loop$idx
                idx=$(($idx+1))
                dd if=/dev/zero of=$img bs=1M count=1000
                sudo losetup -f $img
                sudo mdadm --create $md --level=faulty --raid-devices=1 $lp
                sudo mkfs.ext3 $md
                mkdir $dir_path/$d
                sudo mount $md $dir_path/$d
                sudo chown -R $user:$user $dir_path/$d
                mkdir $dir_path/$d/data
                mkdir $dir_path/$d/mapred
                sudo chown hdfs:hadoop $dir_path/$d/data
                sudo chown mapred:hadoop $dir_path/$d/mapred
            done

            cp tthealth.sh $dir_path/bin
            sudo chown mapred:hadoop $dir_path/bin/tthealth.sh

            # For 20x we need to build the tc for each host since the
            # config path is baked into the binary
            ttbin=""
            pushd $HADOOP_HOME
            if [ "$DISTRO" == "20x" ]; then
                ant task-controller -Dhadoop.conf.dir=$dir_path/conf \
                    -Doffline=true
                ttbin=bin/task-controller
                cp ./build/$HADOOP_VERSION/$ttbin $dir_path/$ttbin
            else
                ttbin=sbin/Linux-amd64-64/task-controller
                mkdir -p $dir_path/sbin/Linux-amd64-64
                sudo chgrp -R hadoop $dir_path/sbin
                sudo chmod -R g+w $dir_path/sbin
                cp $ttbin $dir_path/$ttbin
            fi
            popd
            sudo chown root:mapred $dir_path/$ttbin
            sudo chmod 6050 $dir_path/$ttbin
            sudo chown root:mapred $dir_path/conf/taskcontroller.cfg
            sudo chmod 0400 $dir_path/conf/taskcontroller.cfg
        fi
        sudo chown root:hadoop $dir_path
    done
    # Paths including and leading up to the directories listed
    # in mapred.local.dir and hadoop.log.dir need to be owned by 
    # root and have 755 perms.
    sudo chown root:hadoop $HADOOP_HOME
    sudo chown root:hadoop $DEPLOY_HOME
}

function list_mounts () {
    sudo losetup -a
    #sudo mdadm -E -s
    ls /dev/md*
}

#
# Tear down loopback mounts
#
function remove_mounts () {
    idx=0;
    for dir in dir-s1 dir-s2 dir-s3
    do
        dir_path=$DEPLOY_HOME/$dir
        for i in $(seq 1 2)
        do
            d=local$i
            md=/dev/md$idx
            lp=/dev/loop$idx
            idx=$(($idx+1))
            if [ -d $dir_path/$d ]; then
                sudo umount $dir_path/$d
            fi
            if [ -e $md ]; then
                sudo mdadm -S $md
                sudo mdadm --remove $md
            fi
            if [ -e $lp ]; then
                sudo losetup -d $lp
            fi
        done
    done
}

# Inject a failure in the given mount. Eg.
# wt{n} transient write failures (after n writes) 
# rt{n} transient read failures
# rp{n} persistent (for particular access) read failures 
function fail_mount () {
    local idx=$1
    local mode=$2
    sudo mdadm --grow /dev/md$idx -l faulty -p $mode
}

# Inject given failure into all mounts
function fail_all_mounts () {
    local count=$1
    local mode=$2
    for i in $(seq 0 $count); do
        fail_mount $i $mode
    done
}

# Clear all failures
function clear_mount_failures () {
    local count=$1
    for i in $(seq 0 $count); do
        sudo mdadm --grow /dev/md$i -l faulty -p clear
        sudo mdadm --grow /dev/md$i -l faulty -p flush
    done
}

#
# Run the given daemon using the given and command, out of the given
# directory with the given configuration dir. Restarts the daemon if
# it's already running.
#
function run_daemon () {
    local user=$1
    local cmd=$2
    local daemon=$3
    local dir=$4
    local conf=$DEPLOY_HOME/$dir/conf
    . $HADOOP_HOME/bin/hadoop-config.sh
    local pid_file=$DEPLOY_HOME/$dir/pids/hadoop-$user-$daemon.pid
    if [ -e $pid_file ] && [ "start" = "$cmd" ]; then
        pid=`cat $pid_file`
        if [ -e /proc/$pid ]; then
            echo $daemon already running
            run_daemon $user stop $daemon $dir
            while [ -e /proc/$pid ]; do
                echo wait for $daemon to stop
                sleep 1
            done
        fi
    fi
    sudo -u $user $HADOOP_HOME/bin/hadoop-daemon.sh --config $conf $cmd $daemon
}

#
# Run a hadoop command
#
function run_cmd () {
    local dir="dir-nn"
    HADOOP_CONF_DIR=$DEPLOY_HOME/$dir/conf $HADOOP_HOME/bin/hadoop $*
}

function run_hdfs_cmd () {
    local dir="dir-nn"
    HADOOP_CONF_DIR=$DEPLOY_HOME/$dir/conf sudo -E -u hdfs \
        $HADOOP_HOME/bin/hadoop $*
}

#
# Run the given command on all the daemons
#
function exec_hdfs () {
    local cmd=$1
    run_daemon hdfs $cmd namenode dir-nn
    run_daemon hdfs $cmd datanode dir-s1
    run_daemon hdfs $cmd datanode dir-s2
    run_daemon hdfs $cmd datanode dir-s3
}

function exec_mr () {
    local cmd=$1
    run_daemon mapred $cmd jobtracker dir-jt
    run_daemon mapred $cmd tasktracker dir-s1
    run_daemon mapred $cmd tasktracker dir-s2
    run_daemon mapred $cmd tasktracker dir-s3
}


