#!/bin/bash

ACTION=$1

function usage() {
	echo "Usage: $0 <prep|run|cleanup> [remoteserver] [repts]" >&2
	exit 1
}


TARGET_IP=${2-localhost}	# dns/ip for machine to test
TEST_USER=${3}
CMD_PATH=${4}

REPTS=${5-10}
REQ=${6-''}

NR_REQUESTS=1000
TABLE_SIZE=1000000
RESULTS=mysql.txt

function prepare() {
	mysql -u root < create_db.sql
	# sysbench --test=oltp --oltp-table-size=$TABLE_SIZE prepare
	sysbench oltp_read_write --table-size=$TABLE_SIZE --db-driver=mysql --mysql-user=root --mysql-host=$TARGET_IP prepare
}

function cleanup() {
	# sysbench --test=oltp cleanup
	sysbench oltp_read_write --db-driver=mysql --mysql-user=root --mysql-host=$TARGET_IP cleanup
	mysql -u root < drop_db.sql
}

function run() {
	# sysbench --test=oltp $REQ --oltp-table-size=$TABLE_SIZE --num-threads=$num_threads --mysql-host=$TARGET_IP run | tee \
	# >(grep 'total time:' | awk '{ print $3 }' | sed 's/s//' >> $RESULTS)
	sysbench oltp_read_write $REQ --table-size=$TABLE_SIZE --num-threads=$num_threads --mysql-user=root --mysql-host=$TARGET_IP run | tee \
	>(grep 'total time:' | awk '{ print $3 }' | sed 's/s//' >> $RESULTS)
}

if [[ "$TARGET_IP" != "localhost" && ("$ACTION" == "prep" || "$ACTION" == "cleanup") ]]; then
	echo "prep and cleanup actions can only be run on the db server" >&2
	exit 1
fi

if [[ "$ACTION" == "prep" ]]; then
	service mysql start
	cleanup
	prepare
elif [[ "$ACTION" == "run" ]]; then
	source exits.sh mysql
	start_measurement

	for num_threads in 100; do
		echo -e "$num_threads threads:\n---" >> $RESULTS
		for i in `seq 1 $REPTS`; do
			ssh $TEST_USER@$TARGET_IP "pushd ${CMD_PATH};sudo ./mysql.sh prep"
			run
			ssh $TEST_USER@$TARGET_IP "pushd ${CMD_PATH};sudo ./mysql.sh cleanup"
		done;
		echo "" >> $RESULTS
	done;

	end_measurement
	save_stat

elif [[ "$ACTION" == "cleanup" ]]; then
	#We will do a lazy-cleanup.
	service mysql stop
else
	usage
fi
