#! /bin/bash

if [ -z $SDE ]; then
  echo "ERROR: SDE env var not set"
  exit 1
fi

set -e

ethertype_seed=0x1234
gap_seed=120
prot_seed=0x11
gen_seed=1
p4prog_name=orbweaver

usage() {
  echo "Usage: $0 [-t ethertype_seed] [-g gap_seed] [-p prot_seed] <p4prog_name>" 1>&2; exit 1;
}

while getopts ":t:g:p:n" opt
do
  case "${opt}" in
    t) ethertype_seed=${OPTARG};;
    g) gap_seed=${OPTARG};;
    p) prot_seed=${OPTARG};;
    n) gen_seed=0;;
    \?) usage;;
  esac
done
shift $((OPTIND-1))

if [ $# -lt 1 ]; then
  usage
fi

p4prog_name=$1

cat <<EOF
ethertype_seed=${ethertype_seed}
gap_seed=${gap_seed}
prot_seed=${prot_seed}
p4prog_name=${p4prog_name}
EOF

PROG=orbweaver

sudo rm ${PROG} || echo "$PROG Not Found"
gcc -I${SDE}install/include/ -Wno-implicit-function-declaration -Wno-missing-field-initializers -g -O2 -std=c99 -L${SDE}install/lib/ -o ${PROG} ${PROG}.c -ldriver -lbfsys -lbfutils -lbf_switchd_lib -lm -ldl -lpthread -lpython3.4m -lavago

export SDE_INSTALL=$SDE"install"
export LD_LIBRARY_PATH=${SDE}install/lib:$LD_LIBRARY_PATH
echo "LD_LIBRARY_PATH:$LD_LIBRARY_PATH"

OPT=""
if [ $gen_seed -eq 0 ]; then
  OPT="-n"
fi
echo "OPT: $OPT"

sudo env LD_LIBRARY_PATH=$LD_LIBRARY_PATH ./${PROG} -t ${ethertype_seed} -g ${gap_seed} -p ${prot_seed} ${OPT} $SDE_INSTALL $SDE_INSTALL/share/p4/targets/tofino/$1.conf

