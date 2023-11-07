chmod +x setup.sh
echo "Started Recieving commands"
echo "Ctrl + C to Exit"
while true; do
        echo "Waiting for command "
        message="$(nc -l 123)"
        echo "Command: $message"
        case "$message" in
                "setup")
                        echo "Running Setup"
                        ./setup.sh
                        ;;
                join*)
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
        esac
done
