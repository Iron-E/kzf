#!/usr/bin/env bash
set -e -u -o pipefail

progname="$(basename "$0")"

# declare and set flags
eval set -- "$(\
	getopt \
		-n "$progname" \
		-o 'hA::c:n:w:' \
		-l 'help,all-namespaces::,context:,namespace:,select-context::,select-namespace::,tail:,watch:' \
		-- \
		"$@" \
)"

declare -A flag=(
	['watch']='4s'
	['tail']='-1'
)

function fmt_flags {
	for key in "${!flag[@]}"; do
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
		-t|--tail)             flag["tail"]="$2";                        shift 2 ;;
		-w|--watch)            flag["watch"]="$2";                       shift 2 ;;
		--) break ;;
	esac
done

# handle case where there are no args
if [ "${1-}" = "--" ]; then
	shift
fi

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
  -w, --watch=DURATION      How often to refresh Kubernetes resources.

kubectl
  -A, --all-namespaces      Show resources from every namespace.
  -c, --context=STRING      The kubeconfig context to use.
  -n, --namespace=STRING    The namespace to fuzzy find in.
      --tail=INTEGER        When showing logs, the number of lines to display."

	exit
fi

kubectl_resource="${1-}"
fzf_query="${2-}"

watch_enabled=$(( "${flag["watch"]%[a-z]}" > 0 ))

if command -v viddy &>/dev/null; then
	viddy_opts=()
	if [ "$watch_enabled" -eq 1 ]; then
		viddy_opts+=("--interval" "${flag["watch"]}")
	fi

	function kzf_live_pager {
		echo "viddy ${viddy_opts[*]} $*"
	}
else
	function kzf_live_pager {
		echo "$* | $PAGER"
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
		echo "$*"
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

	context="$(\
		echo "$contexts" \
		| fzf \
			"${fzf_common_opts[@]}" \
			"${fzf_kubectl_opts[@]}" \
			--accept-nth=2
	)"

	flag["context"]="$context"
fi

if [ -n "${flag["select-namespace"]-}" ]; then
	unset 'flag["all-namespaces"]' 'flag["namespace"]'

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

	namespace="$(\
		echo "$namespaces" \
		| fzf \
			"${fzf_common_opts[@]}" \
			"${fzf_kubectl_opts[@]}" \
			--accept-nth=1
	)"

	case "$namespace" in
		--all-namespaces) set_boolean_flag all-namespaces true ;;
		*) flag["namespace"]="$namespace" ;;
	esac
fi

if [ -z "$kubectl_resource" ]; then
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

	kubectl_resource="$(echo "$api_resources" | fzf "${fzf_common_opts[@]}")"
	set -- "$kubectl_resource" "${@:2}" # update positional args
fi

fzf_kubectl_resource="{1}"
if [ -n "${flag["all-namespaces"]-}" ]; then
	fzf_kubectl_resource="{2}"
fi

fzf_kubectl_namespace="${flag["namespace"]-}"
if [ -n "${flag["all-namespaces"]-}" ]; then
	fzf_kubectl_namespace="{1}"
fi

kubectl_object_kind="${kubectl_resource/all/}"
kubectl_describe=(
	"$kubectl_cmd" "describe" "$kubectl_object_kind" "$fzf_kubectl_resource"
	"${kubectl_common_opts[*]}"
	"--context=${flag["context"]-}"
	"--namespace=$fzf_kubectl_namespace"
)

kubectl_get=(
	"$kubectl_cmd" "get" "$kubectl_resource"
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

FZF_DEFAULT_COMMAND="${kubectl_get[*]}" fzf \
	"${fzf_common_opts[@]}" \
	"${fzf_kubectl_opts[@]}" \
	"${fzf_watch_opts[@]}" \
	--query="$fzf_query" \
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
		$0 $(fmt_flags) \
			--select-context \
			--select-namespace=false \
			${*:1:1} \
			{q} \
			${*:3} \
	" \
	--bind="alt-n:become:\
		$0 $(fmt_flags) \
			--select-context=false \
			--select-namespace \
			${*:1:1} \
			{q} \
			${*:3} \
	" \
	--bind="alt-k:become:\
		$0 $(fmt_flags) \
			--select-context=false \
			--select-namespace=false \
			'' \
			{q} \
			${*:3} \
	" \
