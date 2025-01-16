#!/bin/bash


# prereq: sudo dnf -y install git

rm -rf config inv cache script DISABLE_WATCHDOG_CPU_WALLCLOCK_CHECK script-configuration.sh workflow.json script-invocation.json stderr.log
rm -f test_*json script.sh.provenance.json 
if [ "$1" = "clean" ]; then exit 0; fi

cat <<EOF >workflow.json
{"name":"test","description":"test","author":"test","tool-version":"v0.0.1","schema-version":"0.5","command-line":"echo [INPUT1] > ./output.txt","container-image":{"image":"ubuntu:latest","index":"docker://","type":"docker"},"inputs":[{"id":"input1","name":"Input1","type":"String","value-key":"[INPUT1]"}],"output-files":[{"id":"output1","name":"Output1","optional":false,"path-template":"output.txt"}]}
EOF

TESTCONTENT="test_b"
cat <<EOF >script-invocation.json
{"input1":"$TESTCONTENT"}
EOF
# this should create a ./script/output.txt file containing "$TESTCONTENT"


# from ~/gitwork/ng/tasks/1034-example-configuration.sh
cat <<'EOF' >script-configuration.sh
defaultEnvironment=""
cacheDir="${BASEDIR}/cache"
cacheFile="cache.txt"
minAvgDownloadThroughput="150"
srmTimeout="30"
simulationID="workflow-f9sMrq"
timeout="10"
bdiiTimeout="10"
boshCVMFSPath="/cvmfs/biomed.egi.eu/vip/virtualenv/bin"
voDefaultSE="SBG-disk CPPM-disk NIKHEF-disk"
uploadURI="file:/var/www/html/workflows/SharedData/users/admin_test/06-01-2025_09:59:17"
downloads=""
boutiquesFilename="workflow.json"
udockerTag="1.3.1"
singularityPath="/cvmfs/dirac.egi.eu/dirac/v8.0.39/Linux-x86_64/bin"
containersCVMFSPath="/cvmfs/biomed.egi.eu/vip/udocker/containers"
nrep="1"
voUseCloseSE="true"
boutiquesProvenanceDir="$HOME/.cache/boutiques/data"

udockerTag="1.3.17"
uploadURI="file:$PWD/_uploads/$(date +%Y%m%d%H%M%S)"
EOF
mkdir -p "$PWD/_uploads"

bash ./script.sh 2>stderr.log

if command -v shellcheck >/dev/null; then
  shellcheck ./script.sh && echo "shellcheck ok"
fi

# todo /refactor:

