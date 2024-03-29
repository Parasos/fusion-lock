conda create --name slither-testing
conda activate slither-testing
pip3 install slither-analyzer
slither --config-file slither.config.json --json file.json .