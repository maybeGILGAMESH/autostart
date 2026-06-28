#!/usr/bin/env bash
set -euo pipefail

proxy_env_names() {
  printf '%s\n' \
    http_proxy \
    https_proxy \
    all_proxy \
    HTTP_PROXY \
    HTTPS_PROXY \
    ALL_PROXY \
    no_proxy \
    NO_PROXY
}

run_without_proxy() {
  local -a env_args=()
  local var_name

  while read -r var_name; do
    [[ -n "$var_name" ]] && env_args+=("-u" "$var_name")
  done < <(proxy_env_names)

  env "${env_args[@]}" "$@"
}
