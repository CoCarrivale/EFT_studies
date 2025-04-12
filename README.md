# EFT_studies

> Everything started when someone thought "why should I lose my mental health generating gridpacks with 100k operators, if only 10 of them affect my process?". That's why this code exists. Counting the diagrams introduced by different EFT operators and comparing them with SM ones, now you can derive a process-specific list of operators. Associated reweight_card and restrict_card are for free.

After cloning the repository, run the configuration file:

```
./config.sh
```

After that, you will have MG5_aMC_v2_9_18 with all relevant models for EFT @dim6 and @dim8. Most of the models are already implemented in models.json.

<details>
    <summary> What if I want to upload a new model?</summary>

    - Make sure to generate inside the model a restrict_card called restrict_base.dat with all WCs set to 0.
    - For each EFT block, define a list of operators with corresponding indices range inside the block.
    - You can also upload the tar.gz file in models/. 
</details>


Define your process in process.json. EFT order is encoded as NP=X, the code will change automatically to 0 (SM)and 1 (EFT)while running.

<details>
    <summary> What if my process needs some strange multiparticles?</summary>

    Different lines in MadGraph command file can be written in mg5_syntax key for a specific process. Just separate different lines with ##, e.g.:

    ```bash
    "wpwp": {
        "mg5_syntax": ["define p = g u u~ d d~ s s~ c c~ b b~ ## define j = p ## generate p p > w+ w+ j j NP=X"]
    }
    ```
</details>

<details>
    <summary> What if my process needs Madspin?</summary>

    Just consider production and different decays as different sub-processes, writing them as a list in mg5_syntax. The code will put all the informations together, giving a single output for the whole process.
    ```
</details>
Main script is run_madgraph.sh. You can run it locally:

```bash
./run_madgraph.sh $process $model $block
```
or on condor:

```bash
./runONcondor.sh $process $model $block
```

$process and $model should match keys in the respective dictionaries. $block is the index of the EFT block under study, where the order is given by the list defined in models.json. Most of the models have only one block, and if you don't provide the argument the code will automatically consider $block=0. Some models, like SMEFTsim, separate CPC and CPV operators in different blocks.
Outputs are stored in dedicated folders in Output/ and consist in following files:
- diagrams.txt, containing the number of diagrams for each operator;
- reweight_card.dat with relevant operators only;
- restrict_$process.dat, which selects only relevant operators.


Fix needed:
- run automatically over all the blocks