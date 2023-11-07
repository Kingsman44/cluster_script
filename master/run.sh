command=$2
host=$1
token="$(kubeadm token create --print-join-command)"

case $command in
	"setup") ./send.sh $host "setup"
		;;
	"join") ./send.sh $host "join $token"
		echo "token sent"
		;;
	"leave")
		kubectl drain $host
		kubectl delete node $host
		./send.sh $host "leave"
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
