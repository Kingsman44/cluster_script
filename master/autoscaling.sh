CPU_UTILIZATION=0
MEM_UTILIZATION=0
LOWER_THRESHOLD_CNT=0
RESULT=0
NODES=()
CONNECTED_NODES=0

. config.sh

create_file() {
    if [ ! -f cluster/$1/$2 ]; then
        touch cluster/$1/$2
    fi
}

new_file() {
    if [ -f $1 ]; then
        rm -rf $1
    fi
    if [ ! -z $2 ]; then
        echo $2 > $1
    else
        touch $1
    fi
}

setup_cluster_config() {
    allnodes="$(kubectl get nodes)"
    while read p; do
        if [ ! -z "$p" ]; then
            # Check Connection
            echo "checking connection for node $p"
            if nc -dvzw1 $p 123 2>/dev/null; then
                echo "Connection Succeeded"
            else
                echo "Error: Unable to create connection for node $p"
                echo "Make sure worker script is running in su mode"
                echo "Script is exiting due to unable to connect cluster"
                exit
            fi
            #echo "connection succeded"
            mkdir -p cluster/$p
            new_file cluster/$p/current_ram
	    if [ -z "$(echo "$allnodes" | grep $p)" ]; then 
            	new_file cluster/$p/current_status disconnected
	    else
                new_file cluster/$p/current_status connected
	    fi
            new_file cluster/$p/current_cpu
            new_file cluster/$p/current_rtt 0
            create_file $p cpu
            create_file $p ram
            create_file $p rtt
            NODES+=("$p")
	    echo "${NODES[@]}"
            ./scripts/run.sh $p "$MASTER_NODE"
        fi
    done <worker.config
}

get_cpu_utilzation() {
    #echo "$MASTER_NODE"
    total_usage="$(kubectl top nodes | grep "$MASTER_NODE " | awk '{print $3}' | tr -d '%')"
    total_cpu=1
    for i in ${NODES[@]}; do
        if [ "$(cat cluster/$i/current_status)" != "connected" ]; then
            continue
        fi
        var="$(kubectl top node $i)"
        value="$(echo "$var" | grep "$i " | awk '{print $3}' | tr -d '%')"
        #echo "NODE: $i, CPU: $value"
        new_file cluster/$i/current_cpu $value
        echo $value > cluster/$i/cpu
        total_cpu=$(echo "scale=2 ; $total_cpu + 1" | bc)
        total_usage=$(echo "scale=2 ; $total_usage + $value" | bc)
    done
    CPU_UTILIZATION=$(echo "scale=2 ; $total_usage / $total_cpu" | bc )
    CPU_UTILIZATION=$(echo "($CPU_UTILIZATION+0.5)/1" | bc)
    echo "Current Mean CPU Utilzation of connected nodes: $CPU_UTILIZATION%"
}

print_status() {
    echo "================================================"
    echo " Name		| cpu 	| ram	|  status"
    echo "==============================================="
    for i in ${NODES[@]}; do
	echo "$i		| $(cat cluster/$i/current_cpu)	| $(cat cluster/$i/current_ram)	 | $(cat cluster/$i/current_status)  "
    done
    echo "==============================================="
}

get_mem_utilzation() {
    total_usage="$(kubectl top nodes | grep "$MASTER_NODE " | awk '{print $5}' | tr -d '%')"
    total_mem=1
    for i in ${NODES[@]}; do
        if [ "$(cat cluster/$i/current_status)" != "connected" ]; then
            continue
        fi
        var="$(kubectl top node $i)"
        value="$(echo "$var" | grep "$i " | awk '{print $5}' | tr -d '%')"
        new_file cluster/$i/current_ram $value
        echo $value > cluster/$i/ram
        #echo "NODE: $i, MEMORY: $value"
        total_mem=$(echo "scale=2 ; $total_cpu + 1" | bc)
        total_usage=$(echo "scale=2 ; $total_usage + $value" | bc)
    done
    MEM_UTILIZATION=$(echo "scale=2 ; $total_usage / $total_mem" | bc )
    MEM_UTILIZATION=$(echo "($MEM_UTILIZATION+0.5)/1" | bc)
    echo "Current Mean Memory Utilzation of connected nodes: $MEM_UTILIZATION%"
}

rtt_check() {
    for i in ${NODES[@]}; do
        if [ "$(cat cluster/$i/current_status)" != "connected" ]; then
            continue
        fi
        val="$(ping -c 1 $i | tail -1 | awk '{print $4}' | cut -d'=' -f2 | cut -d'/' -f1)"
        val=$(echo "($val * 100)/1" | bc)
        cnt=$(cat cluster/$i/current_rtt)
        if [ $val -ge $MAX_RTT ]; then
            cnt=$(echo "$cnt + 1" | bc)
        else
            cnt=0;
        fi
        if [ $cnt -ge  $RTT_CNT_THRESHOLD ]; then
            join_node
            if [ $RESULT -eq 1 ]; then
                leave_node $i
            fi
        fi
    done
}

setup_metrics_server() {
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl taint nodes --all node.kubernetes.io/disk-pressure-
    kubectl apply -f yaml/metrics-server.yaml
}

join_node() {
    MIN_RTT_VAL=10000
    SLAVE_NAME=""
    RESULT=0
    if [ ! -z "$1" ]; then
        ./scripts/run.sh $1 join
        new_file cluster/$1/current_status connected
        CONNECTED_NODES=$(echo "$CONNECTED_NODES + 1"| bc)
        RESULT=1
        return
    fi
    echo "Checking available Nodes"
    for i in ${NODES[@]}; do
        if [ "$(cat cluster/$i/current_status)" != "disconnected" ]; then
            continue
        fi
        val="$(ping -c 1 $i | tail -1 | awk '{print $4}' | cut -d'=' -f2 | cut -d'/' -f1)"
        val=$(echo "($val * 100)/1" | bc)
	echo "$i RTT:$val"
        if [ $val -lt $MIN_RTT_VAL ]; then
            MIN_RTT_VAL=$val
            SLAVE_NAME="$i"
            RESULT=1
        fi
    done
    if [ $RESULT -eq 1 ]; then
        ./scripts/run.sh $SLAVE_NAME join
        new_file cluster/$SLAVE_NAME/current_status connected
	echo "Connecting Node $SLAVE_NAME"
        CONNECTED_NODES=$(echo "$CONNECTED_NODES + 1"| bc)
    else
        echo "NO NODES HAD BEEN LEFT TO JOIN"
    fi
}

leave_node() {
    MIN_VAL=10000
    SLAVE_NAME=""
    RESULT=0
    if [ $CONNECTED_NODES -eq 0 ]; then
        return
    fi
    if [ ! -z "$1" ]; then
        ./scripts/run.sh $1 leave
        new_file cluster/$1/current_status disconnected
        CONNECTED_NODES=$(echo "$CONNECTED_NODES - 1"| bc)
        RESULT=1
        return
    fi
    for i in ${NODES[@]}; do
        if [ "$(cat cluster/$i/current_status)" != "connected" ]; then
            continue
        fi
        var="$(kubectl top node $i)"
        value_mem="$(echo "$var" | grep "$i " | awk '{print $2}' | tr -d '%')"
        value_cpu="$(echo "$var" | grep "$i " | awk '{print $3}' | tr -d '%')"
        val=$(echo "$value_cpu + $value_mem" | bc)
        if [ $val -lt $MIN_VAL ]; then
            MIN_VAL=$val
            SLAVE_NAME="$i"
            RESULT=1
        fi
    done
    if [ $RESULT -eq 1 ]; then
        ./scripts/run.sh $SLAVE_NAME leave
        new_file cluster/$SLAVE_NAME/current_status disconnected
        CONNECTED_NODES=$(echo "$CONNECTED_NODES - 1"| bc)
    else
        echo "NO NODES HAD BEEN LEAVED"
    fi
}


echo "=================="
echo "Hybrid Autoscaling"
echo "=================="
if [ -z "$(cat worker.config)" ]; then
    echo "Please Set worker nodes in worker.config"
    exit
fi
if [ ! -f worker.config ]; then
    echo "Error: Worker Config not found, please create one"
    exit
fi
echo "getting clusters from worker.config"
cat worker.config
echo "================="
echo "creating cluster config"
mkdir -p cluster
setup_cluster_config
echo "================="
NODES1=$(ls cluster)
echo "Setting up Kubernetes on nodes"
for node in $NODES1; do
    ./scripts/run.sh $node setup
done
echo "================"
rm -rf hpa.yaml
echo "apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: $DEPLOYMENT_NAME
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $DEPLOYMENT_NAME
  minReplicas: $minReplicas
  maxReplicas: $maxReplicas
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: $targetCPUUtilization
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: $targetRAMUtilization" >> hpa.yaml
#cp yaml/hpa.yaml hpa.yaml
#DEPLOYMENT_NAME=$1
#if [ -z "$DEPLOYMENT_NAME" ]; then
#    echo "Deployment name is empty, exiting..."
#    exit
#fi
#sed -i -e "s/hpa-demo-deployment/$DEPLOYMENT_NAME/g" hpa.yaml
# shift
# PARAMETERS=$@
# for parameter in $PARAMETERS; do
#     #echo $parameter
#     if [ "$(echo $parameter | grep minReplicas)" ]; then
#         value=$(echo $parameter | cut -d= -f2 | tr -dc '0-9')
#         if [ -z $value ]; then
#             echo "Empty or unknown value minReplicas, using default 1"
#             continue
#         fi
#         echo "setting minReplicas to $value"
#         sed -i -e "s/minReplicas: 1/minReplicas: $minReplicas/g" hpa.yaml
#         elif [ "$(echo $parameter | grep maxReplicas)" ]; then
#         value=$(echo $parameter | cut -d= -f2 | tr -dc '0-9')
#         if [ -z $value ]; then
#             echo "Empty or unknown value maxReplicas, using default 10"
#             continue
#         fi
#         echo "setting maxReplicas to $value"
#         sed -i -e "s/maxReplicas: 10/maxReplicas: $value/g" hpa.yaml
#         elif [ "$(echo $parameter | grep CPUUtilization)" ]; then
#         value=$(echo $parameter | cut -d= -f2 | tr -dc '0-9')
#         if [ -z $value ]; then
#             echo "Empty or unknown value for targetCPUUtilizationPercentage, using default 50%"
#             continue
#         fi
#         echo "setting targetCPUUtilizationPercentage to $value"
#         sed -i -e "s/targetCPUUtilizationPercentage: 50/targetCPUUtilizationPercentage: $value/g" hpa.yaml
#     fi
# done
echo "==================="
#targetCPUUtilizationPercentage:
cat hpa.yaml
echo "=================="
echo "deploying HPA Autoscaling"
kubectl delete -f hpa.yaml
kubectl create -f hpa.yaml
echo "================="
echo "Starting Cluster Autoscaling"
while true; do
    #echo "Connected Nodes: master ${CONNECTED_NODES[*]}"
    #echo "Disconnected Nodes: ${DISCONNECTED_NODES[*]}"
    #echo "${NODES[@]}"
    get_cpu_utilzation
    get_mem_utilzation
    print_status
    if [ $CPU_UTILIZATION -ge $TARGET_CLUSTER_MEAN_CPU_UTILIZATION ]; then
        join_node
	sleep 30
        elif [ $MEM_UTILIZATION -ge $TARGET_CLUSTER_MEAN_MEM_UTILIZATION ]; then
        join_node
	sleep 30
    fi
    if [ $MEM_UTILIZATION -le $LOWER_THRESHOLD ] && [ $CPU_UTILIZATION -le $LOWER_THRESHOLD ]; then
        if [ $LOWER_THRESHOLD_CNT -le $TARGET_LOWER_THRESHOLD ]; then
            LOWER_THRESHOLD_CNT=$(echo "$LOWER_THRESHOLD_CNT + 1" | bc)
        else
            leave_node
            LOWER_THRESHOLD_CNT=0
        fi
    else
        LOWER_THRESHOLD_CNT=0
    fi
    rtt_check
    sleep 5
done
