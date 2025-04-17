#!/bin/bash

baseDir=$(pwd)
proc=$1
model=$2
N=${3:-0}

if [[ -n "$_CONDOR_SCRATCH_DIR" ]]; then
  echo "Running under Condor — Copying files"
  LOCAL_PATH="CURRENT_DIRECTORY"
  cp -r $LOCAL_PATH/MG5_aMC_v2_9_18 $LOCAL_PATH/models.json $LOCAL_PATH/processes.json .
else
  echo "Running locally — using existing MG5_aMC_v2_9_18 directory"
  LOCAL_PATH=$baseDir
fi

rm -rf $baseDir/MG5_aMC_v2_9_18/mg5_cmd.txt $baseDir/py.py $baseDir/MG5_debug $baseDir/Output/$proc/

## Definition of input parameters (process, model, operators) ##

file="$baseDir/processes.json"
models_json="$baseDir/models.json"
mkdir -p $baseDir/logs
mkdir -p $baseDir/Output/$proc

echo "Parsing model info..."
block=$(jq -r --arg model "$model" --argjson N "$N" '.[$model].block[$N]' "$models_json")
ufo=$(jq -r ".[\"$model\"].ufo" "$models_json")
restrict_card="$baseDir/MG5_aMC_v2_9_18/models/$ufo/restrict_base.dat"

mapfile -t operators < <(jq -r ".\"$model\".operators[$N][]" "$models_json")
start=$(jq -r ".\"$model\".range[$N][0]" "$models_json")
end=$(jq -r ".\"$model\".range[$N][1]" "$models_json")

## Extraction of MadGraph syntax for your process ##

mg5_entry=$(jq -c ".${proc}.mg5_syntax" "$file")
declare -a mg5_syntax_list
if [[ "$mg5_entry" =~ ^\[ ]]; then
  mapfile -t mg5_syntax_list < <(jq -r ".${proc}.mg5_syntax[][]" "$file")
else
  mg5_syntax_list=("$mg5_entry")
fi

## Counting of diagrams ##
## Note: Code runs over all sub-processes (here called "groups") defined in process.json ##

declare -a sm_diagrams_per_group
declare -A operator_diagrams_per_group

for ((g=0; g<${#mg5_syntax_list[@]}; g++)); do
  group="${mg5_syntax_list[$g]}"
  
  ## Running for SM ##

  echo "Counting SM diagrams for group $g"
  cmd_file="$baseDir/MG5_aMC_v2_9_18/mg5_cmd.txt"
  echo "import model $ufo-base" > "$cmd_file"
  IFS='##' read -ra parts <<< "${group//X/0}"
  for part in "${parts[@]}"; do
    trimmed=$(echo "$part" | xargs)
    [[ -n "$trimmed" ]] && echo "$trimmed" >> "$cmd_file"
  done
  echo "quit" >> "$cmd_file"
  
  ## Number of diagrams is extracted by MadGraph log ##

  sm_log="$baseDir/Output/$proc/mg5_${proc}_g${g}_SM.log"
  python3 $baseDir/MG5_aMC_v2_9_18/bin/mg5_aMC $cmd_file > "$sm_log"
  diagrams=$(grep -m1 "^Total: .* diagrams" "$sm_log" | sed -n 's/.*with \([0-9]\+\) diagrams/\1/p')
  sm_diagrams_per_group+=($diagrams)
  
  ## Running for EFT contributions ##

  for op in "${operators[@]}"; do

    ## Modification of restrict_base.dat to select the specific EFT contribution ##
    sed -i -E "s/^([[:space:]]*[0-9]+)[[:space:]]+[-+0-9.eE]+[[:space:]]+# $op\>/\\1  1.00000e+00 # $op/" "$restrict_card"
    
    echo "import model $ufo-base" > "$cmd_file"
    IFS='##' read -ra np_parts <<< "${group//X/1}"
    for part in "${np_parts[@]}"; do
      trimmed=$(echo "$part" | xargs)
      [[ -n "$trimmed" ]] && echo "$trimmed" >> "$cmd_file"
    done
    echo "quit" >> "$cmd_file"

    log_file="$baseDir/Output/$proc/mg5_${proc}_${op}_g${g}.log"
    python3 $baseDir/MG5_aMC_v2_9_18/bin/mg5_aMC $cmd_file > "$log_file"
    n_diags=$(grep -m1 "^Total: .* diagrams" "$log_file" | sed -n 's/.*with \([0-9]\+\) diagrams/\1/p')
    operator_diagrams_per_group[$op]+="$n_diags "
    
    ## Modification of restrict_base.dat to restore initial values (EFT=0) before next iteration ##   
    sed -i -E "s/^([[:space:]]*[0-9]+)[[:space:]]+[-+0-9.eE]+[[:space:]]+# $op\>/\\1  .000000e+00 # $op/" "$restrict_card"
  
  done
  rm "$cmd_file"
done

## Write diagram summary ##

out_diagrams="$LOCAL_PATH/Output/$proc/diagrams.txt"
echo "SM: ${sm_diagrams_per_group[*]}" > "$out_diagrams"
for op in "${operators[@]}"; do
  echo "$op: ${operator_diagrams_per_group[$op]}" >> "$out_diagrams"
done

## Filter significant operators ##
## Note: This step is performed comparing the number of diagrams of some EFT contribution wrt SM ones ##
## If N(EFT_i) = N(SM) the operator doesn't affect the process ##

declare -a DIFF_OPS
for op in "${operators[@]}"; do
  op_diags=( ${operator_diagrams_per_group[$op]} )
  diff=0
  for i in "${!op_diags[@]}"; do
    [[ "${op_diags[$i]}" != "${sm_diagrams_per_group[$i]}" ]] && diff=1 && break
  done
  [[ $diff -eq 1 ]] && DIFF_OPS+=($op)
done

echo "Significant operators: ${DIFF_OPS[*]}"

######################
######################

## Build REWEIGHT CARD for relevant operators ##

echo "   "
echo "STARTING"

rwgt_card="$LOCAL_PATH/Output/${proc}/reweight_card.dat"
sm_diagr=$(grep '^SM:' "$LOCAL_PATH/Output/$proc/diagrams.txt" | awk '{print $2}')

mapfile -t DIFF_OPS < <(awk -v sm="$sm_diagr" '$1 != "SM:" && $2 != sm {gsub(":", "", $1); print $1}' "$LOCAL_PATH/Output/$proc/diagrams.txt")

echo "change helicity False" > "$rwgt_card"
echo "change rwgt_dir rwgt" >> "$rwgt_card"
echo "" >> "$rwgt_card"

OPERATORS=($(jq -r --arg model "$model" --argjson n "$N" '.[$model].operators[$n][]' "$models_json"))
START_INDEX=$(jq -r --arg model "$model" --argjson n "$N" '.[$model].range[$n][0]' "$models_json")

declare -A OP_INDEX
for i in "${!OPERATORS[@]}"; do
    idx=$((START_INDEX + i))
    OP_INDEX["${OPERATORS[$i]}"]=$idx
done

#write_operator_block() {
#    local name=$1
#    local value=$2
#    local -A values=([${OP_INDEX[$name]}]=$value)
#    echo "   set $block ${OP_INDEX[$name]} $value" >> "$rwgt_card"
#}

write_full_block() {
    local -n input_vals=$1 
    for op in "${OPERATORS[@]}"; do
        idx=${OP_INDEX[$op]}
        val=${input_vals[$idx]:-0} 
        echo "   set $block $idx $val" >> "$rwgt_card"
    done
}

# Reweighting weight SM
echo "# SM" >> "$rwgt_card"
echo "launch --rwgt_name=rwgt_1" >> "$rwgt_card"
declare -A sm_vals=()
write_full_block sm_vals

counter=2

## Reweighting weights for single operators ##

for op in "${DIFF_OPS[@]}"; do
    clean_op=$(echo "$op" | tr -d '[:space:]')

    for val in 1 -1; do
        echo "" >> "$rwgt_card"
        echo "# $clean_op=$val" >> "$rwgt_card"
        echo "launch --rwgt_name=rwgt_$counter" >> "$rwgt_card"
        declare -A block_vals=()
        idx=${OP_INDEX[$clean_op]}
        block_vals[$idx]=$val
        write_full_block block_vals
        ((counter++))
    done
done

## Reweighting weights for 2 operators ##

for ((i = 0; i < ${#DIFF_OPS[@]}; i++)); do
    for ((j = i + 1; j < ${#DIFF_OPS[@]}; j++)); do
        op1=$(echo "${DIFF_OPS[$i]}" | tr -d '[:space:]')
        op2=$(echo "${DIFF_OPS[$j]}" | tr -d '[:space:]')

        echo "" >> "$rwgt_card"
        echo "# $op1=1 $op2=1" >> "$rwgt_card"
        echo "launch --rwgt_name=rwgt_$counter" >> "$rwgt_card"
        declare -A block_vals=()
        idx1=${OP_INDEX[$op1]}
        idx2=${OP_INDEX[$op2]}
        block_vals[$idx1]=1
        block_vals[$idx2]=1
        write_full_block block_vals
        ((counter++))
    done
done

## Cleaning reweight card ##
## Note: non-relevant operators are now removed ##

num_blocks=$(grep -c "^#" "$rwgt_card")

declare -A line_counts
while read -r line; do
    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//' | grep "^set ")
    if [[ -n "$trimmed" ]]; then
        key=$(echo "$trimmed" | tr -s ' ')
        line_counts["$key"]=$((line_counts["$key"] + 1))
    fi
done < "$rwgt_card"

tmpfile=$(mktemp)

while read -r line; do
    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//' | grep "^set ")
    if [[ -n "$trimmed" ]]; then
        key=$(echo "$trimmed" | tr -s ' ')
        if [[ ${line_counts[$key]} -eq $num_blocks ]]; then
            continue
        fi
    fi
    echo "$line" >> "$tmpfile"
done < "$rwgt_card"

mv "$tmpfile" "$rwgt_card"

echo "Reweight card ready!"

## Build RESTRICTION CARD for relevant operators ##

restrict_target="$LOCAL_PATH/Output/${proc}/restrict_${proc}.dat"
cp "$restrict_card" "$restrict_target"
used_indices=$(grep "^ *set $block" "$rwgt_card" | awk '{print $3}' | sort -n | uniq)

tmpfile=$(mktemp)

current_block=""
while IFS= read -r line; do

    if [[ "$line" =~ ^[[:space:]]*Block[[:space:]]+([A-Za-z0-9_]+) ]]; then
        current_block=${BASH_REMATCH[1]}
        echo "$line" >> "$tmpfile"
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+[-+0-9.eE]+[[:space:]]+# ]]; then
        idx=${BASH_REMATCH[1]}
        if echo "$used_indices" | grep -q -w "$idx" && [[ "$current_block" == "$block" ]]; then

            newline=$(echo "$line" | sed -E "s/^([[:space:]]*$idx[[:space:]]+)[-+0-9.eE]+/\19.999999e-01/")
            echo "$newline" >> "$tmpfile"
        else
            echo "$line" >> "$tmpfile"
        fi
    else
        echo "$line" >> "$tmpfile"
    fi
done < "$restrict_target"

mv "$tmpfile" "$restrict_target"

echo "Restrict card ready!"

## Organizing outputs in output folder ##

rm py.py

if [[ -n "$_CONDOR_SCRATCH_DIR" ]]; then
  echo "Cleaning..."
  mv $LOCAL_PATH/logs/ $LOCAL_PATH/run_madgraph_condor.sh $LOCAL_PATH/submit_${proc}_${model}_${N}.sub $LOCAL_PATH/Output/$proc/
fi

exit 0
