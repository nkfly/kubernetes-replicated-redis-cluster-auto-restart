# kubernetes-replicated-redis-cluster-auto-restart
Redis cluster with auto-restart and auto-recovery on top of Kubernetes

### Table of Contents

* [Goal](#goal)
* [Test](#test)
* [High-level-explanation-of-docker-entrypoint](#high-level-explanation-of-docker-entrypoint)
* [Production-deployment](#production-deployment)

## Goal

* Given the total node number and replica number of redis cluster, deploy a redis cluster on Kubernetes

* When a node in redis cluster fails, the auto-restarted node will join the redis cluster and keep the service intact

* Provide a fault-tolerant, auto-restart and auto-recovery redis cluster service

## Test

### Pre-requisites

* Having docker(https://www.docker.com/) installed

* Having minikube(https://github.com/kubernetes/minikube) installed

### Steps

* Start minikube and make minikube work with docker daemon

```
minikube start && eval $(minikube docker-env)
```

* Starting from the root of this repository, build the local Docker image

```
cd image
docker build -t local:kubernetes-replicated-redis-cluster-auto-restart .
```

* Get Kubernetes api server and token. Please follow https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/#without-kubectl-proxy-post-v13x . The following command should return json response

```
curl $APISERVER/api --header "Authorization: Bearer $TOKEN" --insecure
```

* Put the api server and token values into APISERVER and TOKEN in deployment.yaml, respectivaly

* Deploy

```
kubectl create -f deployment.yaml
```

* Go to minikube dashboard and check pods

```
minikube dashboard
```

* Bash into one of the pods to check redis cluster, the pod name can be checked from minikube dashboard pods section

```
kubectl exec -ti $POD_NAME bash
```

```
# inside pod
redis-cli cluster nodes
```

You should see something like
```
35958c8f1bf80830d5458a71cfc579c6dc2a88ac 172.17.0.9:6379@16379 master - 0 1506368720900 1 connected 0-5460
4924469dc38c2e00e86b221abb840d9f5ec979bb 172.17.0.10:6379@16379 master - 0 1506368719000 2 connected 5461-10922
ccdba9b4f8f99dbfdbc16177ad3b636ac87be524 172.17.0.12:6379@16379 slave 15de8ecbf875f86ae2a83f1e6fba97e6fcc42c7a 0 1506368720000 7 connected
15de8ecbf875f86ae2a83f1e6fba97e6fcc42c7a 172.17.0.5:6379@16379 master - 0 1506368718888 7 connected 10923-16383
1229970448ed494b345622fb5caf98f8e1d33b96 172.17.0.7:6379@16379 slave 35958c8f1bf80830d5458a71cfc579c6dc2a88ac 0 1506368719893 4 connected
c5b6c70c4cde89584d00a603014333627f54facf 172.17.0.11:6379@16379 myself,slave 4924469dc38c2e00e86b221abb840d9f5ec979bb 0 1506368719000 5 connected
```
* Manually kill one pod from minikube dashboard, to test the auto-restart and auto-recovery

* Wait for some time and bash into one of the pods again, the redis cluster should still have correct masters and slaves

## High-level-explanation-of-docker-entrypoint

* Use pod-template-hash, api server and redis-cli to differentiate whether there is already a cluster running or not. When the api server returns the pods given pod-template-hash, a redis-cli request to other pods is made to count cluster nodes. The number of cluster nodes will determine $IS_CLUSTER_ON

* The pod-template-hash is also used to differentiate a new deployment. In a new deployment, the cluster is considered to be not yet running

### Initialize the cluster

* When the cluster is considered to be not yet running, $IS_CLUSTER_ON = false

* Waiting until all the pods are ready by asking api server, only 1 pod will initialize the whole cluster using redis-trib.rb

### When a pod fails, the auto-restarted pod will join the cluster

* When the cluster is considered to be running, $IS_CLUSTER_ON = true

* Wait and check to make sure one pod is failed

* Tell all other alive pods in the cluster to forget that failed node

* Keep finding a master that has no slaves. The reason why we are sure that there will be 1 master that has no slaves is that redis cluster will promote slave to master if a master dies

* Join the cluster as a slave to that master of no slaves

## Production-deployment

There are something that may be changed in a Production environment

* The image and imagePullPolicy should be changed

* The way to get pod-template-hash in docker-entrypoint.sh may be changed

* The way to call api server may be changed, so the POD_NAMESPACE, APISERVER, TOKEN or even the command in docker-entrypoint.sh may be changed

* redis.conf in the image may be changed
