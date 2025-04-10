#!/bin/bash

# Searching for process definition

baseDir=$(pwd)
echo $baseDir

rm "$baseDir"/MG5_aMC_v2_9_18/mg5_cmd.txt "$baseDir"/py.py "$baseDir"/mg5_* "$baseDir"/MG5_debug "$baseDir"/diagrams.txt "$baseDir"/mg5_*

file="$baseDir/processes.json"
models_json="$baseDir/models.json"

proc=$1
model=$2
N=${3:-0}

mg5_string=$(jq -r ".${proc}.mg5_syntax" $file)
block=$(jq -r --arg model "$model" --argjson N "$N" '.[$model].block[$N]' "$models_json")
ufo=$(jq -r ".[\"$model\"].ufo" "$models_json")

restrict_card="$baseDir/MG5_aMC_v2_9_18/models/$ufo/restrict_base.dat"

if [ "$mg5_syntax" == "null" ]; then
    echo "No matching process found for $1"
    exit 1
fi

#mapfile -t operators < <(jq -r ".[\"$model\"].operators[]" "$models_json")

#start=$(jq ".[\"$model\"].range[0]" "$models_json")
#end=$(jq ".[\"$model\"].range[1]" "$models_json")
#range=()
#for ((i=start; i<=end; i++)); do
#  range+=($i)
#done

mapfile -t operators < <(jq -r ".\"$model\".operators[$N][]" "$models_json")
start=$(jq -r ".\"$model\".range[$N][0]" "$models_json")
end=$(jq -r ".\"$model\".range[$N][1]" "$models_json")
range=()
for ((i=start; i<=end; i++)); do
  range+=("$i")
done

echo "Block: $block"
echo ""

echo "Operators:"
for op in "${operators[@]}"; do
  echo " - $op"
done
echo ""

echo "Range: [$start ; $end]"


echo "Working on process $proc with model $model"
echo "mg5_syntax: $mg5_string"

# Running Standard Model

echo "Counting diagrams for SM"

cmd_file="$baseDir/MG5_aMC_v2_9_18/mg5_cmd.txt"
echo "import model $ufo-base" >> $cmd_file
echo ${mg5_string//X/0} >> $cmd_file
echo "quit" >> $cmd_file

cat $cmd_file
python3 $baseDir/MG5_aMC_v2_9_18/bin/mg5_aMC $cmd_file > $baseDir/mg5_${proc}.log
  
if grep -q "^Total: [0-9]\+ processes with [0-9]\+ diagrams" $baseDir/mg5_${proc}.log; then
  diagrams_line=$(grep "^Total: [0-9]\+ processes with [0-9]\+ diagrams" $baseDir/mg5_${proc}.log)
  m_diagrams=$(echo "$diagrams_line" | sed -n 's/.*with \([0-9]\+\) diagrams/\1/p')
  echo "SM: ${m_diagrams} diagrams" >> $baseDir/diagrams.txt
else
  echo "SM: no diagrams found" >> $baseDir/diagrams.txt
  exit 0
fi

rm $cmd_file

# Launching MadGraph

for ((i=0; i<${#operators[@]}; i++)); do
  oppe=${operators[$i]}
  sed -i -E "s/^([[:space:]]*[0-9]+)[[:space:]]+[-+0-9.eE]+[[:space:]]+# $oppe\>/\\1  1.00000e+00 # $oppe/" "$restrict_card"
  echo "Counting diagrams for $oppe"
  cmd_file="$baseDir/MG5_aMC_v2_9_18/mg5_cmd.txt"
  echo "import model $ufo-base" >> $cmd_file
  echo ${mg5_string//X/1} >> $cmd_file
  echo "quit" >> $cmd_file

  cat $cmd_file
  python3 "$baseDir"/MG5_aMC_v2_9_18/bin/mg5_aMC $cmd_file > "$baseDir"/mg5_${proc}_${oppe}.log
  
  if grep -q "^Total: [0-9]\+ processes with [0-9]\+ diagrams" $baseDir/mg5_${proc}_${oppe}.log; then
    diagrams_line=$(grep "^Total: [0-9]\+ processes with [0-9]\+ diagrams" $baseDir/mg5_${proc}_${oppe}.log)
    m_diagrams=$(echo "$diagrams_line" | sed -n 's/.*with \([0-9]\+\) diagrams/\1/p')
    echo "${oppe}: ${m_diagrams} diagrams" >> $baseDir/diagrams.txt
  else
    echo "${oppe}: no diagrams found" >> $baseDir/diagrams.txt
  fi

  sed -i -E "s/^([[:space:]]*[0-9]+)[[:space:]]+[-+0-9.eE]+[[:space:]]+# $oppe\>/\\1  .000000e+00 # $oppe/" "$restrict_card"
  rm $cmd_file
done

######################
######################


echo "   "
echo "STARTING"

rwgt_card="reweight_card.dat"
sm_diagr=$(grep '^SM:' "diagrams.txt" | awk '{print $2}')

mapfile -t DIFF_OPS < <(awk -v sm="$sm_diagr" '$1 != "SM:" && $2 != sm {gsub(":", "", $1); print $1}' "diagrams.txt")

echo "change helicity False" > "$rwgt_card"
echo "change rwgt_dir rwgt" >> "$rwgt_card"
echo "" >> "$rwgt_card"

#OPERATORS=($(jq -r --arg model "$model" '.[$model].operators[]' "$models_json"))
#START_INDEX=$(jq -r --arg model "$model" '.[$model].range[0]' "$models_json")

#declare -A OP_INDEX
#for i in "${!OPERATORS[@]}"; do
#    idx=$((START_INDEX + i))
#    OP_INDEX["${OPERATORS[$i]}"]=$idx
#done

OPERATORS=($(jq -r --arg model "$model" --argjson n "$N" '.[$model].operators[$n][]' "$models_json"))
START_INDEX=$(jq -r --arg model "$model" --argjson n "$N" '.[$model].range[$n][0]' "$models_json")

declare -A OP_INDEX
for i in "${!OPERATORS[@]}"; do
    idx=$((START_INDEX + i))
    OP_INDEX["${OPERATORS[$i]}"]=$idx
done

write_operator_block() {
    local name=$1
    local value=$2
    local -A values=([${OP_INDEX[$name]}]=$value)

    echo "   set $block ${OP_INDEX[$name]} $value" >> "$rwgt_card"
}

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

# Reweighting weights for single operators
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

# Reweighting weights for 2 operators
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

# Cleaning reweight card

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

# Restriction card

restrict_target="$baseDir/MG5_aMC_v2_9_18/models/$ufo/restrict_${proc}.dat"
cp "$restrict_card" "$restrict_target"
used_indices=$(grep "^ *set $block" "$rwgt_card" | awk '{print $3}' | sort -n | uniq)

tmpfile=$(mktemp)

while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+[-+0-9.eE]+[[:space:]]+# ]]; then
        idx=${BASH_REMATCH[1]}
        if echo "$used_indices" | grep -q -w "$idx"; then
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

# fix: cambia anche i cpv, deve leggere bene
# fix: cambia i path
# fix: sottomissione su condor

exit 0
