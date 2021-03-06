# Copyright (c) 2018-2020, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

SERVER_LOG=${SERVER_LOG:=./server.log}
SERVER_TIMEOUT=${SERVER_TIMEOUT:=120}
SERVER_LD_PRELOAD=${SERVER_LD_PRELOAD:=""}
MONITOR_FILE_TIMEOUT=${MONITOR_FILE_TIMEOUT:=10}

# Sets WAIT_RET to 0 on success, 1 on failure
function wait_for_file_str() {
    local file="$1"; shift
    local grep_expr="$1"; shift
    local exists_secs="${1:-1}"; shift # wait for file to exist, default 1s
    local wait_time_secs="${1:-5}"; shift # wait for expression in file, default 5s

    WAIT_RET=0

    echo "=== Waiting for '$file'..."
    until test $exists_secs -eq 0 -o -f "$file" ; do sleep 1; ((exists_secs--)); done
    if [ "$exists_secs" == "0" ]; then
        echo "=== Timeout. Unable to find '$file'"
        WAIT_RET=1
        return
    fi

    echo "=== Found $file... waiting for '$grep_expr'"
    (timeout $wait_time_secs tail -F -n+0 "$file" &)
    (timeout $wait_time_secs tail -F -n+0 "$file" &) | grep -q "$grep_expr" && \
        echo "=== Found '$grep_expr'" && return

    echo "=== Timeout $wait_time_secs secs. Unable to find '$grep_expr' in '$file'"
    WAIT_RET=1
}

# Wait until server health endpoint shows ready. Sets WAIT_RET to 0 on
# success, 1 on failure
function wait_for_server_ready() {
    local spid="$1"; shift
    local wait_time_secs="${1:-30}"; shift

    WAIT_RET=0

    local wait_secs=$wait_time_secs
    until test $wait_secs -eq 0 ; do
        if ! kill -0 $spid; then
            echo "=== Server not running."
            WAIT_RET=1
            return
        fi

        sleep 1;

        set +e
        code=`curl -s -w %{http_code} localhost:8000/v2/health/ready`
        set -e
        if [ "$code" == "200" ]; then
            return
        fi

        ((wait_secs--));
    done

    echo "=== Timeout $wait_time_secs secs. Server not ready."
    WAIT_RET=1
}

# Wait until server health endpoint shows live. Sets WAIT_RET to 0 on
# success, 1 on failure
function wait_for_server_live() {
    local spid="$1"; shift
    local wait_time_secs="${1:-30}"; shift

    WAIT_RET=0

    local wait_secs=$wait_time_secs
    until test $wait_secs -eq 0 ; do
        if ! kill -0 $spid; then
            echo "=== Server not running."
            WAIT_RET=1
            return
        fi

        sleep 1;

        set +e
        code=`curl -s -w %{http_code} localhost:8000/v2/health/live`
        set -e
        if [ "$code" == "200" ]; then
            return
        fi

        ((wait_secs--));
    done

    echo "=== Timeout $wait_time_secs secs. Server not live."
    WAIT_RET=1
}

# Wait until all server model states are stable (MODEL_READY or
# MODEL_UNAVAILABLE) or until timeout. Note that server has to be
# live.  If timeout is not specified, only return when all model
# states are stable.
function wait_for_model_stable() {
    local wait_time_secs="${1:--1}"; shift

    local wait_secs=$wait_time_secs
    until test $wait_secs -eq 0 ; do
        sleep 1;

        set +e
        total_count=`curl -s -X POST localhost:8000/v2/repository/index | json_pp | grep "state" | wc -l`
        stable_count=`curl -s -X POST localhost:8000/v2/repository/index | json_pp | grep "READY\|UNAVAILABLE" | wc -l`
        count=$((total_count - stable_count))
        set -e
        if [ "$count" == "0" ]; then
            return
        fi

        ((wait_secs--));
    done

    echo "=== Timeout $wait_time_secs secs. Not all models stable."
}

# Run inference server. Return once server's health endpoint shows
# ready or timeout expires. Sets SERVER_PID to pid of SERVER, or 0 if
# error (including expired timeout)
function run_server () {
    SERVER_PID=0

    if [ -z "$SERVER" ]; then
        echo "=== SERVER must be defined"
        return
    fi

    if [ ! -f "$SERVER" ]; then
        echo "=== $SERVER does not exist"
        return
    fi

    if [ -z "$SERVER_LD_PRELOAD" ]; then
      echo "=== Running $SERVER $SERVER_ARGS"
    else
      echo "=== Running LD_PRELOAD=$SERVER_LD_PRELOAD $SERVER $SERVER_ARGS"
    fi

    LD_PRELOAD=$SERVER_LD_PRELOAD $SERVER $SERVER_ARGS > $SERVER_LOG 2>&1 &
    SERVER_PID=$!

    wait_for_server_ready $SERVER_PID $SERVER_TIMEOUT
    if [ "$WAIT_RET" != "0" ]; then
        kill $SERVER_PID || true
        SERVER_PID=0
    fi
}

# Run inference server. Return once server's health endpoint shows
# live or timeout expires.  Sets SERVER_PID to pid of SERVER, or 0 if
# error (including expired timeout)
function run_server_tolive () {
    SERVER_PID=0

    if [ -z "$SERVER" ]; then
        echo "=== SERVER must be defined"
        return
    fi

    if [ ! -f "$SERVER" ]; then
        echo "=== $SERVER does not exist"
        return
    fi

    if [ -z "$SERVER_LD_PRELOAD" ]; then
      echo "=== Running $SERVER $SERVER_ARGS"
    else
      echo "=== Running LD_PRELOAD=$SERVER_LD_PRELOAD $SERVER $SERVER_ARGS"
    fi

    LD_PRELOAD=$SERVER_LD_PRELOAD $SERVER $SERVER_ARGS > $SERVER_LOG 2>&1 &
    SERVER_PID=$!

    wait_for_server_live $SERVER_PID $SERVER_TIMEOUT
    if [ "$WAIT_RET" != "0" ]; then
        kill $SERVER_PID || true
        SERVER_PID=0
    fi
}

# Run inference server and return immediately. Sets SERVER_PID to pid
# of SERVER, or 0 if error
function run_server_nowait () {
    SERVER_PID=0

    if [ -z "$SERVER" ]; then
        echo "=== SERVER must be defined"
        return
    fi

    if [ ! -f "$SERVER" ]; then
        echo "=== $SERVER does not exist"
        return
    fi

    if [ -z "$SERVER_LD_PRELOAD" ]; then
      echo "=== Running $SERVER $SERVER_ARGS"
    else
      echo "=== Running LD_PRELOAD=$SERVER_LD_PRELOAD $SERVER $SERVER_ARGS"
    fi

    LD_PRELOAD=$SERVER_LD_PRELOAD $SERVER $SERVER_ARGS > $SERVER_LOG 2>&1 &
    SERVER_PID=$!
}

# Run inference server inside a memory management tool like Valgrind/ASAN.
# Return once server's health endpoint shows ready or timeout expires. Sets
# SERVER_PID to pid of SERVER, or 0 if error (including expired timeout)
function run_server_leakcheck () {
    SERVER_PID=0

    if [ -z "$SERVER" ]; then
        echo "=== SERVER must be defined"
        return
    fi

    if [ -z "$LEAKCHECK" ]; then
        echo "=== LEAKCHECK must be defined"
        return
    fi

    if [ ! -f "$SERVER" ]; then
        echo "=== $SERVER does not exist"
        return
    fi

    if [ -z "$SERVER_LD_PRELOAD" ]; then
      echo "=== Running $SERVER $SERVER_ARGS"
    else
      echo "=== Running LD_PRELOAD=$SERVER_LD_PRELOAD $SERVER $SERVER_ARGS"
    fi

    TRITONSERVER_DISABLE_BACKEND_UNLOAD=1 LD_PRELOAD=$SERVER_LD_PRELOAD $LEAKCHECK $LEAKCHECK_ARGS $SERVER $SERVER_ARGS > $SERVER_LOG 2>&1 &
    SERVER_PID=$!

    wait_for_server_ready $SERVER_PID $SERVER_TIMEOUT
    if [ "$WAIT_RET" != "0" ]; then
        kill $SERVER_PID || true
        SERVER_PID=0
    fi
}

# Run nvidia-smi to monitor GPU utilization.
# Writes utilization into MONITOR_LOG. If MONITOR_ID is specified only
# that GPU PCI bus ID is monitored.
# Sets MONITOR_PID to pid of SERVER, or 0 if error
function run_gpu_monitor () {
    MONITOR_PID=0

    MONITOR_ID_ARG=
    if [ ! -z "$MONITOR_ID" ]; then
        MONITOR_ID_ARG="-i $MONITOR_ID"
    fi

    nvidia-smi dmon -s u $MONITOR_ID_ARG -f $MONITOR_LOG &
    MONITOR_PID=$!

    local exists_secs="$MONITOR_FILE_TIMEOUT"
    until test $exists_secs -eq 0 -o -f "$MONITOR_LOG" ; do sleep 1; ((exists_secs--)); done
    if [ "$exists_secs" == "0" ]; then
        echo "=== Timeout. Unable to find '$MONITOR_LOG'"
        kill $MONITOR_PID || true
        MONITOR_PID=0
    fi
}

# Put libidentity.so model file into nop models in the model repository
function create_nop_modelfile () {
    local model_file=$1
    local dest_dir=$2
    for nop_model in `ls $dest_dir | grep "nop_"`; do
        local path=$dest_dir/$nop_model
        mkdir -p $path/1
        cp $model_file $path/1/.
    done
}

# Check Python unittest results.
function check_test_results () {
    local log_file=$1
    local expected_num_tests=$2

    if [[ -z "$expected_num_tests" ]]; then
        echo "=== expected number of tests must be defined"
        return 1
    fi

    num_failures=`cat $log_file | grep -E ".*total.*errors.*failures.*" | tail -n 1 | jq .failures`
    num_tests=`cat $log_file | grep -E ".*total.*errors.*failures.*" | tail -n 1 | jq .total`
    num_errors=`cat $log_file | grep -E ".*total.*errors.*failures.*" | tail -n 1 | jq .errors`

    # Number regular expression
    re='^[0-9]+$'

    if [[ $? -ne 0 ]] || ! [[ $num_failures =~ $re ]] || ! [[ $num_tests =~ $re ]] || \
     ! [[ $num_errors =~ $re ]]; then
        cat $log_file
        echo -e "\n***\n*** Test Failed: unable to parse test results\n***" >> $log_file
        return 1
    fi
    if [[ $num_errors != "0" ]] || [[ $num_failures != "0" ]] || [[ $num_tests -ne $expected_num_tests ]]; then
        cat $log_file
        echo -e "\n***\n*** Test Failed: Expected $expected_num_tests test(s), $num_tests test(s) executed, $num_errors test(s) had error, and $num_failures test(s) failed. \n***" >> $log_file
        return 1
    fi

    return 0
}

# Check the valgrind logs for memory leaks, ignoring known memory leaks
#   * cnmem https://github.com/NVIDIA/cnmem/issues/12
#   * dlopen leak could be due to https://bugs.kde.org/show_bug.cgi?id=358980
#   * Tensorflow::NewSession
#   * PlanBackend::CreateExecutionContexts -> LoadPlan -> createInferRuntime_INTERNAL
#   * OnnxBackend::CreateExecutionContext -> OnnxBackend::Context::ValidateOutputs -> OutputInfos -> InputOutputInfos
#     -> OrtApis::SessionGetOutputName -> StrDup -> onnxruntime::utils::DefaultAlloc
#   * NetDefBackend::CreateExecutionContext -> Caffe2WorkspaceCreate
#   * ModelInferHandler::InferResponseComplete -> TRITONSERVER_ErrorNew
#   *
function check_valgrind_log () {
    local valgrind_log=$1

    leak_records=$(grep "are definitely lost" -A 8 $valgrind_log | awk \
    'BEGIN{RS="--";acc=0} !(/cnmem/||/tensorflow::NewSession/||/dl-init/|| \
    /dlerror/||/LoadPlan/||/libtorch/) \
    {print;acc+=1} END{print acc}')

    num_leaks=$(echo -e "$leak_records" | tail -n1)

    if [ "$num_leaks" != "0" ]; then
        echo -e "$leak_records" | sed '$d'
        echo -e "\n***\n*** Test Failed: $num_leaks memory leaks detected.\n***"
        return 1
    fi

    return 0
}
