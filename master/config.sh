#MASTER NODE
MASTER_NODE="master"

#MEAN CPU PERCENT TO DO CLUSTER AUTOSCALING
TARGET_CLUSTER_MEAN_CPU_UTILIZATION=50

#MEAN RAM PERCENT TO DO CLUSTER AUTOSCALING
TARGET_CLUSTER_MEAN_MEM_UTILIZATION=80

#MAX RTT THRESHOLD (rtt*100) (int)
MAX_RTT=200

#THRESHOLD TO LEAVE NODE 
LOWER_THRESHOLD=5

#CHECK CONTINUOS LOWER THRESHOLD 
TARGET_LOWER_CNT_THRESHOLD=10

#RTT COUNT THRESHOLD TO CHANGE NODE OF REGULAR EXCEED
RTT_CNT_THRESHOLD=10

# DEPLOYMENT to AUTOSCALE
DEPLOYMENT_NAME="nginx"

#HPA CONFIG
minReplicas=1
maxReplicas=10
targetCPUUtilization=50
targetRAMUtilization=50

