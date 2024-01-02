TARGET_CLUSTER_MEAN_UTILIZATION=50
CLUSTER_CONFIG='connected=false
ram=
cpu='
CONNECTED_NODES=()
DISCONNECTED_NODES=()
TOTAL_DIS=0
CPU_UTILIZATION=0

setup_cluster_config() {
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
		DISCONNECTED_NODES+=("$p")
		echo $CLUSTER_CONFIG >> cluster/$p
		./scripts/run.sh $p "master"
        fi
    done <worker.config
}

get_cpu_utilzation() {
	total_usage="$(kubectl top nodes | grep "master " | awk '${print $3}' | tr -d '%'
	total_cpu=1
	for i in $CONNECTED_NODES; do
		var="$(kubectl top node $i)"
  		value="$(echo "$var" | grep "$i " | awk '${print $3}' | tr -d '%')"
    		echo "NODE: $i, VALUE: $value"
		total_cpu=$(echo "scale=2 ; $total_cpu + 1" | bc)
		total_usage=$(echo "scale=2 ; $total_usage + $value" | bc)
	done
	CPU_UTILIZATION=$(echo "scale=2 ; $total_usage / $total_cpu" | bc )
	CPU_UTILIZATION=$(echo "($CPU_UTILIZATION+0.5)/1" | bc)
	echo "Current Mean CPU Utilzation of connected nodes: $CPU_UTILIZATION%"
}

setup_metrics_server() {
	kubectl taint nodes --all node-role.kubernetes.io/control-plane-
	kubectl taint nodes --all node.kubernetes.io/disk-pressure-
	kubectl apply -f yaml/metrics-server.yaml
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
rm -rf cluster
mkdir cluster
setup_cluster_config
echo "================="
NODES=$(ls cluster)
echo "Setting up Kubernetes on nodes"
for node in $NODES; do
	./scripts/run.sh $node setup
done
echo "================"
rm -rf hpa.yaml
cp yaml/hpa.yaml hpa.yaml
DEPLOYMENT_NAME=$1
if [ -z "$DEPLOYMENT_NAME" ]; then
	echo "Deployment name is empty, exiting..."
	exit
fi
sed -i -e "s/hpa-demo-deployment/$DEPLOYMENT_NAME/g" hpa.yaml
shift
PARAMETERS=$@
for parameter in $PARAMETERS; do
	#echo $parameter
	if [ "$(echo $parameter | grep minReplicas)" ]; then
		value=$(echo $parameter | cut -d= -f2 | tr -dc '0-9')
		if [ -z $value ]; then
			echo "Empty or unknown value minReplicas, using default 1"
			continue
		fi
		echo "setting minReplicas to $value"
		sed -i -e "s/minReplicas: 1/minReplicas: $value/g" hpa.yaml
	elif [ "$(echo $parameter | grep maxReplicas)" ]; then
                value=$(echo $parameter | cut -d= -f2 | tr -dc '0-9')
                if [ -z $value ]; then
                        echo "Empty or unknown value maxReplicas, using default 10"
                        continue
                fi
		echo "setting maxReplicas to $value"
                sed -i -e "s/maxReplicas: 10/maxReplicas: $value/g" hpa.yaml
        elif [ "$(echo $parameter | grep CPUUtilization)" ]; then
                value=$(echo $parameter | cut -d= -f2 | tr -dc '0-9')
                if [ -z $value ]; then
                        echo "Empty or unknown value for targetCPUUtilizationPercentage, using default 50%"
                        continue
                fi
		echo "setting targetCPUUtilizationPercentage to $value"
                sed -i -e "s/targetCPUUtilizationPercentage: 50/targetCPUUtilizationPercentage: $value/g" hpa.yaml
	fi
done
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
	echo "Connected Nodes: master ${CONNECTED_NODES[*]}"
	echo "Disconnected Nodes: ${DISCONNECTED_NODES[*]}"
	get_cpu_utilzation
	if [ $CPU_UTILIZATION -ge $TARGET_CLUSTER_MEAN_UTILIZATION ]; then
		if [ ${#DISCONNECTED_NODES[@]} -gt 0 ]; then
			node=${DISCONNECTED_NODES[$TOTAL_DIS]}
			echo "Selected node: $node"
			unset DISCONNECTED_NODES[$TOTAL_DIS]
			CONNECTED_NODES+=($node)
			./scripts/run.sh $node join
			TOTAL_DIS=$(echo "$TOTAL_DIS + 1" | bc)
			echo "Joining node $node"
		else
			echo "No nodes are free unable to connect node"
		fi
	fi
	sleep 5
done
