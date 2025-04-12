# EFT_studies

After cloning the repository, run the configuration file:

```
./config.sh
```

After that, you will have MG5_aMC_v2_9_18 with all relevant models for EFT @dim6 and @dim8. Most of the models are already implemented in models.json.

<details>
    <summary> What if I want to upload a new model?</summary>

    - Make sure to generate inside the model a restrict_card called ```restrict_base.dat``` with all WCs set to 0.
    - For each EFT block, define a list of operators with corresponding indices range inside the block.
    - You can also upload the tar.gz file in models/. 
</details>
EFT model (aqgc, SMEFTfr, SMEFTsim etc) should be uploaded in MG5_aMC_v2_9_23/models.
For each model, copy an available restriction card and rename it as "restrict_base.dat", then put all WCs values to .000000e-00.

Update your local path in run_madgraph.sh.

```
./run_madgraph.sh $process $model
```

$process and $model should match keys in the respective dictionaries.
Outputs are diagrams.txt, reweight_card.dat and restrict_$process.dat.

Fix needed:
- condor submission
- introduction of generic paths
- avoid modifications to cpv block in restrict_card