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
		echo "kubectl drain $host"
		echo "kubectl delete node $host"
		./send.sh $host "leave"
		;;
	"*")
		echo "unknown command"
		;;
esac

