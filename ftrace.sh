#! /bin/bash
set -E -e -u -o pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

trace_fs=/sys/kernel/debug/tracing
tracing_function=(
	lapic_next_event
)


func_stack_trace=1
timeout_sec=10

function function_trace_cleanup()
{
	echo "function trace cleanup...."
	echo 0 > tracing_on
	echo nop > current_tracer
	echo > set_ftrace_filter
	echo > set_graph_function
	echo 10 > tracing_thresh
}
function graph_trace_cleanup()
{
	echo "graph trace cleanup...."
	echo 0 > tracing_on
	echo nop > current_tracer
	echo > set_graph_function

	echo 1 > options/funcgraph-irqs || true
	echo 0 > max_graph_depth
}


option=${1:-}

trap function_trace_cleanup EXIT
if [ "$option" == "-f" ]; then

	cd $trace_fs
	echo 0 > tracing_on
	echo > trace
	first_write=0
	for f in ${tracing_function[@]}; do
		if ! grep  -q -E "${f}[[:blank:]]|[[:blank:]]${f}\$" /proc/kallsyms; then
			echo "not found [$f] in kallsyms"
			continue
		fi
		if [ $first_write -eq 0 ]; then
			echo $f > set_ftrace_filter
			first_write=1
		else
			echo $f >> set_ftrace_filter
		fi
	done
	echo "========== current trace functions:=========="
	cat set_ftrace_filter
	echo "==========:::::::::::::::::::::::::=========="
	printf "%-10s: %-10s\n" timeout_sec  $timeout_sec
	echo "==========:::::::::::::::::::::::::=========="
	read -p "start tracing? <ctrl-c> to cancel"
	echo 1 > tracing_on
	echo function > current_tracer
	if [ $func_stack_trace -eq 1 ]; then
		echo "enable stack trace"
		echo func_stack_trace  > trace_options
	fi
	timeout --foreground $timeout_sec cat trace_pipe
	# cleanup function will close ftrace
elif [ "$option" == "-g" ]; then
	cd $trace_fs
	echo 0 > tracing_on
	echo > trace
	echo 0 > options/funcgraph-irqs || true
	echo 6 > max_graph_depth

	first_write=0
	for f in ${tracing_function[@]}; do
		if ! grep  -q -E "${f}[[:blank:]]|[[:blank:]]${f}\$" /proc/kallsyms; then
			echo "not found [$f] in kallsyms"
			continue
		fi
		if [ $first_write -eq 0 ]; then
			echo $f > set_graph_function 
			first_write=1
		else
			echo $f >> set_graph_function
		fi
	done
	echo "========== current graph trace functions:  =========="
	cat set_graph_function
	echo "========== ::::::::::::::::::::::::::::::::=========="
	printf "%-10s: %-10s\n" timeout_sec  $timeout_sec
	echo "========== ::::::::::::::::::::::::::::::::=========="
	read -p "start tracing? <ctrl-c> to cancel"
	echo 1 > tracing_on
	echo function_graph > current_tracer
	timeout --foreground $timeout_sec cat trace_pipe
elif [ "$option" == "-h" ]; then
	cd $trace_fs
	echo > trace
	echo 0 > tracing_on
	echo "hwlat" > current_tracer
	echo 1 > tracing_thresh
	echo 1 > tracing_on
	timeout --foreground $timeout_sec cat trace_pipe
else
	echo "function trace: $0 -f"
	echo "hwlat trace: $0 -h"
	echo "function graph: $0 -g"
fi
#
