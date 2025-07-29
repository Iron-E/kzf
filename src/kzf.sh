#!/usr/bin/env bash
set -e -u -o pipefail
shopt -s extglob

progname="$(basename "$0")"

# declare and set flags
eval set -- "$(\
	getopt \
		-n "$progname" \
		-o 'hA::c:n:w:' \
		-l 'help,all-namespaces::,context:,mux:,namespace:,select-context::,select-namespace::,select-resource::,tail:,watch:,zj,zellij' \
		-- \
		"$@" \
)"

declare -A flag=(
	['watch']='4s'
	['tail']='-1'
)

function fmt_flags {
	ignored_prefix="${1-}"
	for key in "${!flag[@]}"; do
		# if removing the ignored prefix from a key makes it different than what
		# the key originally was, skip it
		if [ "${key}" != "${key#"$ignored_prefix"}" ]; then
			continue
		fi

		value="${flag["$key"]}"
		case "$value" in
			"--$key") echo -n " $value" ;; # is a boolean flag
			*) echo -n " --${key}=${value}" ;; # is not a boolean flag
		esac
	done
}

# args:
#
# 1. name of the flag to set
# 2. "true", "false", or no value (defaults to "true")
function set_boolean_flag {
	if [ "$2" = "false" ]; then
		unset 'flag["$1"]'
		return
	fi

	flag["$1"]="--$1"
}

# parse args
for opt in "$@"; do
	case "$opt" in
		-A|--all-namespaces)   set_boolean_flag "all-namespaces" "$2";   shift 2 ;;
		-c|--context)          flag["context"]="$2";                     shift 2 ;;
		   --debug)            set_boolean_flag "debug" "$2";            shift 2 ;;
		-h|--help)             flag["help"]="--help";                    shift 2 ;;
		   --mux)              flag["mux"]="$2";                         shift 2 ;;
		-n|--namespace)        flag["namespace"]="$2";                   shift 2 ;;
		   --select-context)   set_boolean_flag "select-context" "$2";   shift 2 ;;
		   --select-namespace) set_boolean_flag "select-namespace" "$2"; shift 2 ;;
		   --select-resource)  set_boolean_flag "select-resource" "$2";  shift 2 ;;
		-t|--tail)             flag["tail"]="$2";                        shift 2 ;;
		-w|--watch)            flag["watch"]="$2";                       shift 2 ;;
		   --zj|--zellij)      flag["mux"]="zellij";                     shift 2 ;;
		--) break ;;
	esac
done

if [ -n "${flag["help"]-}" ]; then
	echo "Usage: $progname [flags] [<resource> [<query>]]

kubectl fuzzy finder

Arguments:
  <resource>    The type of resource to fuzzy find (e.g. 'pods').
  <query>       The initial fzf query.

Flags:
      --debug               Run in debug mode.
  -h, --help                Show context-sensitive help.
      --mux=STRING          Enable terminal multiplexer integration.
                            One of: zj|zellij
      --select-context      Fuzzy find the context to view resoruces in.
      --select-namespace    Fuzzy find the namespace to view resoruces in.
      --select-resource     Fuzzy find the resource kind to view.
                            This is the default when <resource> is not given.
  -w, --watch=DURATION      How often to refresh Kubernetes resources.

kubectl
  -A, --all-namespaces      Show resources from every namespace.
  -c, --context=STRING      The kubeconfig context to use.
  -n, --namespace=STRING    The namespace to fuzzy find in.
      --tail=INTEGER        When showing logs, the number of lines to display.

zellij
      --zellij    Short for --mux=zellij."

	exit
fi

if [ -n "${flag["debug"]-}" ]; then
	trap 'echo exit due to error on line $LINENO' ERR
fi

# handle case where there are no args
if [ "${1-}" = "--" ]; then
	shift
fi

positional_args=("$@")
kubectl_resource='positional_args[0]'
fzf_query='positional_args[1]'

function fmt_kzf_positional_args_for_fzf {
	echo "${positional_args[*]:0:1} {q} ${positional_args[*]:2}"
}

function fmt_flags_for_fzf {
	echo "$(fmt_flags "$@")" "$(fmt_kzf_positional_args_for_fzf)"
}

watch_enabled=$(( "${flag["watch"]%[a-z]}" > 0 ))

if command -v viddy &>/dev/null; then
	viddy_opts=()
	if [ "$watch_enabled" -eq 1 ]; then
		viddy_opts+=("--interval" "${flag["watch"]}")
	fi

	function kzf_live_pager {
		echo "viddy ${viddy_opts[*]} ${positional_args[*]}"
	}
else
	function kzf_live_pager {
		echo "${positional_args[*]} | $PAGER"
	}
fi

if command -v tspin &>/dev/null; then
	case "$(tspin --version)" in
		*4.*.*) tspin_opt="-c" ;;
		*) tspin_opt="-e" ;;
	esac

	function kzf_log_pager {
		echo tspin "$tspin_opt" "\"${kubectl_logs[*]}\""
	}
else
	function kzf_log_pager {
		echo "${positional_args[*]}"
	}
fi

function with_mux {
	echo "execute:$*"
}

case "${flag["mux"]-}" in
	zj|zellij)
		if command -v zellij &>/dev/null; then
			function with_mux {
				echo "execute-silent:zellij run --close-on-exit -- bash -c '$*'"
			}
		else
			echo "$0: --zellij option given, but zellij waas not found in the \$PATH" >/dev/stderr
		fi
		;;
esac

declare -a kubectl_common_opts
kubectl_cmd=kubectl

if command -v kubecolor &>/dev/null; then
	kubectl_cmd=kubecolor
	kubectl_common_opts+=("--force-colors")
fi

fzf_common_opts=(
	"--ansi"
	"--with-shell=bash -c"
)

fzf_kubectl_opts=(
	'--header-lines=1'
	--delimiter='\s+'
)

if [ -n "${flag["select-context"]-}" ]; then
	contexts="$(
		"$kubectl_cmd" config get-contexts \
			"${kubectl_common_opts[@]}"
	)"

	set +e
	context="$(
		echo "$contexts" \
		| fzf \
			"${fzf_common_opts[@]}" \
			"${fzf_kubectl_opts[@]}" \
			--prompt 'Context> ' \
			--accept-nth=2
	)";

	# shellcheck disable=SC2181
	if [ $? = 0 ]; then
		flag["context"]="$context"
	fi

	set -e
fi

if [ -n "${flag["select-namespace"]-}" ]; then
	namespaces="$(\
		"$kubectl_cmd" get namespaces \
			"${kubectl_common_opts[@]}" \
			--context="${flag["context"]-}"
	)"

	read -r -d '' namespaces <<-EOF || true # read returns 1 on EOF
	$(echo "$namespaces" | head -n1)
	--all-namespaces
	$(echo "$namespaces" | tail -n +2)
EOF

	set +e
	namespace="$(
		echo "$namespaces" \
		| fzf \
			"${fzf_common_opts[@]}" \
			"${fzf_kubectl_opts[@]}" \
			--prompt 'Namespace> ' \
			--accept-nth=1
	)"

	# shellcheck disable=SC2181
	if [ $? = 0 ]; then
		unset 'flag["all-namespaces"]' 'flag["namespace"]'
		case "$namespace" in
			--all-namespaces) set_boolean_flag all-namespaces true ;;
			*) flag["namespace"]="$namespace" ;;
		esac
	fi

	set -e
fi

function kubectl_api_resources {
	set -e -u -o pipefail

	"$kubectl_cmd" api-resources \
		--context="${flag["context"]-}" \
		--namespace="${flag["namespace"]-}" \
		--cached \
		"${@}"
}

function select_kubectl_resource {
	set -e -u -o pipefail

	local api_resources
	api_resources="$(kubectl_api_resources "${kubectl_common_opts[@]}")"

	local api_resources_header
	api_resources_header="$(echo "$api_resources" | head -n1)"

	local api_resources_body
	api_resources_body="$(echo "$api_resources" | tail -n +2)"
	api_resources_body="$(printf "all\n%s" "$api_resources_body" | sort)"

	local selected
	selected="$(\
		printf "%s\n%s" "$api_resources_header" "$api_resources_body" \
		| fzf \
			"${fzf_common_opts[@]}" \
			"${fzf_kubectl_opts[@]}" \
			--accept-nth='{1},{-3}' \
			--prompt="Kind> " \
	)"

	local name="${selected%,*}" # cronjobs,batch/v1 -> cronjobs
	local group="${selected#*,}" # cronjobs,batch/v1 -> batch/v1
	group="${group%%?(/)v*}" # batch/v1 -> batch (see https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html)

	echo "${name}${group:+.$group}"
}

if [ -z "${!kubectl_resource-}" ]; then
	positional_args[0]="$(select_kubectl_resource)"
elif [ -n "${flag["select-resource"]-}" ]; then
	set +e
	new_kubectl_resource="$(select_kubectl_resource)";

	# shellcheck disable=SC2181
	if [ $? = 0 ]; then
		positional_args[0]="$new_kubectl_resource"
	fi

	set -e
fi

fzf_kubectl_resource="{1}"
if [ -n "${flag["all-namespaces"]-}" ]; then
	fzf_kubectl_resource="{2}"
fi

fzf_kubectl_namespace="${flag["namespace"]-}"
if [ -n "${flag["all-namespaces"]-}" ]; then
	fzf_kubectl_namespace="{1}"
fi

kubectl_object_kind="${!kubectl_resource/all/}"
kubectl_delete=(
	"$kubectl_cmd" "delete" "$kubectl_object_kind" "$fzf_kubectl_resource"
	# SEE: https://github.com/kubecolor/kubecolor/issues/201#issuecomment-2508919907
	"${kubectl_common_opts[*]/--force-colors/--plain}"
	"--context=${flag["context"]-}"
	"--namespace=$fzf_kubectl_namespace"
	"--interactive=true" # prompt user
	"--wait=false" # delete asynchronously
)

kubectl_describe=(
	"$kubectl_cmd" "describe" "$kubectl_object_kind" "$fzf_kubectl_resource"
	"${kubectl_common_opts[*]}"
	"--context=${flag["context"]-}"
	"--namespace=$fzf_kubectl_namespace"
)

kubectl_get=(
	"$kubectl_cmd" "get" "${!kubectl_resource}"
	"${kubectl_common_opts[@]}"
	"--context=${flag["context"]-}"
	"--namespace=${flag["namespace"]-}"
	"--show-labels"
	"${flag["all-namespaces"]-}"
)

kubectl_get_yaml=(
	"$kubectl_cmd" "get" "$kubectl_object_kind" "$fzf_kubectl_resource"
	"${kubectl_common_opts[@]}"
	"--context=${flag["context"]-}"
	"--namespace=$fzf_kubectl_namespace"
	"--output=yaml"
)

kubectl_logs=(
	"$kubectl_cmd" "logs" "${kubectl_object_kind:+${kubectl_object_kind}/}${fzf_kubectl_resource}"
	"${kubectl_common_opts[@]}"
	"--context=${flag["context"]-}"
	"--namespace=$fzf_kubectl_namespace"
	"--follow"
)

kubectl_restart=(
	"$kubectl_cmd" "rollout" "restart" "$kubectl_object_kind" "$fzf_kubectl_resource"
	"${kubectl_common_opts[*]}"
	"--context=${flag["context"]-}"
	"--namespace=$fzf_kubectl_namespace"
)

fzf_watch_opts=()
if [ "$watch_enabled" -eq 1 ]; then
	fzf_watch_opts+=(
		'--listen'
		"--bind=start:+bg-transform:
			while true; do
				sleep ${flag["watch"]@Q}
				curl -X POST \"localhost:\$FZF_PORT\" -d 'reload:${kubectl_get[*]}' --silent
			done &
		"
	)
fi

case "${!kubectl_resource}" in
	*.*)
		kubectl_resource_name="${!kubectl_resource%.*}"
		kubectl_resource_group="${!kubectl_resource#*.}"
		;;
	*)
		kubectl_resource_name="${!kubectl_resource}"
		kubectl_resource_group=
		;;
esac

kubectl_resource_kind="$(\
	kubectl_api_resources --api-group="${kubectl_resource_group}" \
	| grep -w "${kubectl_resource_name}" || echo "All" \
)"

kubectl_resource_kind="${kubectl_resource_kind##* }"

let_user_read_error='read -rp "press enter to continue "'

FZF_DEFAULT_COMMAND="${kubectl_get[*]}" exec fzf \
	"${fzf_common_opts[@]}" \
	"${fzf_kubectl_opts[@]}" \
	"${fzf_watch_opts[@]}" \
	--prompt "${kubectl_resource_kind}> " \
	--query="${!fzf_query-}" \
	--accept-nth="$fzf_kubectl_resource" \
	--bind="ctrl-r:+refresh-preview+reload:${kubectl_get[*]}" \
	--bind="alt-d:$(with_mux "${kubectl_delete[*]}")" \
	--bind="alt-i:$(with_mux "$(kzf_live_pager "${kubectl_describe[*]}")")" \
	--bind="alt-l:$(with_mux "$(kzf_log_pager "${kubectl_logs[@]}")")" \
	--bind="alt-r:$(with_mux "${kubectl_restart[*]} || $let_user_read_error")" \
	--bind="alt-y:$(with_mux "${kubectl_get_yaml[*]} | $PAGER")" \
	--bind="alt-c:become:$0 $(fmt_flags_for_fzf select) --select-context" \
	--bind="alt-n:become:$0 $(fmt_flags_for_fzf select) --select-namespace" \
	--bind="alt-k:become:$0 $(fmt_flags_for_fzf select) --select-resource" \
	--ghost='Press F1 for help' \
	--preview-window="hidden" \
	--bind='f1:change-preview-window(right,30%|hidden)' \
	--preview-label="Help" \
	--preview="cat <<-EOF
		alt-c    change active context
		alt-d    delete resource (with confirmation)
		alt-i    describe resource (mnemonic: inspect)
		alt-k    change active resource kind
		alt-l    show resource logs
		alt-n    change active namespace
		alt-r    restart resource
		alt-y    show manifest (mnemonic: YAML)
EOF" \
