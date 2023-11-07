host=$1
message="$2"

echo "$message" | nc -N $host 124
