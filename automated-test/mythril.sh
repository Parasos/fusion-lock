conda create --name mythril-testing
conda activate mythril-testing
pip3 install mythril
myth analyze src/FusionLock.sol --solc-json automated-test/mythril.config.json