command=$2
host=$1

case $command in
	"master")
		./scripts/send.sh $host "master $(cat /etc/hostname)"
		;;
	"setup-master")
		./scripts/setup_master.sh
		;;
	"setup") ./scripts/send.sh $host "setup"
		;;
	"join") token="$(kubeadm token create --print-join-command)"
		./scripts/send.sh $host "join $token"
		echo "token sent"
		;;
	"leave")
		kubectl drain $host
		kubectl delete node $host
		./scripts/send.sh $host "leave"
		;;
	"get-cpu")
		./scripts/send.sh $host "get-cpu"
		cpuutil=$(nc -l 124)
		echo "$cpuutil"
		;;
	"cpu")
		if [ ! -z "$3" ]; then
			mem=$(kubectl top pod $3 | grep $3 | sed  -r "s/ +/ /g" | cut -d' ' -f2)
			echo "CPU Usage: $mem"
		fi
		;;
	"memory")
                if [ ! -z "$3" ]; then
                        mem=$(kubectl top pod $3 | grep $3 | sed  -r "s/ +/ /g" | cut -d' ' -f3)
                        echo "Memory Usage: $mem"
                fi
		;;
	"*")
		echo "unknown command"
		;;
esac
