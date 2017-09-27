#!/bin/bash

set -eux

env

redis-server /etc/redis/redis.conf &

POD_TEMPLATE_HASH=`hostname | cut -d- -f 2`
POD_IP=`hostname -i`
LIST_IPS=`curl $APISERVER/api/v1/namespaces/$POD_NAMESPACE/pods --header "Authorization: Bearer $TOKEN" --insecure | jq " .items[] | select(.metadata.labels[\"pod-template-hash\"]==\"$POD_TEMPLATE_HASH\") | .status .podIP"`
LIST_IPS=`echo $LIST_IPS | sed 's/"//g'`
IS_CLUSTER_ON="false"

# ask all nodes to check cluster situation
for IP in $LIST_IPS; do
  if [ $IP != $POD_IP  ]; then
    NODE_NUM=`redis-cli -h $IP cluster nodes | wc -l`
    if [ $NODE_NUM -gt "1" ]; then
      IS_CLUSTER_ON="true"
    fi
  fi
done

if [ $IS_CLUSTER_ON == "true" ]; then
  NODE_IP_IN_CLUSTER=""
  FAIL_NODE=""
  BREAK_LOOP="false"
  # wait to make sure one node is failed
  while [ $BREAK_LOOP == "false" ]; do
    for IP in $LIST_IPS; do
      RET=`redis-cli -h $IP ping`
      if [ $RET == "PONG" ] && [ $IP != $POD_IP ]; then
        SLAVE_COUNT=`redis-cli -h $IP cluster nodes | grep 'slave ' | wc -l`
        MASTER_COUNT=`redis-cli -h $IP cluster nodes | grep 'master ' | wc -l`
        ALIVE_COUNT=`expr $SLAVE_COUNT + $MASTER_COUNT`
        if [ $ALIVE_COUNT -lt $REDIS_CLUSTER_COUNT ]; then
          NODE_IP_IN_CLUSTER="$IP"
          FAIL_NODE=`redis-cli -h $IP cluster nodes | grep fail | cut -d ' ' -f 1`
          BREAK_LOOP="true"
          break
        fi
        sleep 1
      fi
    done
  done
  # forget failed node
  for IP in $LIST_IPS; do
    RET=`redis-cli -h $IP ping`
    if [ $RET == "PONG" ] && [ $IP != $POD_IP ]; then
        redis-cli -h $IP cluster forget $FAIL_NODE
    fi
  done
  # keep finding a master that has no slaves
  BREAK_LOOP="false"
  while [ $BREAK_LOOP == "false" ]; do
    MASTER_NODES=`redis-cli -h $NODE_IP_IN_CLUSTER cluster nodes | grep 'master ' | cut -d ' ' -f 1`
    MASTER_OF_SLAVE_NODES=`redis-cli -h $NODE_IP_IN_CLUSTER cluster nodes | grep 'slave '| cut -d ' ' -f 4`
    for MASTER_ID in $MASTER_NODES; do
      HAS_SLAVE="false"
      for MASTER_OF_SLAVE_ID in $MASTER_OF_SLAVE_NODES; do
        if [ $MASTER_ID == $MASTER_OF_SLAVE_ID ]; then
          HAS_SLAVE="true"
        fi
      done
      # add myself as a slave to that master of no slaves
      if [ $HAS_SLAVE == "false" ]; then
        /redis-trib.rb add-node --slave --master-id $MASTER_ID $POD_IP:$REDIS_CLUSTER_PORT $NODE_IP_IN_CLUSTER:$REDIS_CLUSTER_PORT
        BREAK_LOOP="true"
        break
      fi
    done
  done
else
  NODE_NUM="0"
  # wait until all the nodes in the cluster are up
  while [ $NODE_NUM -lt $REDIS_CLUSTER_COUNT ]; do
    LIST_IPS=`curl $APISERVER/api/v1/namespaces/$POD_NAMESPACE/pods --header "Authorization: Bearer $TOKEN" --insecure | jq " .items[] | select(.metadata.labels[\"pod-template-hash\"]==\"$POD_TEMPLATE_HASH\") | .status .podIP"`
    NODE_NUM=`echo "$LIST_IPS" | sed -e 's/$/,/' -e '$s/,//' | wc -l`

    echo "waiting 5s"
    sleep 5
  done

  NODE_LIST=""
  LIST_IPS=`echo $LIST_IPS | sed 's/"//g'`
  CLUSTER_CREATE_NODE=""
  # concat node string
  for IP in $LIST_IPS; do
    NODE_LIST+=" $IP:$REDIS_CLUSTER_PORT"
    CLUSTER_CREATE_NODE="$IP"
  done
  # only 1 node will initialize the cluster
  if [ $CLUSTER_CREATE_NODE == $POD_IP ]; then
    echo "running as cluster initializer"
    /redis-trib.rb create --replicas $REDIS_CLUSTER_REPLICA $NODE_LIST
  fi
fi


tail -f /redis.log
