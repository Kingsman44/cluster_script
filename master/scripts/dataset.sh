#!/bin/bash

# Output file for storing metrics
mkdir -p ../dataset
CLUSTER_FILE="../dataset/cluster_metrics.csv"
POD_FILE="../dataset/pod_metrics.csv"

CLUSTERS="slave1"

DEPLOYMENT_NAME=""

if [ ! -f $CLUSTER_FILE ]; then
    echo "timeStamp,nodename,cpu,ram,rtt,next_cpu,next_ram,next_rtt" >> "$CLUSTER_FILE"
fi

# if [ ! -f $POD_FILE ]; then
#     echo "timeStamp,podname,cpu,ram,rtt,next_cpu,next_ram,next_rtt" >> "$POD_FILE"
# fi

#PODS="$(kubectl top pod $DEPLOYMENT_NAME | grep $DEPLOYMENT_NAME | awk '{print $1}')"
#echo $PODS

collect_metrics() {
    saved_cluster_value=""
    saved_pod_value=""
    timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
    for cluster in $CLUSTERS; do
        var="$(kubectl top node $cluster)"
        cpu_value="$(echo "$var" | grep "$cluster " | awk '{print $3}' | tr -d '%')"
        ram_value="$(echo "$var" | grep "$cluster " | awk '{print $5}' | tr -d '%')"
        rtt_value=$(ping -c 1 $cluster | tail -1 | awk '{print $4}' | cut -d'=' -f2 | cut -d'/' -f1)
        saved_cluster_value="$saved_cluster_value
$timestamp,$cluster,$cpu_value,$ram_value,$rtt_value"
    done

#     for pod in $PODS; do
#         var="$(kubectl top pod $pod)"
#         cpu_value="$(echo "$var" | grep "$pod " | awk '{print $3}' | tr -d '%')"
#         ram_value="$(echo "$var" | grep "$pod " | awk '{print $5}' | tr -d '%')"
#         rtt_value=$(ping -c 1 localhost | tail -1 | awk '{print $4}' | cut -d'=' -f2)
#         saved_pod_value="$saved_pod_value
# $timestamp,$pod,$cpu_value,$ram_value,$rtt_value"
#     done
    
    sleep 4.8
    
    for value in "$saved_cluster_value"; do
        cluster="$(echo $value | cut -d, -f2)"
        if [ -z "$cluster" ]; then
                continue
        fi
        var="$(kubectl top node $cluster)"
        cpu_value="$(echo "$var" | grep "$cluster " | awk '{print $3}' | tr -d '%')"
        ram_value="$(echo "$var" | grep "$cluster " | awk '{print $5}' | tr -d '%')"
        rtt_value="$(ping -c 1 $cluster | tail -1 | awk '{print $4}' | cut -d'=' -f2 | cut -d'/' -f1)"
        final_value="$value,$cpu_value,$ram_value,$rtt_value"
        echo CLUSTER:$cluster:$final_value
        echo $final_value >> $CLUSTER_FILE
    done   

    #for value in $saved_pod_value; do
}

while true; do
    collect_metrics
done
