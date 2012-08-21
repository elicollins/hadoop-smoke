#!/usr/bin/env bash
set -e
set -x

. def.sh
. util.sh

# Build the tarball
if [ 1 -eq 1 ]; then
pushd $HADOOP_SRC
if [ "$DISTRO" == "cdh3" ]; then
    ant task-controller -Doffline=true
fi
ant tar -Djava5.home=$JAVA5_HOME -Dforrest.home=$FORREST_HOME -Doffline=true
popd
fi

# Create and deploy hadoop configuration
deploy_hadoop $USER
