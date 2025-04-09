# EFT_studies

MG5_aMC_v2_9_23 should be located in the same folder of EFT_studied.
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