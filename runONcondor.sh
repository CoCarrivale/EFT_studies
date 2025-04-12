#!/bin/bash

baseDir=$(pwd)
proc=$1
model=$2
N=${3:-0}

mkdir -p Output/$proc/
mkdir -p logs/
cp run_madgraph.sh run_madgraph_condor.sh
sed -i "s|CURRENT_DIRECTORY|$baseDir|g" run_madgraph_condor.sh

cp submit.sub submit_${proc}_${model}_$N.sub

sed -i \
  -e "s|PROCESS|$proc|g" \
  -e "s|MODEL|$model|g" \
  -e "s|BLOCK|$N|g" \
  submit_${proc}_${model}_$N.sub

condor_submit submit_${proc}_${model}_$N.sub

#rm run_madgraph_condor.sh
#mv submit_${proc}_${model}_$N.sub Output/$proc/