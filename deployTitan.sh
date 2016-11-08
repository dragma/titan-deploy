# script s from titan.sh file
$GSRV_SHUTDOWN_TIMEOUT_S=60;
$ELASTICSEARCH_SHUTDOWN_TIMEOUT_S=60;
$CASSANDRA_SHUTDOWN_TIMEOUT_S=60;
$SLEEP_INTERVAL_S=2

# Locate the jps command.  Check $PATH, then check $JAVA_HOME/bin.
# This does not need to by cygpath'd.
JPS=
for maybejps in jps "${JAVA_HOME}/bin/jps"; do
    type "$maybejps" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        JPS="$maybejps"
        break
    fi
done

status_class() {
    local p=`$JPS -l | grep "$2" | awk '{print $1}'`
    if [ -n "$p" ]; then
        echo "$1 ($2) is running with pid $p"
        return 0
    else
        echo "$1 ($2) does not appear in the java process table"
        return 1
    fi
}

wait_for_shutdown() {
    local friendly_name="$1"
    local class_name="$2"
    local timeout_s=60

    local now_s=`date '+%s'`
    local stop_s=$(( $now_s + $timeout_s ))

    while [ $now_s -le $stop_s ]; do
        status_class "$friendly_name" $class_name >/dev/null
        if [ $? -eq 1 ]; then
            # Class not found in the jps output.  Assume that it stopped.
            return 0
        fi
        sleep 2
        now_s=`date '+%s'`
    done

    echo "$friendly_name shutdown timeout exceeded ($timeout_s seconds)" >&2
    return 1
}

kill_class() {
    local p=`$JPS -l | grep "$2" | awk '{print $1}'`
    if [ -z "$p" ]; then
        echo "$1 ($2) not found in the java process table"
        return
    fi
    echo "Killing $1 (pid $p)..." >&2
    case "`uname`" in
        CYGWIN*) taskkill /F /PID "$p" ;;
        *)       kill "$p" ;;
    esac
}

stop() {
    kill_class        'Gremlin-Server' org.apache.tinkerpop.gremlin.server.GremlinServer
    wait_for_shutdown 'Gremlin-Server' org.apache.tinkerpop.gremlin.server.GremlinServer
    kill_class        Elasticsearch org.elasticsearch.bootstrap.Elasticsearch
    wait_for_shutdown Elasticsearch org.elasticsearch.bootstrap.Elasticsearch
    kill_class        Cassandra org.apache.cassandra.service.CassandraDaemon
    wait_for_shutdown Cassandra org.apache.cassandra.service.CassandraDaemon
}

CASSANDRA_CONF_FILTE_NAME="titan-cassandra-es.properties";
GREMLIN_CONF_FILE_NAME="gremlin-server.yaml";
TITAN_DIR_NAME="titan-1.0.0-hadoop1"; # shall not bo changed
TITAN_ZIP_IMAGE="titan.zip";
TITAN_SETUP_DIR='..';

if [ $# -eq 2 ]
then
    if [ $1 = '-d' ]
    then
        TITAN_SETUP_DIR=${2%/};
        if [ ! -d "$TITAN_SETUP_DIR" ]
        then
            echo "Error:"
            echo "  $TITAN_SETUP_DIR is not a valid directory.";
            exit;
        fi
    else
        echo "Wrong option.";
        echo "  Usage:";
        echo "    ./deployTitan.sh [-d path/to/setup/directory]"
        exit;
    fi
fi

echo "-> Titan install directory: '$TITAN_SETUP_DIR'";
echo "-> Titan work directory:    '$TITAN_SETUP_DIR/$TITAN_DIR_NAME'";

if [ ! -f "./$TITAN_ZIP_IMAGE" ]; then
    echo "File not found!";
    echo "Downloading image";
    wget -O "./$TITAN_ZIP_IMAGE" http://s3.thinkaurelius.com/downloads/titan/titan-1.0.0-hadoop1.zip;
else
    echo "Titan image found";
fi

echo "Trying to shut down titan";
stop

echo "Destroy previous Titan installation";
rm -rf "$TITAN_SETUP_DIR/$TITAN_DIR_NAME";

echo "Unziping...";
unzip ./titan.zip -d "$TITAN_SETUP_DIR/" &> /dev/null;

echo "Moving config files";
cp "./$CASSANDRA_CONF_FILTE_NAME" "$TITAN_SETUP_DIR/$TITAN_DIR_NAME/conf/$CASSANDRA_CONF_FILTE_NAME";
cp "./$GREMLIN_CONF_FILE_NAME" "$TITAN_SETUP_DIR/$TITAN_DIR_NAME/conf/gremlin-server/$GREMLIN_CONF_FILE_NAME";