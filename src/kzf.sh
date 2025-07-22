#!/usr/bin/env bash
set -e -u -o pipefail

progname="$(basename "$0")"

# declare and set flags
eval set -- "$(\
	getopt \
		-n "$progname" \
		-o 'hA::c:n:w:' \
		-l 'help,all-namespaces::,context:,namespace:,select-context::,select-namespace::,select-resource::,tail:,watch:' \
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
		-h|--help)             flag["help"]="--help";                    shift 2 ;;
		-n|--namespace)        flag["namespace"]="$2";                   shift 2 ;;
		   --select-context)   set_boolean_flag "select-context" "$2";   shift 2 ;;
		   --select-namespace) set_boolean_flag "select-namespace" "$2"; shift 2 ;;
		   --select-resource)  set_boolean_flag "select-resource" "$2";  shift 2 ;;
		-t|--tail)             flag["tail"]="$2";                        shift 2 ;;
		-w|--watch)            flag["watch"]="$2";                       shift 2 ;;
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
  -h, --help                Show context-sensitive help.
      --select-context      Fuzzy find the context to view resoruces in.
      --select-namespace    Fuzzy find the namespace to view resoruces in.
      --select-resource     Fuzzy find the resource kind to view.
                            This is the default when <resource> is not given.
  -w, --watch=DURATION      How often to refresh Kubernetes resources.

kubectl
  -A, --all-namespaces      Show resources from every namespace.
  -c, --context=STRING      The kubeconfig context to use.
  -n, --namespace=STRING    The namespace to fuzzy find in.
      --tail=INTEGER        When showing logs, the number of lines to display."

	exit
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

declare -a kubectl_common_opts
kubectl_cmd=kubectl

if hash kubecolor 2>/dev/null; then
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

function select_kubectl_resource {
	api_resources=\
"all
$(\
	"$kubectl_cmd" api-resources \
		"${kubectl_common_opts[@]}" \
		--context="${flag["context"]-}" \
		--namespace="${flag["namespace"]-}" \
		--output name \
		--no-headers
)"

	api_resources="$(echo "$api_resources" | sort)"
	echo "$api_resources" | fzf "${fzf_common_opts[@]}"
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
	"--follow"
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

FZF_DEFAULT_COMMAND="${kubectl_get[*]}" exec fzf \
	"${fzf_common_opts[@]}" \
	"${fzf_kubectl_opts[@]}" \
	"${fzf_watch_opts[@]}" \
	--query="${!fzf_query-}" \
	--accept-nth="$fzf_kubectl_resource" \
	--bind="ctrl-r:+refresh-preview+reload:${kubectl_get[*]}" \
	--bind='f1:change-preview-window(right,30%|hidden)' \
	--preview="echo 'test'" \
	--preview-label="Help" \
	--preview-window="30%,hidden" \
	--bind="alt-i:execute:$(kzf_live_pager "${kubectl_describe[*]}")" \
	--bind="alt-l:execute:$(kzf_log_pager "${kubectl_logs[@]}")" \
	--bind="alt-y:execute:${kubectl_get_yaml[*]} | $PAGER" \
	--bind="alt-c:become:\
		$0 $(fmt_flags select) \
			--select-context \
			$(fmt_kzf_positional_args_for_fzf)
	" \
	--bind="alt-n:become:\
		$0 $(fmt_flags select) \
			--select-namespace \
			$(fmt_kzf_positional_args_for_fzf)
	" \
	--bind="alt-k:become:\
		$0 $(fmt_flags select) \
			--select-resource \
			$(fmt_kzf_positional_args_for_fzf)
	" \
