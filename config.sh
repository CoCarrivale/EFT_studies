#!/bin/bash
# Launch this script from your work directory

##############
## MadGraph ##
##############

echo "Downloading MG5_aMC_v2_9_18  ..."
wget http://cms-project-generators.web.cern.ch/cms-project-generators/MG5_aMC_v2.9.18.tar.gz
tar xvf MG5_aMC_v2_9_18.tar.gz
rm MG5_aMC_v2_9_18.tar.gz

#####################
## Main EFT models ##
#####################

#!/bin/bash

for file in models/*_UFO.tar.gz; do
    model=$(basename "$file" _UFO.tar.gz)
    echo "Unboxing model $model..."
    cp "$file" MG5_aMC_v2_9_18/models/
    cd MG5_aMC_v2_9_18/models/ || exit
    tar -xsvf "${model}_UFO.tar.gz"
    rm "${model}_UFO.tar.gz"
    cd ../..
done