#!/usr/bin/env bash
# Generate the fixed 8192 x 64 BootROM macro from the SMIC S018VM compiler.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <S018VM_CDK_DIR> <bootrom.code> <output-dir>" >&2
  exit 2
fi

cdk_dir=$1
codefile=$2
output_dir=$3
macro_name=S018VM_X512Y16D64_PM

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

if [[ $(wc -l < "$codefile") -ne 8192 ]] || [[ $(awk 'length != 64 || /[^01]/ { bad = 1 } END { print bad + 0 }' "$codefile") -ne 0 ]]; then
  echo "BootROM code file must contain exactly 8192 lines of 64 binary bits: $codefile" >&2
  exit 1
fi

output_dir=$(realpath -m "$output_dir")
cdk_dir=$(realpath "$cdk_dir")
codefile=$(realpath "$codefile")
mkdir -p "$output_dir"

macro_v=$output_dir/$macro_name.v
rm -f "$output_dir/$macro_name".{v,lef,lib,cdl,gds,pdf} \
  "$output_dir/$macro_name"_*.lib

compiler_dir=$cdk_dir
if [[ -n ${DISPLAY:-} ]]; then
  (
    cd "$compiler_dir"
    env -u JAVA_TOOL_OPTIONS "$java_cmd" -jar S018VM.jar -instname "$macro_name" -words 8192 -mux 16 -bits 64 \
      -codefile "$codefile" -savepath "$output_dir" -v -lef -lib -cdl -gds
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
    env -u JAVA_TOOL_OPTIONS "$java_cmd" -jar S018VM.jar -instname "$macro_name" -words 8192 -mux 16 -bits 64 \
      -codefile "$codefile" -savepath "$output_dir" -v -lef -lib -cdl -gds
  )
fi

if [[ ! -f "$macro_v" ]]; then
  echo "SMIC ROM compiler did not produce $macro_v" >&2
  exit 1
fi
