#!/usr/bin/env bash
set -e -o pipefail

progname="$(basename "$0")"

# declare and set flags
eval set -- "$(\
	getopt \
		-n "$progname" \
		-o 'hAc:n:w:' \
		-l 'help,all-namespaces,context:,namespace:,query:,tail:,watch:' \
		-- \
		"$@" \
)"

declare -A flag=(
	['watch']='4s'
	['tail']='-1'
)

# parse args
for opt; do
	case "$opt" in
		-A|--all-namespaces)    flag["all-namespaces"]="--all-namespaces"; shift 2 ;;
		-c|--context)           flag["context"]="$1";                      shift 2 ;;
		-h|--help)              flag["help"]="--help";                     shift 2 ;;
		-n|--namespace)         flag["namespace"]="$1";                    shift 2 ;;
		-q|--query)             flag["query"]="$1";                        shift 2 ;;
		-t|--tail)              flag["tail"]="$1";                         shift 2 ;;
		-w|--watch)             flag["watch"]="$1";                        shift 2 ;;
		--) break ;;
	esac
done

# handle case where there are no args
if [ "$1" = "--" ]; then
	shift
fi

if [ -n "${flag["help"]}" ]; then
	echo "Usage: $progname [<resource>] [flags]

kubectl fuzzy finder

Arguments:
  <resource>    The type of resource to fuzzy find (e.g. 'pods').

Flags:
  -h, --help              Show context-sensitive help.
  -w, --watch=DURATION    How often to refresh Kubernetes resources.

fzf
  -q, --query=STRING    The default fzf search text.

kubectl
  -A, --all-namespaces      Show resources from every namespace.
  -c, --context=STRING      The kubeconfig context to use.
  -n, --namespace=STRING    The namespace to fuzzy find in.
      --tail=INTEGER        When showing logs, the number of lines to display."

	exit
fi

kubectl_resource="$1"

watch_enabled=$(( "${flag["watch"]%[a-z]}" > 0 ))

fzf_kubectl_resource="{1}"
if [ -n "${flag["all-namespaces"]}" ]; then
	fzf_kubectl_resource="{2}"
fi

fzf_kubectl_namespace="${flag["namespace"]}"
if [ -n "${flag["all-namespaces"]}" ]; then
	fzf_kubectl_namespace="{1}"
fi

if [ ! -v PAGER ]; then
	echo "$progname could not find an appropriate pager. Please install viddy, bat, or set \$PAGER"
fi

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

fzf_common_opts=(\
	"--ansi" \
	"--with-shell=bash -c"
)

declare -a kubectl_common_opts
kubectl_cmd=kubectl

if hash kubecolor 2>/dev/null; then
	kubectl_cmd=kubecolor
	kubectl_common_opts+=("--force-colors")
fi

if [ -n "${flag["select_namespace"]}" ]; then
	echo "Unimplemented!" >/dev/stderr
	exit
fi

if [ -z "$kubectl_resource" ]; then
	api_resources="$(\
		$kubectl_cmd api-resources \
			"${kubectl_common_opts[@]}" \
			--context="${flag["context"]}" \
			--namespace="${flag["namespace"]}" \
			--output name \
			--no-headers
	)"

	kubectl_resource="$(echo "$api_resources" | fzf "${fzf_common_opts[@]}")"
fi

kubectl_describe=(
	"$kubectl_cmd" "describe" "$resource"
	"${kubectl_common_opts[*]}"
	"--context=${flag["context"]}"
	"--namespace=$fzf_kubectl_namespace"
	"$kubectl_resource"
	"$fzf_kubectl_resource"
)

kubectl_get=(
	"$kubectl_cmd" "get" "$kubectl_resource"
	"${kubectl_common_opts[@]}"
	"--context=${flag["context"]}"
	"--namespace=${flag["namespace"]}"
	"--show-labels"
	"${flag["all-namespaces"]}"
)

kubectl_get_yaml=(
	"$kubectl_cmd" "get" "${kubectl_resource} ${fzf_kubectl_resource}"
	"${kubectl_common_opts[@]}"
	"--context=${flag["context"]}"
	"--namespace=$fzf_kubectl_namespace"
	"--output=yaml"
)

kubectl_logs=(
	"$kubectl_cmd" "logs" "${kubectl_resource}/${fzf_kubectl_resource}"
	"${kubectl_common_opts[@]}"
	"--context=${flag["context"]}"
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
	"${fzf_watch_opts[@]}" \
	--header-lines=1 \
	--delimiter='\s+' \
	--accept-nth="$fzf_kubectl_resource" \
	--bind="ctrl-r:+refresh-preview+reload:${kubectl_get[*]}" \
	--bind='f1:change-preview-window(right,30%|hidden)' \
	--preview="echo 'test'" \
	--preview-label="Help" \
	--preview-window="30%,hidden" \
	--bind="alt-i:execute:$(kzf_live_pager "${kubectl_describe[*]}")" \
	--bind="alt-l:execute:$(kzf_log_pager "${kubectl_logs[@]}")" \
	--bind="alt-y:execute:${kubectl_get_yaml[*]} | $PAGER"
