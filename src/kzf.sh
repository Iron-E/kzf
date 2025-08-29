#!/usr/bin/env bash
set -e -u -o pipefail
shopt -s extglob

progname="$(basename "$0")"

# declare and set flags
eval set -- "$(\
	getopt \
		-n "$progname" \
		-o 'A::c:hn:w:' \
		-l 'all-namespaces::,context:,debug::,help,kubecolor::,mux:,namespace:,pager:,select-context::,select-namespace::,select-resource::,tail:,tspin::,viddy::,watch:,zellij,zj' \
		-- \
		"$@" \
)"

function flag_from_env {
	if [ "${!1:-}" = "true" ] || [ "${2:-}" = "true" ]; then
		# KZF_FOO_BAR -> FOO_BAR
		: "${1#*_}"
		# FOO_BAR -> foo_bar
		: "${_,,}"
		# foo_bar foo-bar
		: "${_//_/-}"
		echo "--${_}"
	fi
}

declare -A default_option=(
	['context']="${KZF_CONTEXT:-}"
	['mux']="${KZF_MUX:-}"
	['namespace']="${KZF_NAMESPACE:-}"
	['pager']="${KZF_PAGER:-${PAGER:-less}}"
	['tail']="${KZF_TAIL:-'-1'}"
	['watch']="${KZF_WATCH:-4s}"
)

declare -A option
for key in "${!default_option[@]}"; do
	option["${key}"]="${default_option["$key"]}"
done

declare -A default_flag=(
	['all-namespaces']="$(flag_from_env KZF_ALL_NAMESPACES)"
	['debug']="$(flag_from_env KZF_DEBUG)"
	['kubecolor']="$(flag_from_env KZF_KUBECOLOR true)"
	['select-context']="$(flag_from_env KZF_SELECT_CONTEXT)"
	['select-namespace']="$(flag_from_env KZF_SELECT_NAMESPACE)"
	['select-resource']="$(flag_from_env KZF_SELECT_RESOURCE)"
	['tspin']="$(flag_from_env KZF_TSPIN true)"
	['viddy']="$(flag_from_env KZF_VIDDY true)"
)

declare -A flag
for key in "${!default_flag[@]}"; do
	flag["${key}"]="${default_flag["$key"]}"
done

function fmt_options_and_flags {
	ignored_prefix="${1:-}"

	local value
	for key in "${!default_flag[@]}"; do
		# if removing the ignored prefix from a key makes it different than what
		# the key originally was, skip it
		if [ "${key}" != "${key#"$ignored_prefix"}" ]; then
			continue
		fi

		# --foo=false unsets the var
		if [ ! -v "flag[${key}]" ]; then
			echo -n " --${key}=false"
			continue
		fi

		value="${flag["$key"]}"
		case "$value" in
			"${default_flag["$key"]:-}") ;; # omit, is a default
			"--$key") echo -n " $value" ;; # set
		esac
	done

	for key in "${!default_option[@]}"; do
		# if removing the ignored prefix from a key makes it different than what
		# the key originally was, skip it
		if [ "${key}" != "${key#"$ignored_prefix"}" ]; then
			continue
		fi

		value="${option["$key"]}"
		case "$value" in
			"${default_option["$key"]:-}") ;; # omit, is a default
			*) echo -n " --${key}=${value@Q}" ;; # set
		esac
	done
}

# args:
#
# 1. name of the flag to set
# 2. "true", "false", or no value (defaults to "true")
function set_flag {
	if [ "$2" = "false" ]; then
		unset 'flag["$1"]'
		return
	fi

	flag["$1"]="--$1"
}

# parse args
for opt in "$@"; do
	case "$opt" in
		-A|--all-namespaces)   set_flag "all-namespaces" "$2";   shift 2 ;;
		-c|--context)          option["context"]="$2";           shift 2 ;;
		   --debug)            set_flag "debug" "$2";            shift 2 ;;
			--kubecolor)        set_flag "kubecolor" "$2";        shift 2 ;;
		-h|--help)             option["help"]="--help";          shift 2 ;;
		   --mux)              option["mux"]="$2";               shift 2 ;;
		-n|--namespace)        option["namespace"]="$2";         shift 2 ;;
		   --pager)            option["pager"]="$2";             shift 2 ;;
		   --select-context)   set_flag "select-context" "$2";   shift 2 ;;
		   --select-namespace) set_flag "select-namespace" "$2"; shift 2 ;;
		   --select-resource)  set_flag "select-resource" "$2";  shift 2 ;;
		-t|--tail)             option["tail"]="$2";              shift 2 ;;
			--tspin)            set_flag "tspin" "$2";            shift 2 ;;
			--viddy)            set_flag "viddy" "$2";            shift 2 ;;
		-w|--watch)            option["watch"]="$2";             shift 2 ;;
		   --zj|--zellij)      option["mux"]="zellij";           shift 2 ;;
		--) break ;;
	esac
done

if [ -n "${option["help"]:-}" ]; then
	cat <<'EOF'
Usage: $progname [flags] [<resource> [<query>]]

kubectl fuzzy finder

Arguments:
  <resource>    The type of resource to fuzzy find (e.g. 'pods').
  <query>       The initial fzf query.

Flags:
      --debug[=BOOLEAN]               Run in debug mode.
                                      (default: $KZF_DEBUG)

  -h, --help                          Show this help text.

      --mux=STRING                    Enable terminal multiplexer integration.
                                      One of: zj|zellij
                                      (default: $KZF_MUX)

      --pager=STRING                  The command to use when paging the output of certain kubectl commands.

                                      If you use an integration with colored output (e.g. kubecolor),
                                      make sure this pager is configured to interpret those colors
                                      (e.g. --pager='less -R').

                                      (default: ${KZF_PAGER:-${PAGER:-less}})

      --select-context[=BOOLEAN]      Fuzzy find the context to view resoruces in.
                                      (default: $KZF_SELECT_CONTEXT)

      --select-namespace[=BOOLEAN]    Fuzzy find the namespace to view resoruces in.
                                      (default: $KZF_SELECT_NAMESPACE)

      --select-resource[=BOOLEAN]     Fuzzy find the resource kind to view.
                                      This is the default when <resource> is not given.
                                      (default: $KZF_SELECT_RESOURCE)

  -w, --watch=DURATION                How often to refresh Kubernetes resources.
                                      (default: ${KZF_WATCH:-4s})

kubectl
  -A, --all-namespaces[=BOOLEAN]    Show resources from every namespace.
                                    (default: $KZF_ALL_NAMESPACES)

  -c, --context=STRING              The kubeconfig context to use.
                                    (default: $KZF_CONTEXT)

      --kubecolor[=BOOLEAN]         Whether to enable the kubecolor integration.
                                    This flag is ignored if kubecolor is not installed.

                                    See: https://github.com/kubecolor/kubecolor
                                    (default: ${KZF_KUBECOLOR:-true})

  -n, --namespace=STRING            The namespace to fuzzy find in.
                                    (default: $KZF_NAMESPACE)

      --tail=INTEGER                When showing logs, the number of lines to display.
                                    (default: ${KZF_TAIL:-'-1'})

tailspin
      --tspin[=BOOLEAN]    Whether to enable the tailspin integration.
                           This flag is ignored if tailspin is not installed.

                           See: https://github.com/bensadeh/tailspin
                           (default: ${KZF_TSPIN:-true})

viddy
      --viddy[=BOOLEAN]    Whether to enable the viddy integration.
                           This flag is ignored if viddy is not installed.

                           See: https://github.com/sachaos/viddy
                           (default: ${KZF_VIDDY:-true})

zellij
      --zj        Short for --zellij.
      --zellij    Short for --mux=zellij.
EOF

	exit
fi

if [ -n "${flag["debug"]:-}" ]; then
	trap 'echo exit due to error on line $LINENO' ERR
fi

# handle case where there are no args
if [ "${1:-}" = "--" ]; then
	shift
fi

positional_args=("$@")
kubectl_resource='positional_args[0]'
fzf_query='positional_args[1]'

function fmt_kzf_positional_args_for_fzf {
	echo "${positional_args[@]:0:1}" '{q}' "${positional_args[@]:2}"
}

function fmt_flags_for_fzf {
	echo "$(fmt_options_and_flags "$@")" "$(fmt_kzf_positional_args_for_fzf)"
}

watch_enabled=$(( "${option["watch"]%[a-z]}" > 0 ))

if [ -n "${flag["viddy"]:-}" ] && command -v viddy &>/dev/null; then
	viddy_opts=()
	if [ "$watch_enabled" -eq 1 ]; then
		viddy_opts+=("--interval" "${option["watch"]}")
	fi

	function kzf_live_pager {
		echo viddy "${viddy_opts[@]}" "$@"
	}
else
	function kzf_live_pager {
		echo "$@" '|' "${option["pager"]}"
	}
fi

if [ -n "${flag["tspin"]:-}" ] && command -v tspin &>/dev/null; then
	case "$(tspin --version)" in
		*4.*.*) tspin_opt="-c" ;;
		*) tspin_opt="-e" ;;
	esac

	function kzf_log_pager {
		echo tspin "$tspin_opt" "\"$*\""
	}
else
	function kzf_log_pager {
		echo "$@"
	}
fi

function with_mux {
	cmd="$*"
	if [ -z "$cmd" ]; then
		read -r -d '' cmd || true
	fi

	echo "execute:$cmd"
}

case "${option["mux"]:-}" in
	zj|zellij)
		if command -v zellij &>/dev/null; then
			function with_mux {
				cmd="$*"
				if [ -z "$cmd" ]; then
					read -r -d '' cmd || true
				fi

				echo "execute-silent:zellij run --close-on-exit -- bash -c '$cmd'"
			}
		else
			echo "$0: --zellij option given, but zellij waas not found in the \$PATH" >/dev/stderr
		fi
		;;
esac

declare -a kubectl_common_opts
kubectl_cmd=kubectl

if [ -n "${flag["kubecolor"]:-}" ] && command -v kubecolor &>/dev/null; then
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

function fzf_info_command {
	# shellcheck disable=SC2016
	echo -n echo '"(${FZF_INFO})'
	echo -n "${option["context"]:+ ctx:${option["context"]}}"
	echo -n "${option["namespace"]:+ ns:${option["namespace"]}}"
	echo -n "${flag["all-namespaces"]:+ ns:*}"
	echo -n '"'
}

if [ -n "${flag["select-context"]:-}" ]; then
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
			--prompt 'Selcct Context> ' \
			--accept-nth=2
	)";

	# shellcheck disable=SC2181
	if [ $? = 0 ]; then
		option["context"]="$context"
	fi

	set -e
fi

if [ -n "${flag["select-namespace"]:-}" ]; then
	namespaces="$(\
		"$kubectl_cmd" get namespaces \
			"${kubectl_common_opts[@]}" \
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
			--prompt 'Select Namespace> ' \
			--info-command="echo \"(\$FZF_INFO) ${option["context"]+ ctx:${option["context"]}}\"" \
			--accept-nth=1
	)"

	# shellcheck disable=SC2181
	if [ $? = 0 ]; then
		unset 'flag["all-namespaces"]' 'flag["namespace"]'
		case "$namespace" in
			--all-namespaces) set_flag all-namespaces true ;;
			*) option["namespace"]="$namespace" ;;
		esac
	fi

	set -e
fi

kubectl_common_opts+=("--context=${option["context"]:-}")

function kubectl_api_resources {
	set -e -u -o pipefail

	"$kubectl_cmd" api-resources \
		--namespace="${option["namespace"]:-}" \
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
	api_resources_body="$(printf "all\n%s" "$api_resources_body")"

	local selected
	selected="$(\
		printf "%s\n%s" "$api_resources_header" "$api_resources_body" \
		| fzf \
			"${fzf_common_opts[@]}" \
			"${fzf_kubectl_opts[@]}" \
			--accept-nth='{1},{-3}' \
			--prompt="Select Kind> " \
			--info-command="$(fzf_info_command)" \
	)"

	local name="${selected%,*}" # cronjobs,batch/v1 -> cronjobs
	local group="${selected#*,}" # cronjobs,batch/v1 -> batch/v1
	group="${group%%?(/)v*}" # batch/v1 -> batch (see https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html)

	echo "${name}${group:+.$group}"
}

if [ -z "${!kubectl_resource:-}" ]; then
	positional_args[0]="$(select_kubectl_resource)"
elif [ -n "${flag["select-resource"]:-}" ]; then
	set +e
	new_kubectl_resource="$(select_kubectl_resource)";

	# shellcheck disable=SC2181
	if [ $? = 0 ]; then
		positional_args[0]="$new_kubectl_resource"
	fi

	set -e
fi

fzf_kubectl_resource="{1}"
if [ -n "${flag["all-namespaces"]:-}" ]; then
	fzf_kubectl_resource="{2}"
fi

fzf_kubectl_namespace="${option["namespace"]:-}"
if [ -n "${flag["all-namespaces"]:-}" ]; then
	fzf_kubectl_namespace="{1}"
fi

kubectl_object_kind="${!kubectl_resource/all/}"
kubectl_binding_opts=(
	"${kubectl_object_kind:+${kubectl_object_kind}/}${fzf_kubectl_resource}"
	"${kubectl_common_opts[@]}"
	"--namespace=$fzf_kubectl_namespace"
)

kubectl_attach=("$kubectl_cmd" "attach" "${kubectl_binding_opts[@]}")

kubectl_delete=(
	"$kubectl_cmd" "delete"
	# SEE: https://github.com/kubecolor/kubecolor/issues/201#issuecomment-2508919907
	"${kubectl_binding_opts[@]/--force-colors/--plain}"
	"--interactive=true" # prompt user
	"--wait=false" # delete asynchronously
)

kubectl_describe=("$kubectl_cmd" "describe" "${kubectl_binding_opts[@]}")
kubectl_exec=("$kubectl_cmd" "exec" "${kubectl_binding_opts[@]}" "-it")

read_kubectl_exec_cmd=("read" "-r" "-p" "Command> " "-e" "cmd")

kubectl_get=(
	"$kubectl_cmd" "get" "${!kubectl_resource}"
	"${kubectl_common_opts[@]}"
	"${flag["all-namespaces"]:-"--namespace=${option["namespace"]:-}"}"
	"--show-labels"
)

kubectl_get_yaml=("$kubectl_cmd" "get" "${kubectl_binding_opts[@]}" "--output=yaml")
kubectl_logs=("$kubectl_cmd" "logs" "${kubectl_binding_opts[@]}" "--follow")
kubectl_restart=("$kubectl_cmd" "rollout" "restart" "${kubectl_binding_opts[@]}")

let_user_read_error='read -rp "press enter to continue "'
read -r -d '' kubectl_select_container <<-EOF || true
	set -euo pipefail
	shopt -s extglob lastpipe
	case "${kubectl_object_kind}" in
		deploy?(ment?(s?(.apps)))|rs|replicaset?(s?(.apps))|job?(s?(.batch)))
			jsonpath='{.spec.template.spec.containers[*].name}'
			;;
		cj|cronjob?(s?(.batch)))
			jsonpath='{.spec.jobTemplate.spec.template.spec.containers[*].name}'
			;;
		po?(d?(s)))
			jsonpath='{.spec.containers[*].name}'
			;;
		*)
			echo unsupported kind: '(${!kubectl_resource})'
			$let_user_read_error
			;;
	esac

	containers="\$(
		${kubectl_get_yaml[*]/--output=yaml/} \
			--output jsonpath="\${jsonpath}" \
		| tr ' ' $'\n'
	)"

	if [ -z "\$containers" ]; then
		echo $kubectl_object_kind $fzf_kubectl_resource has no containers
		$let_user_read_error
		exit
	fi

	echo "\${containers}" \
	| fzf \
		${fzf_common_opts[*]@Q} \
		--prompt 'Selcct Container> ' \
		--info-command='$(fzf_info_command)' \
		--preview-window='right,30%'
EOF

fzf_watch_opts=()
if [ "$watch_enabled" -eq 1 ]; then
	fzf_watch_opts+=(
		'--listen'
		"--bind=start:+bg-transform:
			while true; do
				sleep ${option["watch"]@Q}
				curl -X POST \"localhost:\$FZF_PORT\" -d 'reload-sync:${kubectl_get[*]}' --silent
			done &
		"
	)
fi

case "${!kubectl_resource}" in
	all)
		kubectl_resource_kind=All
		;;
	*.*)
		kubectl_resource_name="${!kubectl_resource%%.*}"
		kubectl_resource_group="${!kubectl_resource#*.}"

		# explanation of regex.
		# sample output of api-resources:
		#
		# ```
		# NAME                                SHORTNAMES   APIVERSION                        NAMESPACED   KIND
		# storageclasses                      sc           storage.k8s.io/v1                 false        StorageClass
		# ```
		#
		# We want to match lines based on NAME, SHORTNAMES, or KIND.
		# This is because valid user input could be one of (case insensitive):
		#
		# - sc[.stor[age.k8s.io]]
		# - storageclass[.stor[age.k8s.io]]
		# - storageclasses[.stor[age.k8s.io]]
		#
		# To do this, it is necessary to match on one of:
		#
		# 1. (NAME|SHORTNAMES)
		match_name="${kubectl_resource_name}\s+"
		match_any_name="\w+\s+"

		# neovim parses (( as an arithmetic expression without single qutoes, so this line has to get a little funky
		match_shortname='((\w+,)*'"${kubectl_resource_name}"'(,\w+)*\s+)'
		match_any_shortname="\S*\s*"

		match_group_name="${kubectl_resource_group}\S*\s+"

		match_any_kind="\w+"
		match_any_namespaced="\w+\s+"

		match_on_name_or_shortname="^($match_name$match_any_shortname|$match_any_name$match_shortname)$match_group_name$match_any_namespaced$match_any_kind\$"
		match_on_kind="^$match_any_name$match_any_shortname$match_group_name$match_any_namespaced$kubectl_resource_name\$"

		kubectl_resource_kind="$(
			kubectl_api_resources "${kubectl_common_opts[@]/--force-colors/--plain}" \
			| grep -iE "$match_on_name_or_shortname|$match_on_kind" \
			| head -n 1
		)"
		;;
	*)
		kubectl_resource_kind="$(
			kubectl_api_resources \
			| grep -iE "(^|,|\s)${!kubectl_resource}(\s|,|$)" \
			| head -n 1
		)"
		;;
esac

kubectl_resource_kind="${kubectl_resource_kind##* }"

export -f kzf_log_pager
export tspin_opt

# shellcheck disable=SC2016
FZF_DEFAULT_COMMAND="${kubectl_get[*]}" exec fzf \
	"${fzf_common_opts[@]}" \
	"${fzf_kubectl_opts[@]}" \
	"${fzf_watch_opts[@]}" \
	--prompt "${kubectl_resource_kind}> " \
	--info-command="$(fzf_info_command)" \
	--query="${!fzf_query:-}" \
	--accept-nth="$fzf_kubectl_resource" \
	--bind='change:transform-search:
		echo -n {q}
		if [ "$FZF_PROMPT" = "All> " ] && [ -n {q} ]; then
			echo -n " !LABELS"
		fi
	' \
	--bind="ctrl-r:+reload-sync:${kubectl_get[*]}" \
	--bind="alt-a:$(with_mux "${kubectl_attach[*]}")" \
	--bind="alt-A:$(cat <<-EOF | with_mux
		${kubectl_select_container} \
			--expect='alt-t' \
			--preview='cat <<-EOP
				enter     attach
				alt-t     attach w/ tty
			EOP' \
		| readarray -t selected

		declare -a extra_opts
		case "\${selected[0]}" in
			alt-t) extra_opts+=("-i" "-t") ;;
			*) ;;
		esac

		${kubectl_attach[*]@Q} "\${extra_opts[@]}" --container="\${selected[1]}"
	EOF
	)" \
	--bind="alt-d:$(with_mux "${kubectl_delete[*]}")" \
	--bind="alt-D:$(with_mux "${kubectl_delete[*]}" --now)" \
	--bind="alt-i:$(with_mux "$(kzf_live_pager "${kubectl_describe[*]}")")" \
	--bind="alt-l:$(with_mux "$(kzf_log_pager "${kubectl_logs[@]}")")" \
	--bind="alt-L:$(cat <<-EOF | with_mux
		${kubectl_select_container} \
			--expect='alt-a,alt-c,alt-p' \
			--preview='cat <<-EOP
				enter        pick container
				alt-p        pick container in all pods (e.g. for Deployment)
				alt-c        pick all containers
				alt-a        pick all containers in all pods (e.g. for Deployment)
			EOP' \
		| readarray -t selected

		declare -a extra_opts
		case "\${selected[0]}" in
			alt-a) extra_opts+=("--all-containers" "--all-pods") ;;
			alt-c) extra_opts+=("--all-containers") ;;
			alt-p) extra_opts+=("--all-pods") ;;
			*) extra_opts+=("--container=\${selected[1]}") ;;
		esac

		eval "\$(kzf_log_pager "${kubectl_logs[@]}" "\${extra_opts[@]}")"
	EOF
	)" \
	--bind="alt-r:$(with_mux "${kubectl_restart[*]} || $let_user_read_error")" \
	--bind="alt-x:$(cat <<-EOF | with_mux
		${read_kubectl_exec_cmd[*]@Q}
		eval ${kubectl_exec[*]@Q} -it -- \$cmd \
		|| $let_user_read_error
	EOF
	)" \
	--bind="alt-X:$(cat <<-EOF | with_mux
		${kubectl_select_container} \
			--expect='alt-t' \
			--preview='cat <<-EOP
				enter     attach
				alt-t     attach w/ tty
			EOP' \
		| readarray -t selected

		declare -a extra_opts
		case "\${selected[0]}" in
			alt-t) extra_opts+=("-i" "-t") ;;
			*) ;;
		esac

		${read_kubectl_exec_cmd[*]@Q}
		eval ${kubectl_exec[*]@Q} "\${extra_opts[@]}" --container="\${selected[1]}" -- \$cmd \
		|| $let_user_read_error
	EOF
	)" \
	--bind="alt-y:$(with_mux "${kubectl_get_yaml[*]@Q} | ${option["pager"]}")" \
	--bind="alt-c:become:$0 $(fmt_flags_for_fzf select) --select-context" \
	--bind="alt-n:become:$0 $(fmt_flags_for_fzf select) --select-namespace" \
	--bind="alt-k:become:$0 $(fmt_flags_for_fzf select) --select-resource" \
	--ghost='Press F1 for help' \
	--preview-window="hidden" \
	--bind='f1:change-preview-window(right,30%|hidden)' \
	--preview-label="Help" \
	--preview="cat <<-EOF
		alt-a    attach to default container
		alt-A    select and attach to container
		alt-c    change active context
		alt-d    delete resource (with confirmation)
		alt-D    delete resource --now (with confirmation)
		alt-i    describe resource (mnemonic: inspect)
		alt-k    change active resource kind
		alt-l    show container logs
		alt-L    select and show container logs
		alt-n    change active namespace
		alt-r    restart resource
		alt-x    execute command in container
		alt-X    select and execute command in container
		alt-y    show manifest (mnemonic: YAML)
	EOF" \
