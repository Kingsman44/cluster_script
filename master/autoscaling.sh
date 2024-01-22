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

get_utilzation() {
    #echo "$MASTER_NODE"
    total_usage_cpu="$(kubectl top nodes | grep "$MASTER_NODE " | awk '{print $3}' | tr -d '%')"
    total_usage_ram="$(kubectl top nodes | grep "$MASTER_NODE " | awk '{print $5}' | tr -d '%')"
    total_rtt=0
    total_nodes=1
    for i in ${NODES[@]}; do
        if [ "$(cat cluster/$i/current_status)" != "connected" ]; then
            continue
        fi
        var="$(kubectl top node $i)"
        value_cpu="$(echo "$var" | grep "$i " | awk '{print $3}' | tr -d '%')"
        value_ram="$(echo "$var" | grep "$i " | awk '{print $5}' | tr -d '%')"
        value_rtt="$(ping -c 1 $i | tail -1 | awk '{print $4}' | cut -d'=' -f2 | cut -d'/' -f1)"
        #echo "NODE: $i, CPU: $value"
        new_file cluster/$i/current_cpu $value_cpu
        new_file cluster/$i/current_ram $value_ram
        echo $value_cpu > cluster/$i/cpu
        echo $value_ram > cluster/$i/ram
        total_nodes=$(echo "scale=2 ; $total_nodes + 1" | bc)
        total_usage_cpu=$(echo "scale=2 ; $total_usage_cpu + $value_cpu" | bc)
        total_usage_ram=$(echo "scale=2 ; $total_usage_ram + $value_ram" | bc)
        total_rtt=$(echo "scale=2 ; $total_rtt + $value_rtt" | bc)
    done
    CPU_UTILIZATION=$(echo "scale=2 ; $total_usage_cpu / $total_nodes" | bc )
    CPU_UTILIZATION=$(echo "($CPU_UTILIZATION+0.5)/1" | bc)
    MEM_UTILIZATION=$(echo "scale=2 ; $total_usage_ram / $total_nodes" | bc )
    MEM_UTILIZATION=$(echo "($MEM_UTILIZATION+0.5)/1" | bc)
    if [ $total_nodes -gt 1 ]; then
    	AVG_RTT=$(echo "scale=2 ; $total_rtt / ( $total_nodes - 1 )" | bc)
    else
	AVG_RTT="$(ping -c 1 localhost | tail -1 | awk '{print $4}' | cut -d'=' -f2 | cut -d'/' -f1)"
    fi
    echo "Average RTT $AVG_RTT"
    echo "Current Mean CPU Utilzation of connected nodes: $CPU_UTILIZATION%"
    echo "Current Mean MEMORY Utilzation of connected nodes: $MEM_UTILIZATION%"
    cpu_x="$(tail -n 4 cluster/cpu_5.txt | awk 'NF')"
    ram_x="$(tail -n 4 cluster/ram_5.txt | awk 'NF')"
    rtt_x="$(tail -n 4 cluster/rtt_5.txt | awk 'NF')"
    rm -rf cluster/*.txt
    #echo "CPU_X: $cpu_x"
    echo "$cpu_x" > cluster/cpu_5.txt
    echo "$CPU_UTILIZATION" >> cluster/cpu_5.txt
    echo "$ram_x" > cluster/ram_5.txt
    echo "$MEM_UTILIZATION" >> cluster/ram_5.txt
    echo "$rtt_x" > cluster/rtt_5.txt
    echo "$AVG_RTT" >> cluster/rtt_5.txt
    #awk 'NF' cluster/rtt_5.txt > cluster/rtt_5.txt
    #awk 'NF' cluster/ram_5.txt > cluster/ram_5.txt
    #awk 'NF' cluster/cpu_5.txt > cluster/cpu_5.txt

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
	echo "Waiting $1 to get ready"
        while 1>0; do
                if [ ! -z "$(kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | grep $SLAVE_NAME)" ]; then
                        break;
                fi 
                sleep 2;
        done
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
	echo "Waiting for Node $SLAVE_NAME to get ready"
        CONNECTED_NODES=$(echo "$CONNECTED_NODES + 1"| bc)
	while 1>0; do
		if [ ! -z "$(kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | grep $SLAVE_NAME)" ]; then
			break;
		fi 
		sleep 2;
	done
	RESULT=1
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
new_file cluster/cpu_5.txt
new_file cluster/ram_5.txt
new_file cluster/rtt_5.txt
setup_cluster_config
echo "================="
NODES1=$(ls cluster | grep -v txt)
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
sleep_value=5
while true; do
    #echo "Connected Nodes: master ${CONNECTED_NODES[*]}"
    #echo "Disconnected Nodes: ${DISCONNECTED_NODES[*]}"
    #echo "${NODES[@]}"
    get_utilzation
    sleep_value=5
    if [ $(wc -l < cluster/cpu_5.txt) -eq 5 ]; then
        python3 model.py
        CPU_UTILIZATION=$(cat cluster/pred_cpu.txt)
        MEM_UTILIZATION=$(cat cluster/pred_ram.txt)
        echo "PREDICTED AVG CPU UTILIZATION: $CPU_UTILIZATION"
        echo "PREDICTED AVG MEMORY UTILIZATION: $MEM_UTILIZATION"
        sleep_value=2
    fi
    #get_mem_utilzation
    print_status
    if [ $CPU_UTILIZATION -ge $TARGET_CLUSTER_MEAN_CPU_UTILIZATION ]; then
        join_node
        elif [ $MEM_UTILIZATION -ge $TARGET_CLUSTER_MEAN_MEM_UTILIZATION ]; then
        join_node
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
    sleep $sleep_value
done
