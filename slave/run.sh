chmod +x setup.sh
echo "Started Recieving commands"
echo "Ctrl + C to Exit"
MASTER="master"
while true; do
        echo "Waiting for command "
        message="$(nc -l 123)"
        echo "Command: $message"
        case "$message" in
		master*)
			MASTER="$(echo $message | cut -d' ' -f2)"
			echo "Setted master hostname as $MASTER"
			;;
                "setup")
			if [ ! -f setup_done ]; then
                        	echo "Running Setup"
                        	./setup.sh
				touch setup_done
			else
				echo "Setup already done"
			fi
                        ;;
                join*)
			sudo modprobe br_netfilter
			sudo sysctl -w net.ipv4.ip_forward=1
                        ip=$(echo $message | cut -d' ' -f4)
                        token=$(echo $message | cut -d' ' -f6)
                        cert=$(echo $message | cut -d' ' -f8)
                        echo "join token: $token"
                        kubeadm join $ip --token $token --discovery-token-ca-cert-hash $cert
                        ;;
                "leave")
                        echo "leaving the node"
                        kubeadm reset -f
                        ;;
		"get-cpu")
			cpu="$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')"
			./send.sh $MASTER "$cpu"
			;;
        esac
done
