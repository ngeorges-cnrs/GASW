#!/bin/bash
# relatively harmless warnings, globally disabled:
# shellcheck disable=SC2155  # local v=$(), ok if we ignore return value
# shellcheck disable=SC2001  # echo|sed vs ${var//search/replace}
# shellcheck disable=SC2012  # ls vs find
# shellcheck disable=SC2181  # style: if [ $? = 0 ] vs if command

### global settings

# This section should only define script-global variables.

# Extract filename without extension
DIRNAME=$(basename "${0%.sh}")

# Base directory
BASEDIR="$PWD"

# Set HOME if not defined.
# Also set APPTAINER_HOME, so that HOME is set inside singularity containers.
if [ -z "$HOME" ]; then
  export HOME="$PWD"
  export APPTAINER_HOME="$PWD:$PWD"
fi

# Names of the configuration and invocation files
configurationFilename="$DIRNAME-configuration.sh"
invocationJsonFilename="$DIRNAME-invocation.json"

### functions

# This section should only contain functions definitions, no global command.
# Functions should favor local variables.

## logging

# logDate: date formatting helper for logging functions
function logDate {
  # LC_ALL=C: use neutral locale for date output
  # xargs: merge consecutive spaces to keep previous unquoted behaviour
  LC_ALL=C TZ=UTC date | xargs
}

# info: log an info-level message on stdout
function info {
  echo "[ INFO - $(logDate) ] $*"
}

# warning: log a warning-level message on stdout
function warning {
  echo "[ WARN - $(logDate) ] $*"
}

# error: log an error-level message on stderr
function error {
  echo "[ ERROR - $(logDate) ] $*" >&2
}

# startLog: start a log section with an opening tag and optional attributes,
# on stdout+stderr
function startLog {
  echo "<$*>" >&1
  echo "<$*>" >&2
}

# stopLog: stop a log section with a closing tag, on stdout+stderr
function stopLog {
  local logName="$1"
  echo "</${logName}>" >&1
  echo "</${logName}>" >&2
}

# showHostConfig: print a summary of the current runtime environment
function showHostConfig {
  startLog host_config
  echo "SE Linux mode is:"
  /usr/sbin/getenforce
  echo "gLite Job Id is ${GLITE_WMS_JOBID}"
  echo "===== uname ===== "
  uname -a
  domainname -a
  echo "===== network config ===== "
  /sbin/ifconfig eth0
  local dmesg_line=$(dmesg | grep 'Link is Up' | uniq)
  local netspeed=$(echo "$dmesg_line" | grep -o '[0-9]*[[:space:]][a-zA-Z]bps'| awk '{gsub(/ /,"",$0);print}')
  echo "NetSpeed = $netspeed ($dmesg_line)"
  echo "===== CPU info ===== "
  cat /proc/cpuinfo
  echo "===== Memory info ===== "
  cat /proc/meminfo
  echo "===== lcg-cp location ===== "
  which lcg-cp
  echo "===== ls -a . ===== "
  ls -a
  echo "===== ls -a .. ===== "
  ls -a ..
  echo "===== env ====="
  env
  echo "===== rpm -qa  ===="
  rpm -qa
  stopLog host_config
}

# getJsonDepth2: get the value of key1.key2 from a json file.
# Print output on stdout, blank when not found.
function getJsonDepth2 {
  local file="$1"
  local key1="$2"
  local key2="$3"
  python -c 'import sys,json;v=json.load(sys.stdin).get("'"$key1"'",None);print(v.get("'"$key2"'","") if isinstance(v,dict) else "")' < "$file"
}

## runtime tools installation

# checkBosh: install bosh if needed, or make it available in PATH
function checkBosh {
  # by default, use CVMFS bosh
  test -e "$boshCVMFSPath"/bosh && "$boshCVMFSPath"/bosh create foo.sh
  if [ $? != 0 ]; then
    info "CVMFS bosh in $boshCVMFSPath not working, checking for a local version"
    bosh create foo.sh
    if [ $? != 0 ]; then
      info "bosh is not found in PATH or it is does not work fine, searching for another local version"
      local HOMEBOSH=$(find "$HOME" -name bosh)
      if [ -z "$HOMEBOSH" ]; then
        info "bosh not found, trying to install it"
        export PATH="$HOME/.local/bin:$PATH"
        pip install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org --user boutiques
        if [ $? != 0 ]; then
          error "pip install boutiques failed"
          exit 1
        else
          export BOSHEXEC="bosh"
        fi
      else
        info "local bosh found in $HOMEBOSH"
        export BOSHEXEC=$HOMEBOSH
      fi
    else # bosh is found in PATH and works fine
      info "local bosh found in $PATH"
      export BOSHEXEC="bosh"
    fi
  else # if bosh CVMFS works fine
    export BOSHEXEC="$boshCVMFSPath/bosh"
  fi
}

# checkDocker: install udocker if needed
function checkDocker {
  if command -v docker; then # docker command found in PATH
    return 0
  fi
  # install udocker (A basic user tool to execute simple docker containers in batch or interactive systems without root privileges)
  info "cloning udocker $udockerTag"
  git clone --depth=1 --branch "$udockerTag" https://github.com/indigo-dc/udocker.git
  (cd udocker/udocker && ln -s maincmd.py udocker)
  export PATH="$PWD/udocker/udocker:$PATH"

  # creating a temporary directory for udocker containers
  mkdir -p containers
  export UDOCKER_CONTAINERS="$PWD/containers"

  # find pre-deployed containers on CVMFS,
  # and create a symlink to the udocker containers directory.
  if [ -d "$containersCVMFSPath" ]; then
    for d in "$containersCVMFSPath"/*/; do
      mkdir "containers/$(basename "${d%/}")" && ln -s "${d%/}"/* "containers/$(basename "${d%/}")/"
    done
  fi
  cat >docker <<'EOF'
#!/bin/bash
MYARGS=$*
echo "executing ./udocker/udocker/udocker $MYARGS"
./udocker/udocker/udocker $MYARGS
EOF
  chmod a+x docker
  export PATH="$PWD:$PATH"
}

# checkSingularity: check that singularity is in PATH, or make it available
# with $singularityPath
function checkSingularity {
  # command -v displays the path to singularity if found
  info "checking for singularity"
  if ! command -v singularity; then
    if test -d "$singularityPath"; then
      export PATH="$singularityPath:$PATH"
      info "adding singularityPath to PATH ($singularityPath)"
    else
      warning "singularityPath not found ($singularityPath), leaving PATH unchanged"
    fi
  fi
}

# checkGirderClient: install girder-client if needed
function checkGirderClient {
  if ! command -v girder-client; then
    pip install --user girder-client
    if [ $? != 0 ]; then
      error "girder-client not in PATH, and an error occured while trying to install it."
      error "Exiting with return value 1"
      exit 1
    fi
  fi
}

## termination handler

# cleanup: perform cleanup tasks such as unmounting directories, killing
# background processes, and printing log information. It is executed on exit.
function cleanup {
  # flag checks if directories are mounted with gfal
  if [[ $isGfalmountExec -eq 0 ]]; then
    unmountGfal    #unmounts all gfal mounted directories
    unlink /tmp/*_"$(basename "$PWD")"
  fi
  startLog cleanup
  info "=== ls -a ==="
  ls -a
  info "=== ls $cacheDir/$cacheFile ==="
  ls "$cacheDir/$cacheFile"
  info "=== cat $cacheDir/$cacheFile === "
  cat "$cacheDir/$cacheFile"
  info "Cleaning up: $(echo rm * -Rf)"
  # remove all files in the exec dir
  rm -Rf -- *
  info "END date:"
  date +%s
  stopLog cleanup
  check_cleanup=true
}

## cache management

# addToCache: add a downloaded file to the local cache with its timestamp
function addToCache {
  touch "$cacheDir/$cacheFile"
  local LFN="$1"
  local FILE=$(basename "$2")
  local i=0
  local exist="true"
  local NAME=""
  while [ "$exist" = "true" ]; do
    NAME="$cacheDir/${FILE}-cache-${i}"
    if ! test -f "${NAME}"; then
      exist="false"
    fi
    ((i++))
  done
  info "Removing all cache entries for ${LFN} (files will stay locally in case anyone else needs them)"
  local TEMP=$(mktemp temp.XXXXXX)
  awk -v L="${LFN}" '$1!=L {print}' "$cacheDir/$cacheFile" > "${TEMP}"
  mv -f "${TEMP}" "$cacheDir/$cacheFile"
  info "Adding file ${FILE} to cache and setting the timestamp"
  cp -f "${FILE}" "${NAME}"
  local date_local=$(ls -la "${NAME}" | awk -F' ' '{print $6, $7, $8}')
  local TIMESTAMP=$(date -d "${date_local}" +%s)
  echo "${LFN} ${NAME} ${TIMESTAMP}" >> "$cacheDir/$cacheFile"
}

# checkCacheDownloadAndCacheLFN: check if a file is available in the local
# cache. If not, download the file and add it to the cache.
function checkCacheDownloadAndCacheLFN {
  local LFN="$1"
  local download="true"

  local LOCALPATH=$(awk -v L="$LFN" '$1==L {print $2}' "$cacheDir/$cacheFile")
  if [ -n "$LOCALPATH" ]; then
    info "There is an entry in the cache: test if the local file still here"
    local TIMESTAMP_LOCAL=""
    local TIMESTAMP_GRID=""
    local date_local=""
    if [ -f "${LOCALPATH}" ]; then
      info "The file exists: checking if it was modified since it was added to the cache"
      local YEAR=$(date +%Y)
      local YEARBEFORE=$((YEAR - 1))
      local currentDate=$(date +%s)
      local TIMESTAMP_CACHE=$(awk -v L="$LFN" '$1==L {print $3}' "$cacheDir/$cacheFile")
      local LOCALMONTH=$(ls -la "$LOCALPATH" | awk -F' ' '{print $6}')
      local MONTHTIME=$(date -d "$LOCALMONTH 1 00:00" +%s)
      date_local=$(ls -la "$LOCALPATH" | awk -F' ' '{print $6, $7, $8}')
      if [ "$MONTHTIME" -gt "$currentDate" ]; then
        TIMESTAMP_LOCAL=$(date -d "$date_local $YEARBEFORE" +%s)
      else
        TIMESTAMP_LOCAL=$(date -d "$date_local $YEAR" +%s)
      fi
      if [ "$TIMESTAMP_CACHE" = "$TIMESTAMP_LOCAL" ]; then
        info "The file was not touched since it was added to the cache: test if it is up-to-date"
        local date_grid_s=$(lfc-ls -l "$LFN" | awk -F' ' '{print $6, $7, $8}')
        local MONTHGRID=$(echo "$date_grid_s" | awk -F' ' '{print $1}')
        MONTHTIME=$(date -d "$MONTHGRID 1 00:00" +%s)
        if [ -n "$MONTHTIME" ] && [ -n "$date_grid_s" ]; then
          if [ "$MONTHTIME" -gt "$currentDate" ]; then
            # it must be last year
            TIMESTAMP_GRID=$(date -d "${date_grid_s} ${YEARBEFORE}" +%s)
          else
            TIMESTAMP_GRID=$(date -d "${date_grid_s} ${YEAR}" +%s)
          fi
          if [ "${TIMESTAMP_LOCAL}" -gt "${TIMESTAMP_GRID}" ]; then
            info "The file is up-to-date ; there is no need to download it again"
            download="false"
          else
            warning "The cache entry is outdated (local modification date is ${TIMESTAMP_LOCAL} - ${date_local} while grid is ${TIMESTAMP_GRID} ${date_grid_s})"
          fi
        else
          warning "Cannot determine file timestamp on the LFC"
        fi
      else
        warning "The cache entry was modified since it was created (cache time is ${TIMESTAMP_CACHE} and file time is ${TIMESTAMP_LOCAL} - ${date_local})"
      fi
    else
      warning "The cache entry disappeared"
    fi
  else
    info "There is no entry in the cache"
  fi

  if [ "${download}" = "false" ]; then
    info "Linking file from cache: ${LOCALPATH}"
    BASE=$(basename "$LFN")
    echo "BASE : $BASE"
    echo "LOCALPATH : $LOCALPATH"
    info "ln -s $LOCALPATH ./$BASE"
    ln -s "$LOCALPATH" "./$BASE"
    return 0
  fi

  if [ "${download}" = "true" ]; then
    echo "${LFN}"
    downloadLFN "$LFN" || return 1
    addToCache "$LFN" "$(basename "$LFN")"
    return 0
  fi
}

## shanoir token management

# refresh_token: refresh the Sanoir authentication token periodically, using
# a background process.
# URIs are of the form of the following example. A single "/", instead
# of 3, after "shanoir:" is also allowed.
# shanoir:/path/to/file/filename?&refreshToken=eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lk....&keycloak_client_id=....&keycloak_client_secret=...
# The mandatory arguments are: keycloak_client_id, keycloak_client_secret.
#
function refresh_token {
  touch "$SHANOIR_TOKEN_LOCATION"
  touch "$SHANOIR_REFRESH_TOKEN_LOCATION"

  local subshell_refresh_token=$(cat "$SHANOIR_REFRESH_TOKEN_LOCATION")

  echo "refresh token process started !"

  local URI="$1"
  local keycloak_client_id=$(echo "$URI" | sed -r 's/^.*[?&]keycloak_client_id=([^&]*)(&.*)?$/\1/i')
  local refresh_token_url=$(echo "$URI" | sed -r 's/^.*[?&]refresh_token_url=([^&]*)(&.*)?$/\1/i')

  if [[ ! "$subshell_refresh_token" ]]; then
    # initializing the refresh token
    subshell_refresh_token=$(echo "$URI" | sed -r 's/^.*[?&]refreshToken=([^&]*)(&.*)?$/\1/i')
    echo "$subshell_refresh_token" > "$SHANOIR_REFRESH_TOKEN_LOCATION"
  fi

  while :; do
    # get the new refresh token
    subshell_refresh_token=$(cat "$SHANOIR_REFRESH_TOKEN_LOCATION")

    # the response format is "{"status":"status"}"
    # this response format is made to handle error while getting the refreshed token in the same time
    COMMAND() {
      curl -w "{\"status\":\"%{http_code}\"}" -sb -o --request POST "${refresh_token_url}" --header "Content-Type: application/x-www-form-urlencoded" --data-urlencode "client_id=${keycloak_client_id}" --data-urlencode "grant_type=refresh_token" --data-urlencode "refresh_token=${subshell_refresh_token}"
    }

    local refresh_response=$(COMMAND)
    local exit_code=$?
    local status_code=$(echo "$refresh_response" | grep -o '"status":"[^"]*' | grep -o '[^"]*$')

    if ! [[ "$exit_code" -eq 0 && "$status_code" -eq 200 ]]; then
      local error_message=$(echo "$refresh_response" | grep -o '"error_description":"[^"]*' | grep -o '[^"]*$')
      error "error while refreshing the token: exit=${exit_code}, status=${status_code}, message: ${error_message}"
      exit 1
    fi

    # setting the new tokens
    echo "$refresh_response" | grep -o '"access_token":"[^"]*' | grep -o '[^"]*$' > "$SHANOIR_TOKEN_LOCATION"
    echo "$refresh_response" | grep -o '"refresh_token":"[^"]*' | grep -o '[^"]*$' > "$SHANOIR_REFRESH_TOKEN_LOCATION"

    sleep 240
  done
}

# stopRefreshingToken: stop the background token refreshing process.
function stopRefreshingToken {
  if [ "${REFRESH_PID}" != "" ]; then
    info "Killing background refresh token process with id : ${REFRESH_PID}"
    kill -9 "${REFRESH_PID}"
    REFRESH_PID=""
    echo "refresh token process ended !"
  fi
}

# wait_for_token: wait for the authentication token to be refreshed and
# to become available.
# The refresh token may take some time, this method is for that purpose
# and it exit the program if it's timed out
function wait_for_token {
  local token=""
  local attempts=0

  while [[ "${attempts}" -ne 3 ]]; do
    token=$(cat "$SHANOIR_TOKEN_LOCATION")
    if [[ "${token}" == "" ]]; then
      echo "token is not refreshed yet, waiting for 3 seconds..."
      echo "attempts : ${attempts}"
      attempts=$((attempts + 1))
      sleep 3
    else
      echo "token is refreshed !"
      break
    fi
  done

  # Check the token after the timeout
  if [[ -z "${token}" ]]; then
    echo "Token refreshing is taking too long. Aborting the process."
    stopRefreshingToken
    exit 1
  fi
}

## download helpers

# downloadLFN: download a file from a logical file name (LFN) path,
# using the Dirac command.
function downloadLFN {
  local LFN="$1"
  echo "LFN : ${LFN}"

  # Sanitize LFN:
  # - "lfn:" at the beginning is optional for dirac-dms-* commands,
  #    but does not work as expected with comdirac commands like
  #    dmkdir.
  # - "//" are not accepted, neither by dirac-dms-*, nor by dmkdir.
  LFN=$(echo "${LFN}" | sed -r -e 's/^lfn://' -e 's#//#/#g')

  info "getting file size and computing sendReceiveTimeout"
  local size=$(dirac-dms-lfn-metadata "$LFN" | grep Size | sed -r 's/.* ([0-9]+),/\1/')

  # Compute sendReceiveTimeout (doing a subbash command with ok to avoid a syntax error to stop the function)
  local sendReceiveTimeout=$((${size:-0} / ${minAvgDownloadThroughput:-150} / 1024))

  if [ "$sendReceiveTimeout" = "" ] || [ $sendReceiveTimeout -le 900 ]; then
    info "sendReceiveTimeout empty or too small, setting it to 900s"
    sendReceiveTimeout=900
  else
    info "sendReceiveTimeout is $sendReceiveTimeout"
  fi

  local LOCAL="$PWD/$(basename "$LFN")"
  info "Removing file ${LOCAL} in case it is already here"
  rm -f "$LOCAL"

  local totalTimeout=$((timeout + srmTimeout + sendReceiveTimeout))

  local LINE="dirac-dms-get-file -d -o /Resources/StorageElements/GFAL_TIMEOUT=${totalTimeout} ${LFN}"
  info "$LINE"
  local startDownload=$(date +%s)
  (${LINE}) &> get-file.log

  if [ $? = 0 ]; then
    local duration=$(($(date +%s) - startDownload))
    info "dirac-dms-get-file worked fine"
    local source=$(grep "generating url" get-file.log | tail -1 | sed -r 's/^.* (.*)\.$/\1/')
    info "DownloadCommand=dirac-dms-get-file Source=${source} Destination=$(hostname) Size=${size} Time=${duration}"
    RET_VAL=0
  else
    error "dirac-dms-get-file failed"
    error "$(cat get-file.log)"
    RET_VAL=1
  fi

  rm get-file.log
  return ${RET_VAL}
}

# downloadGirderFile: download a file from a Girder server using the Girder
# client.
# URI are of the form of the following example. A single "/", instead
# of 3, after "girder:" is also allowed.
# girder:///control_3DT1.nii?apiurl=http://localhost:8080/api/v1&fileId=5ae1a8fc371210092e0d2936&token=TFT2FdxP9hzM7WKsidBjMJMmN69
#
# The code is quite the same as the uploadGirderFile function.  Any
# changes should be done the same in both functions.
function downloadGirderFile {
  local URI="$1"

  # The regexpes are written so that case is ignored and the
  # arguments can be in any order.
  local fileName=$(echo "$URI" | sed -r 's#^girder:/(//)?([^/].*)\?.*$#\2#i')
  local apiUrl=$(echo "$URI" | sed -r 's/^.*[?&]apiurl=([^&]*)(&.*)?$/\1/i')
  local fileId=$(echo "$URI" | sed -r 's/^.*[?&]fileid=([^&]*)(&.*)?$/\1/i')
  local token=$(echo "$URI" | sed -r 's/^.*[?&]token=([^&]*)(&.*)?$/\1/i')

  checkGirderClient

  local COMMLINE="girder-client --api-url ${apiUrl} --token ${token} download --parent-type file ${fileId} ./${fileName}"
  echo "downloadGirderFile, command line is ${COMMLINE}"
  ${COMMLINE}
}

# gfalCheckMount: print 1 if gfalFS mounts exist, 0 if not
function gfalCheckMount {
  test -z "$(for file in *; do findmnt -t fuse.gfalFS -lo Target -n -T "$(realpath "$file")"; done)" && echo 1 || echo 0
}

# mountGfal: mount a directory using gfalFS for accessing grid storage elements.
# This function identifies the gfal path and extracts the basename of the directory to be mounted,
# and creates a directory with the exact name on $PWD of the node. This directory gets mounted with
# the corresponding directory on the SE.
#
# This function checks for all the gfal mounts in the current folder.
function mountGfal {
  local URI="$1"

  # The regexpes are written so that case is ignored and the
  # arguments can be in any order.
  local fileName=$(echo "$URI" | sed -r 's#^srm:/(//)?([^/].*)\?.*$#\2#i')
  local gfal_basename=$(basename "$fileName")
  local job_id=${gfal_basename}_$(basename "$PWD")

  CREATE_DIR_COMMAND="mkdir -p $gfal_basename"
  SYM_LINK_COMMAND="ln -s $PWD/$gfal_basename /tmp/$job_id"
  GFAL_COMMAND="gfalFS -s /tmp/$job_id ${fileName}"

  ${CREATE_DIR_COMMAND}
  ${SYM_LINK_COMMAND}
  ${GFAL_COMMAND}
  # Let nfs-kernel-server export the directory and write logs
  sleep 30
  gfalCheckMount
}

# unmountGfal: unmount all gfalFS-mounted directories.
# This function un-mounts all the gfal mounted directories by searching them
# with 'findmnt' and filtering them with FSTYPE 'fuse.gfalFS'. This function
# gets called in the cleanup function, either after the execution of the job,
# failure of the job, or interruption of the job.
function unmountGfal {
  START=$SECONDS
  while [ "$(gfalCheckMount)" = 0 ]; do
    for file in "$PWD"/*; do
      findmnt -t fuse.gfalFS -lo Target -n -T "$(realpath "$file")" && gfalFS_umount "$(realpath "$file")"
    done
    sleep 2
    # while loop breaks automatically after 10 minutes
    if [[ $((SECONDS - START)) -gt 600 ]]; then
      echo "WARNING - gfal directory couldn't be unmounted: timeout"
      break
    fi
  done
  gfalCheckMount
}

# downloadShanoirFile: download a file from the Shanoir platform using
# an API URL and authentication token.
# URI are of the form of the following example. A single "/", instead
# of 3, after "shanoir:" is also allowed.
# shanoir:/download.dcm?apiurl=https://shanoir-ng-nginx/shanoir-ng/datasets/carmin-data/path&format=dcm&datasetId=1
#
# This method depends on the refresh token process to refresh the token when it needs
function downloadShanoirFile {
  local URI="$1"

  wait_for_token

  local token=$(cat "$SHANOIR_TOKEN_LOCATION")

  echo "token inside download : ${token}"

  local fileName=$(echo "$URI" | sed -r 's#^shanoir:/(//)?([^/].*)\?.*$#\2#i')
  local apiUrl=$(echo "$URI" | sed -r 's/^.*[?&]apiurl=([^&]*)(&.*)?$/\1/i')
  local format=$(echo "$URI" | sed -r 's/^.*[?&]format=([^&]*)(&.*)?$/\1/i')
  local resourceId=$(echo "$URI" | sed -r 's/^.*[?&]resourceId=([^&]*)(&.*)?$/\1/i')
  local converterId=$(echo "$URI" | sed -r 's/^.*[?&]converterId=([^&]*)(&.*)?$/\1/i')

  COMMAND(){
    curl --write-out '%{http_code}' -o "$fileName" --request GET "$apiUrl/$resourceId?format=$format&converterId=$converterId" --header "Authorization: Bearer $token"
  }

  local attempts=0

  while [[ "${attempts}" -ne 3 ]]; do
    local status_code=$(COMMAND)
    local exit_code=$?
    info "downloadShanoirFile, exit code is : ${exit_code}, status code is : ${status_code}"

    if ! [[ "$exit_code" -eq 0 && "$status_code" -eq 200 ]]; then
      error "error while downloading the file: exit=${exit_code}, status=${status_code}"
      attempts=$((attempts + 1))
      info "${attempts} done. Waiting 3 seconds and maybe do another attempt"
      sleep 3
    else
      break
    fi
  done

  if [[ "${attempts}" -ge 3 ]]; then
    error "3 failures at downloading, stop trying and stop the job"
    stopRefreshingToken
    exit 1
  fi

  if [[ $format = "zipped_nii" ]]; then
    echo "its a zipped nifti, it will be automatically unzipped"
    local TMP_UNZIP_DIR="tmp_unzip_dir"
    mkdir $TMP_UNZIP_DIR
    mv "$fileName" "$TMP_UNZIP_DIR/tmp.zip"
    unzip -d $TMP_UNZIP_DIR $TMP_UNZIP_DIR/tmp.zip
    # there should be a unique .nii ou .nii.gz file somewhere
    searchResult=$(find $TMP_UNZIP_DIR -name '*.nii.gz' -o -name '*.nii')
    # doing this trick instead of using "wc -l" because it fails when there is no result
    if [[ $(echo -n "$searchResult" | grep -c '^') -ne 1 ]]; then
      error "too many or none nifti file (.nii or .nii.gz) in shanoir zip, supporting only 1"
      stopRefreshingToken
      exit 1
    fi
    mv "$searchResult" "$fileName"
    rm -rf $TMP_UNZIP_DIR
  fi
}

# validateDownload: validate if the download was successful,
# and exit with an error message if not
function validateDownload {
  if [ $? != 0 ]; then
    echo "$1"
    echo "Exiting with return value 1"
    exit 1
  fi
}

# downloadURI: download a file from various URI schemes 
function downloadURI {
  local URI="$1"
  local URI_LOWER=$(echo "$URI" | awk '{print tolower($0)}')

  startLog file_download uri="${URI}"

  if [[ ${URI_LOWER} == lfn* ]] || [[ $URI_LOWER == /* ]]; then
    ## Extract the path part from the uri, and remove // if present in path.
    LFN=$(echo "${URI}" | sed -r -e 's%^\w+://[^/]*(/[^?]+)(\?.*)?$%\1%' -e 's#//#/#g')

    checkCacheDownloadAndCacheLFN "$LFN"
    validateDownload "Cannot download LFN file"
  fi

  if [[ ${URI_LOWER} == file:/* ]]; then
    local FILENAME=$(echo "$URI" | sed 's%file://*%/%')
    cp "$FILENAME" .
    validateDownload "Cannot copy input file: $FILENAME"
  fi

  if [[ ${URI_LOWER} == http://* ]]; then
    curl --insecure -O "$URI"
    validateDownload "Cannot download HTTP file"
  fi

  if [[ ${URI_LOWER} == girder:/* ]]; then
    downloadGirderFile "$URI"
    validateDownload "Cannot download Girder file"
  fi

  if [[ ${URI_LOWER} == shanoir:/* ]]; then
    if [[ "$REFRESHING_JOB_STARTED" == false ]]; then
      refresh_token "$URI" &
      REFRESH_PID=$!
      REFRESHING_JOB_STARTED=true
    fi
    downloadShanoirFile "$URI"
    validateDownload "Cannot download shanoir file"
  fi

  if [[ ${URI_LOWER} == srm:/* ]]; then
    if [[ $(mountGfal "$URI") -eq 0 ]]; then
      isGfalmountExec=0
    else
      echo "Cannot download gfal file"
    fi
  fi
}

# performDownload: handle top-level download execution step
function performDownload {
  startLog inputs_download

  # Create a file to disable watchdog CPU wallclock check
  touch ../DISABLE_WATCHDOG_CPU_WALLCLOCK_CHECK

  # Iterate over each URL in the 'downloads' array
  for download in ${downloads}; do
    # Remove leading and trailing whitespace
    local download="$(echo -e "${download}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    # Process the URL using downloadURI function
    downloadURI "$download"
  done

  # Change permissions of all files in the directory
  chmod 755 -- *
  # Record the timestamp after downloads
  AFTERDOWNLOAD=$(date +%s)

  stopLog inputs_download
}

## exec helpers

# performExec: handle top-level application execution step
function performExec {
  startLog application_execution

  # Add a delay to ensure file creation before proceeding
  echo "BEFORE_EXECUTION_REFERENCE" > BEFORE_EXECUTION_REFERENCE_FILE
  sleep 1

  # Get execution tools
  checkBosh
  local containerType=$(getJsonDepth2 "../$boutiquesFilename" "container-image" "type")
  case "$containerType" in
    docker) checkDocker ;;
    singularity) checkSingularity ;;
  esac

  # Temporary directory for /tmp in containers
  local tmpfolder=$(mktemp -d -p "$PWD" "tmp-XXXXXX")
  mkdir -p "$tmpfolder"

  # Prepare bosh exec flags
  local boshopts=("--stream")
  boshopts+=("--provenance" "{\"jobid\":\"$DIRNAME\"}")
  local imagepath=
  if [ -z "$containersRuntime" ]; then
    # Legacy mode: get imagepath and container runtime from the descriptor
    imagepath=$(getJsonDepth2 "../$boutiquesFilename" "custom" "vip:imagepath")
  else
    # Dynamic resource mode: use $containersRuntime+$containersImagesBasePath
    case "$containersRuntime" in
      docker)
        boshopts+=("--force-docker")
        ;;
      singularity)
        boshopts+=("--force-singularity")
        # get image base name and tag from descriptor
        local image=$(basename "$(getJsonDepth2 "../$boutiquesFilename" "container-image" "image")")
        local imgname=$(echo "$image" | cut -d: -f1)
        local imgtag=$(echo "$image" | cut -d: -f2)
        if [ -z "$imgname" ] || [ -z "$imgtag" ]; then
          error "Invalid image name: '$image'"
          exit 1
        fi
        # set imagepath
        imagepath="$containersImagesBasePath/${imgname}_${imgtag}"
        if ! [ -e "$imagepath" ]; then
          error "Image file not found: $imagepath"
          exit 1
        fi
        ;;
      *)
        error "Invalid containersRuntime: '$containersRuntime'"
        exit 1
        ;;
    esac
  fi
  if [ -n "$imagepath" ]; then
    boshopts+=("--imagepath" "$imagepath")
  fi
  boshopts+=("-v" "$PWD/../cache:$PWD/../cache")
  boshopts+=("-v" "$tmpfolder:/tmp")

  # Execute the command
  info "Running bosh:" "$BOSHEXEC" exec launch "${boshopts[@]}" "../$boutiquesFilename" "../inv/$invocationJsonFilename"
  "$BOSHEXEC" exec launch "${boshopts[@]}" "../$boutiquesFilename" "../inv/$invocationJsonFilename"

  # Check if execution was successful
  if [ $? -ne 0 ]; then
    error "Exiting with return value 6"
    BEFOREUPLOAD=$(date +%s)
    info "Execution time: $((BEFOREUPLOAD - AFTERDOWNLOAD)) seconds"
    stopLog application_execution
    cleanup
    exit 6
  fi

  BEFOREUPLOAD=$(date +%s)
  stopLog application_execution

  info "Execution time was $((BEFOREUPLOAD - AFTERDOWNLOAD))s"
}

## upload helpers

# nSEs: count the number of storage elements in the list
function nSEs {
  local i=0
  for n in ${SELIST}; do
    i=$((i + 1))
  done
  return $i
}

# getAndRemoveSE: get and remove a storage element from the list by its index
function getAndRemoveSE {
  local index="$1"
  local i=0
  local NSE=""
  RESULT=""
  for n in ${SELIST}; do
    if [ "$i" = "${index}" ]; then
      RESULT=$n
      info "result: $RESULT"
    else
      NSE="${NSE} $n"
    fi
    i=$((i + 1))
  done
  SELIST=${NSE}
  return 0
}

# chooseRandomSE: choose a random storage element from the list
function chooseRandomSE {
  nSEs
  local n=$?
  if [ "$n" = "0" ]; then
    info "SE list is empty"
    RESULT=""
  else
    local r=${RANDOM}
    local id=$((r % n))
    getAndRemoveSE ${id}
  fi
}

# uploadLfnFile: upload a file to a logical file name (LFN) path,
# using the Dirac command.
function uploadLfnFile {
  local LFN="$1"
  local FILE="$2"
  local nrep="$3"
  local SELIST="$voDefaultSE"

  # Sanitize LFN:
  # - "lfn:" at the beginning is optional for dirac-dms-* commands,
  #    but does not work as expected with comdirac commands like
  #    dmkdir.
  # - "//" are not accepted, neither by dirac-dms-*, nor by dmkdir.
  LFN=$(echo "$LFN" | sed -r -e 's/^lfn://' -e 's#//#/#g')

  info "getting file size and computing sendReceiveTimeout"
  local size=$(ls -l "$FILE" | awk -F' ' '{print $5}')
  local sendReceiveTimeout=$((${size:-0} / minAvgDownloadThroughput / 1024))
  if [ -z "$sendReceiveTimeout" ] || [ "$sendReceiveTimeout" -le 900 ]; then
    info "sendReceiveTimeout empty or too small, setting it to 900s"
    sendReceiveTimeout=900
  else
    info "sendReceiveTimeout is $sendReceiveTimeout"
  fi

  local totalTimeout=$((timeout + srmTimeout + sendReceiveTimeout))

  local OPTS="-o /Resources/StorageElements/GFAL_TIMEOUT=${totalTimeout}"
  chooseRandomSE
  local DEST=${RESULT}
  local done=0
  while [ "$nrep" -gt "$done" ] && [ "${DEST}" != "" ]; do
    if [ "$done" = "0" ]; then
      local command="dirac-dms-add-file"
      local source=$(hostname)
      dirac-dms-remove-files "$OPTS" "$LFN" &>/dev/null
      local startUpload=$(date +%s)
      (dirac-dms-add-file "$OPTS" "$LFN" "$FILE" "$DEST") &> dirac.log
      local error_code=$?
    else
      local command="dirac-dms-replicate-lfn"
      local startUpload=$(date +%s)
      (dirac-dms-replicate-lfn -d "$OPTS" "$LFN" "$DEST") &> dirac.log
      local error_code=$?

      local source=$(grep "operation 'getFileSize'" dirac.log | tail -1 | sed -r 's/^.* StorageElement (.*) is .*$/\1/')
    fi
    if [ ${error_code} = 0 ]; then
      info "Copy/Replication of ${LFN} to SE ${DEST} worked fine."
      done=$((done + 1))
      local duration=$(($(date +%s) - startUpload))
      info "UploadCommand=${command} Source=${source} Destination=${DEST} Size=${size} Time=${duration}"
      if [ -z "${duration}" ]; then
        info "Missing duration info, printing the whole log file."
        cat dirac.log
      fi
    else
      error "$(cat dirac.log)"
      warning "Copy/Replication of ${LFN} to SE ${DEST} failed"
    fi
    rm dirac.log
    chooseRandomSE
    DEST=${RESULT}
  done
  if [ "${done}" = "0" ]; then
    error "Cannot copy file ${FILE} to lfn ${LFN}"
    error "Exiting with return value 2"
    exit 2
  else
    addToCache "$LFN" "$FILE"
  fi
}

# uploadShanoirFile: upload a file to the Shanoir platform using an API URL
# and authentication token.
# This method is used to upload results of an execution to an upload url.
# URI are of the form of the following example.  A single "/", instead
# of 3, after "shanoir:" is also allowed.
# shanoir:/path/to/folder?upload_url=https://upload/url/&type=File&md5=None
#
# This method depends on refresh token process to refresh the token when it needs
function uploadShanoirFile {
  local URI="$1"
  local FILENAME="$2"

  wait_for_token

  local token=$(cat "$SHANOIR_TOKEN_LOCATION")

  local upload_url=$(echo "$URI" | sed -r 's/^.*[?&]upload_url=([^&]*)(&.*)?$/\1/i')
  local directoryPath=$(echo "$URI" | sed -r 's#^shanoir:/(//)?([^/].*)\?.*$#\2#i')

  local type=$(echo "$URI" | sed -r 's/^.*[?&]type=([^&]*)(&.*)?$/\1/i')
  local md5=$(echo "$URI" | sed -r 's/^.*[?&]md5=([^&]*)(&.*)?$/\1/i')

  COMMAND() {
    (echo -n '{"base64Content": "'; base64 "$FILENAME"; echo '", "type":"'; echo "$type"; echo '", "md5":"'; echo "$md5" ; echo '"}') | curl --output shanoir_upload_response.json --write-out '%{http_code}' --request PUT "$upload_url/$directoryPath/$FILENAME"  --header "Authorization: Bearer $token"  --header "Content-Type: application/carmin+json" --header 'Accept: application/json, text/plain, */*' -d @-
  }

  local status_code=$(COMMAND)
  local exit_code=$?
  echo "uploadShanoirFile, exit code is : ${exit_code}, status code is : ${status_code}"
  echo "uploadShanoirFile, response is : $(cat shanoir_upload_response.json)"
  rm -f shanoir_upload_response.json

  if ! [[ "$exit_code" -eq 0 && "$status_code" -eq 201 ]]; then
    error "error while uploading the file: exit=${exit_code}, status=${status_code}"
    stopRefreshingToken
    exit 1
  fi
}

# uploadGirderFile: upload a file to a Girder server using the Girder client.
# URI are of the form of the following example.  A single "/", instead
# of 3, after "girder:" is also allowed.
# girder:///control_3DT1.nii?apiurl=http://localhost:8080/api/v1&fileId=5ae1a8fc371210092e0d2936&token=TFT2FdxP9hzM7WKsidBjMJMmN69
#
# The code is quite the same as the downloadGirderFile function.  Any
# changes should be done the same in both functions.
function uploadGirderFile {
  local URI="$1"
  local FILENAME="$2"

  local apiUrl=$(echo "$URI" | sed -r 's/^.*[?&]apiurl=([^&]*)(&.*)?$/\1/i')
  local fileId=$(echo "$URI" | sed -r 's/^.*[?&]fileid=([^&]*)(&.*)?$/\1/i')
  local token=$(echo "$URI" | sed -r 's/^.*[?&]token=([^&]*)(&.*)?$/\1/i')

  checkGirderClient

  local COMMLINE="girder-client --api-url ${apiUrl} --token ${token} upload --parent-type folder ${fileId} ./${FILENAME}"
  echo "uploadGirderFile, command line is ${COMMLINE}"
  ${COMMLINE}
  if [ $? != 0 ]; then
    error "Error while uploading girder file"
    error "Exiting with return value 1"
    exit 1
  fi
}

# upload: upload a file to various URI schemes
function upload {
  local RES_DIR_URI="$1"
  local FILENAME="$2"
  local ID="$3"
  local NREP="$4"
  # TODO : this uri log is not perfect as it well append the filename at the end of a
  # complex shanoir or girder uri (after the "?" arguments) which makes no real sense.
  # It makes no harm as it is then parsed and only displayed
  startLog file_upload id="$ID" uri="$RES_DIR_URI/$FILENAME"

  # The pattern must NOT be put between quotation marks.
  if [[ ${RES_DIR_URI} == shanoir:/* ]]; then
    if [ "$REFRESHING_JOB_STARTED" == false ]; then
      refresh_token "$RES_DIR_URI" &
      REFRESH_PID=$!
      REFRESHING_JOB_STARTED=true
    fi
    uploadShanoirFile "$RES_DIR_URI" "$FILENAME"
  elif [[ ${RES_DIR_URI} == girder:/* ]]; then
    uploadGirderFile "$RES_DIR_URI" "$FILENAME"
  elif [[ ${RES_DIR_URI} == file:/* ]]; then
    local RES_DIR=$(echo "$RES_DIR_URI" | sed 's%file://*%/%')
    local DEST="${RES_DIR}/${FILENAME}"

    if [ -e "$DEST" ]; then
      error "Result file already exists: $DEST"
      error "Exiting with return value 1"
      exit 1
    fi

    mv "$FILENAME" "$DEST"
    if [ $? != 0 ]; then
      error "Error while moving result local file."
      error "Exiting with return value 1"
      exit 1
    fi
  else
    # Extract the path part from the uri.
    local RES_DIR_LFN=$(echo "${RES_DIR_URI}" | sed -r 's%^\w+://[^/]*(/[^?]+)(\?.*)?$%\1%')

    uploadLfnFile "$RES_DIR_LFN/$FILENAME" "$PWD/$FILENAME" "$NREP"
  fi

  stopLog file_upload
}

# getProvenanceFilename: get the provenance filename for a given jobid
function getProvenanceFilename {
  local targetjobid="$1"
  # process most recent files first, stop at the first match
  # shellcheck disable=SC2010
  ls -t "$boutiquesProvenanceDir" | grep -v "^descriptor_" |
    while read -r filename; do
      local jobid=$(getJsonDepth2 "$boutiquesProvenanceDir/$filename" "additional-information" "jobid")
      if [ "$jobid" = "$targetjobid" ]; then
        echo "$filename"
        break
      fi
    done
}

# copyProvenanceFile: copy the provenance file to a specified destination
function copyProvenanceFile {
  local dest="$1"
  # $boutiquesProvenanceDir is defined by GASW from the settings file
  if [ ! -d "$boutiquesProvenanceDir" ]; then
    error "Boutiques cache dir $boutiquesProvenanceDir does not exist."
    return 1
  fi
  local provenanceFile=$(getProvenanceFilename "$DIRNAME")
  if [[ -z "$provenanceFile" ]]; then
    error "No provenance found in boutiques cache $boutiquesProvenanceDir"
    return 2
  fi
  # found a provenance file for our job, get the related archived descriptor
  info "Found provenance file $boutiquesProvenanceDir/$provenanceFile"
  local descriptorFile=$(getJsonDepth2 "$boutiquesProvenanceDir/$provenanceFile" "summary" "descriptor-doi")
  # move the provenance file from boutiques cache
  info "Moving it to $dest"
  cp "$boutiquesProvenanceDir/$provenanceFile" "$BASEDIR"
  mv "$boutiquesProvenanceDir/$provenanceFile" "$dest"
  # also cleanup the archived descriptor, to avoid accumulation over time
  if [ -e "$boutiquesProvenanceDir/$descriptorFile" ]; then
    info "Cleaning up descriptor cache $descriptorFile"
    rm -f "$boutiquesProvenanceDir/$descriptorFile"
  fi
}

# performUpload: handle top-level upload step
function performUpload {
  local provenanceFile="$BASEDIR/$DIRNAME.sh.provenance.json"
  copyProvenanceFile "$provenanceFile"

  startLog results_upload

  # Extract the file names and store them in a bash array
  local outputs=$(python <<EOF
import json, sys
with open("$provenanceFile", "r") as file:
    outputs = json.load(file)['public-output']['output-files']
    print(*[f"{k}::{v.get('file-name')}" for k, v in outputs.items()])
EOF
)

  # Remove square brackets from uploadURI
  # (we assume UploadURI will always be a single string)
  uploadURI=$(echo "$uploadURI" | sed 's/^\[//; s/\]$//')

  info "uploadURI : $uploadURI"

  # Check if uploadURI starts with "file:/"
  if [[ "$uploadURI" == file:* ]]; then
    # Get the actual file system path by removing 'file:' prefix
    local dir_path="${uploadURI#file:}"
    # Create the directory if it doesn't exist
    mkdir -p "$dir_path"
    # Check if the directory was successfully created or exists
    if [ -d "$dir_path" ]; then
      echo "Directory '$dir_path' successfully created or already exists."
    else
      echo "Failed to create directory '$dir_path'."
      exit 1 # Exit the script with an error status
    fi
  fi

  # Check if the array is not empty and print the results
  if [ -z "$outputs" ]; then
    echo "No file names found in the output-files section."
  else
    echo "File names found:"
    for output in $outputs; do
      output_id="${output%%::*}"
      file_name="${output#*::}"

      # Execute the upload command
      upload "${uploadURI}" "${file_name}" "$output_id" "$nrep"
    done
  fi

  stopLog results_upload
}

## upload_test helpers

# delete: delete a file on Dirac or locally
function delete {
  local URI="$1"

  startLog file_delete uri="${URI}"

  # The pattern must NOT be put between quotation marks.
  if [[ ${URI} == lfn* ]] || [[ ${URI} == /* ]]; then
    # Extract the path part from the uri, and sanitize it.
    # "//" are not accepted by dirac commands.
    local LFN=$(echo "${URI}" | sed -r -e 's%^\w+://[^/]*(/[^?]+)(\?.*)?$%\1%' -e 's#//#/#g')

    info "Deleting file ${LFN}..."
    dirac-dms-remove-files "${LFN}"
  elif [[ ${URI} == file:/* ]]; then
    local FILENAME=$(echo "$URI" | sed 's%file://*%/%')

    info "Removing local file ${FILENAME}..."
    rm -f "$FILENAME"
  else
    info "delete not supported for ${URI}"
  fi

  stopLog file_delete
}

# testUpload: check that upload works, and remove our traces
function testUpload {
  local filename="uploadTest_$(basename "$PWD")"

  # upload_test is only done on Dirac, to avoid running the whole execution
  # if we don't have a reliable way of uploading the result.
  # This assumes that the "upload" function exits on error.
  if [[ ${uploadURI} == lfn* ]] || [[ $uploadURI == /* ]]; then
    startLog upload_test
    if [ -f "$cacheDir/uploadChecked" ]; then
      info "Skipping upload test (it has already been done by a previous job)"
    else
      echo "test result" > "$filename"
      upload "$uploadURI" "$filename" "" 1
      delete "$uploadURI/$filename"
      rm -f "$filename"
      touch "$cacheDir/uploadChecked"
    fi
    stopLog upload_test
  fi
}

### main

# This section should be kept reasonably small, using functions when needed.

## global init

# Check if directories already exist (In case of LOCAL, the directories already exists. To replicate the LOCAL execution in DIRAC, we create the directories on the remote node)
if [[ ! -d "config" || ! -d "inv" ]]; then
  # Create the directories if they don't already exist
  mkdir -p inv
  mkdir -p config

  # Copy the files to their respective directories after creation
  cp "${configurationFilename}" config/
  info "Copied ${configurationFilename} to config/"
  cp "${invocationJsonFilename}" inv/
  info "Copied ${invocationJsonFilename} to inv/"
else
  info "Directories already exist. Skipping copy."
fi

# Source the configuration file
configurationFile="config/$configurationFilename"
if [ -f "$configurationFile" ]; then
  # here we declare all variables that are expected in $configurationFile:
  # this is useful both as a way to document this interface, and also to avoid
  # having to disable SC2154 "variable referenced but not assigned"
  defaultEnvironment=
  cacheDir=
  cacheFile=
  minAvgDownloadThroughput=
  srmTimeout=
  # shellcheck disable=SC2034
  simulationID= # unused
  timeout=
  boshCVMFSPath=
  voDefaultSE=
  uploadURI=
  downloads=
  boutiquesFilename=
  udockerTag=
  singularityPath=
  containersCVMFSPath=
  containersRuntime=
  containersImagesBasePath=
  nrep=
  boutiquesProvenanceDir=

  # shellcheck disable=SC1090
  source "$configurationFile"
else
  error "Configuration file $configurationFile not found!"
  exit 1
fi

# Register cleanup handler
trap 'echo "trap activation" && stopRefreshingToken | \
if [ "$check_cleanup" = true ]; then \
  echo "cleanup was already executed successfully"; \
else \
  echo "Executing cleanup" && cleanup; \
fi' INT EXIT

# Shanoir token variables
SHANOIR_TOKEN_LOCATION="$cacheDir/SHANOIR_TOKEN.txt"
SHANOIR_REFRESH_TOKEN_LOCATION="$cacheDir/SHANOIR_REFRESH_TOKEN.txt"
REFRESHING_JOB_STARTED=false
REFRESH_PID=""

# Gfal mount flag
isGfalmountExec=1

# Start logging
startLog header
START=$(date +%s)
echo "START date is ${START}"

# Build the custom environment
ENV="$defaultEnvironment"
if test -n "$ENV"; then
  # shellcheck disable=SC2163,SC2086
  export $ENV
fi

# Create execution directory
mkdir "$DIRNAME"
if [ $? -eq 0 ]; then
  echo "cd $DIRNAME"
  cd "$DIRNAME" || exit 7
else
  echo "Unable to create directory $DIRNAME"
  echo "Exiting with return value 7"
  exit 7
fi

# Create cache directory
mkdir -p "$cacheDir"

# Init done
echo "END date is $(date +%s)"

stopLog header

## core actions: download inputs, execute app, upload result

showHostConfig
testUpload
performDownload
performExec
performUpload

## footer and cleanup

startLog footer

cleanup

STOP=$(date +%s)
info "Stop date is ${STOP}"
TOTAL=$((STOP - START))
info "Total running time: $TOTAL seconds"
UPLOAD=$((STOP - BEFOREUPLOAD))
DOWNLOAD=$((AFTERDOWNLOAD - START))
info "Input download time: ${DOWNLOAD} seconds"
info "Execution time: $((BEFOREUPLOAD - AFTERDOWNLOAD)) seconds"
info "Results upload time: ${UPLOAD} seconds"
info "Exiting with return value 0"

stopLog footer
exit 0
