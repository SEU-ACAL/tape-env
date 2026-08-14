#!/usr/bin/env bash
# Generate a fixed-width SMIC S018VM ROM macro from the SMIC compiler.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <S018VM_CDK_DIR> <rom.code> <output-dir>" >&2
  exit 2
fi

cdk_dir=$1
codefile=$2
output_dir=$3
macro_name=${SMIC180_ROM_MACRO_NAME:-S018VM_X512Y16D64_PM}
words=${SMIC180_ROM_WORDS:-8192}
bits=${SMIC180_ROM_BITS:-64}
cache_mode=${SMIC180_ROM_CACHE_MODE:-1777}
output_mode=${SMIC180_ROM_OUTPUT_MODE:-0777}
mux=16

if [[ -n ${SMIC180_ROM_JAVA:-} ]]; then
  java_cmd=$SMIC180_ROM_JAVA
elif [[ -n ${JAVA_HOME:-} && -x ${JAVA_HOME}/bin/java ]]; then
  java_cmd=$JAVA_HOME/bin/java
else
  java_cmd=$(command -v java || true)
fi
if [[ -z $java_cmd || ! -x $java_cmd ]]; then
  echo "Java executable not found; set SMIC180_ROM_JAVA or JAVA_HOME" >&2
  exit 1
fi

if [[ ! -d "$cdk_dir" ]]; then
  echo "SMIC S018VM CDK directory does not exist: $cdk_dir" >&2
  exit 1
fi
if [[ ! -r "$cdk_dir/S018VM.jar" ]]; then
  echo "S018VM.jar is not readable: $cdk_dir/S018VM.jar" >&2
  exit 1
fi
if [[ ! -f "$codefile" ]]; then
  echo "Missing required input: $codefile" >&2
  exit 1
fi

if [[ ! $words =~ ^[0-9]+$ ]] || [[ ! $bits =~ ^[0-9]+$ ]]; then
  echo "SMIC180_ROM_WORDS and SMIC180_ROM_BITS must be decimal integers" >&2
  exit 2
fi
if [[ ! $cache_mode =~ ^0?[0-7]{3,4}$ ]] || [[ ! $output_mode =~ ^0?[0-7]{3,4}$ ]]; then
  echo "SMIC180_ROM_CACHE_MODE and SMIC180_ROM_OUTPUT_MODE must be octal modes" >&2
  exit 2
fi
if [[ $(wc -l < "$codefile") -ne $words ]] || [[ $(awk -v bits="$bits" 'length != bits || /[^01]/ { bad = 1 } END { print bad + 0 }' "$codefile") -ne 0 ]]; then
  echo "ROM code file must contain exactly $words lines of $bits binary bits: $codefile" >&2
  exit 1
fi

ensure_mode() {
  local path=$1
  local requested_mode=$2
  local actual_mode
  local expected_mode=${requested_mode#0}

  actual_mode=$(stat -c '%a' "$path")
  if [[ $actual_mode != "$expected_mode" ]]; then
    chmod "$requested_mode" "$path"
  fi
}

output_dir=$(realpath -m "$output_dir")
cdk_dir=$(realpath "$cdk_dir")
codefile=$(realpath "$codefile")
cache_dir=$(dirname "$output_dir")
umask 000
mkdir -p "$output_dir"
ensure_mode "$cache_dir" "$cache_mode"
ensure_mode "$output_dir" "$output_mode"

macro_v=$output_dir/$macro_name.v
cached_codefile=$output_dir/$macro_name.code
fingerprint_file=$output_dir/.$macro_name.fingerprint

# Serialize each macro cache. VCS and Verilator elaborations can run in
# parallel and share this directory.
exec 9>"$output_dir/.$macro_name.lock"
flock 9

code_sha256=$(sha256sum "$codefile" | awk '{ print $1 }')
jar_sha256=$(sha256sum "$cdk_dir/S018VM.jar" | awk '{ print $1 }')
script_sha256=$(sha256sum "${BASH_SOURCE[0]}" | awk '{ print $1 }')
fingerprint=$(
  printf '%s\n' 'format=1'
  printf '%s\n' "macro_name=$macro_name"
  printf '%s\n' "words=$words"
  printf '%s\n' "bits=$bits"
  printf '%s\n' "mux=$mux"
  printf '%s\n' "code_sha256=$code_sha256"
  printf '%s\n' "jar_sha256=$jar_sha256"
  printf '%s\n' "script_sha256=$script_sha256"
)

if [[ -f "$macro_v" && -f "$cached_codefile" && -f "$fingerprint_file" ]] && \
  [[ $(sha256sum "$cached_codefile" | awk '{ print $1 }') == "$code_sha256" ]] && \
  diff -q <(printf '%s\n' "$fingerprint") "$fingerprint_file" > /dev/null; then
  echo "Reusing SMIC ROM IP: $macro_v"
  exit 0
fi

# S018VM writes an absolute $readmemb path into its Verilog. Give it a stable
# copy so a cached macro remains valid after generated-src is cleaned.
tmp_codefile=$cached_codefile.tmp.$$
cp "$codefile" "$tmp_codefile"
mv -f "$tmp_codefile" "$cached_codefile"

rm -f "$output_dir/$macro_name".{v,lef,lib,cdl,gds,pdf} \
  "$output_dir/$macro_name"_*.lib

compiler_dir=$cdk_dir
if [[ -n ${DISPLAY:-} ]]; then
  (
    cd "$compiler_dir"
    env -u JAVA_TOOL_OPTIONS "$java_cmd" -jar S018VM.jar -instname "$macro_name" -words "$words" -mux "$mux" -bits "$bits" \
      -codefile "$cached_codefile" -savepath "$output_dir" -v -lef -lib -cdl -gds
  )
else
  xvfb=${SMIC180_ROM_XVFB:-/data0/tools/Synopsys/verdi/verdi/W-2024.09-SP1/bin/Xvfb}
  if [[ ! -x "$xvfb" ]]; then
    echo "SMIC ROM compiler requires X11; set SMIC180_ROM_XVFB to an Xvfb executable" >&2
    exit 1
  fi

  xvfb_pid=
  for display_number in $(seq 91 110); do
    "$xvfb" ":$display_number" -screen 0 1024x768x24 -ac -fp /usr/share/fonts/X11/misc > /dev/null 2>&1 &
    candidate_pid=$!
    sleep 0.1
    if kill -0 "$candidate_pid" 2> /dev/null; then
      xvfb_pid=$candidate_pid
      export DISPLAY=:$display_number
      break
    fi
  done
  if [[ -z "$xvfb_pid" ]]; then
    echo "Unable to start a private Xvfb display for the SMIC ROM compiler" >&2
    exit 1
  fi
  trap 'kill "$xvfb_pid" 2> /dev/null || true' EXIT

  (
    cd "$compiler_dir"
    env -u JAVA_TOOL_OPTIONS "$java_cmd" -jar S018VM.jar -instname "$macro_name" -words "$words" -mux "$mux" -bits "$bits" \
      -codefile "$cached_codefile" -savepath "$output_dir" -v -lef -lib -cdl -gds
  )
fi

if [[ ! -f "$macro_v" ]]; then
  echo "SMIC ROM compiler did not produce $macro_v" >&2
  exit 1
fi

printf '%s\n' "$fingerprint" > "$fingerprint_file.tmp.$$"
mv -f "$fingerprint_file.tmp.$$" "$fingerprint_file"
chmod a+rw "$macro_v" "$cached_codefile" "$fingerprint_file"
echo "Generated SMIC ROM IP: $macro_v"
