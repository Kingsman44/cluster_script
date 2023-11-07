chmod +x setup.sh
chmod +x join.sh
echo "Started Recieving commands"
echo "Ctrl + C to Exit"
while true; do
	echo "Waiting for command "
	message="$(nc -l 123)"
	echo "Command: $message"
	case "$message" in
		"setup")
			echo "Running Setup"
			#./setup.sh
			;;
		join*)
			token=$(echo $message | cut -d' ' -f2-999)
			echo "join token: $token"
			#./join.sh $token
			#./"$token"
			;;
		"leave")
			echo "leaving the node"
			#kubeadm reset
			;;
	esac
done
