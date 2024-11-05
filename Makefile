-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

# specify which fork to use. set this in our .env
# if we want to test multiple forks in one go, remove this as an argument below
FORK_URL := ${ETH_RPC_URL} # BASE_RPC_URL, ETH_RPC_URL, ARBITRUM_RPC_URL

# if we want to run only matching tests, set that here
test := test_

# local tests without fork
test  :; forge test -vv --fork-url ${FORK_URL} --ffi
trace  :; forge test -vvv --fork-url ${FORK_URL} --ffi
gas  :; forge test --fork-url ${FORK_URL} --gas-report --ffi
test-contract  :; forge test -vv --match-contract $(contract) --fork-url ${FORK_URL} --ffi
test-contract-gas  :; forge test --gas-report --match-contract ${contract} --fork-url ${FORK_URL} --ffi
trace-contract  :; forge test -vvv --match-contract $(contract) --fork-url ${FORK_URL} --ffi
test-test  :; forge test -vv --match-test $(test) --fork-url ${FORK_URL} --ffi
test-test-trace  :; forge test -vvv --match-test $(test) --fork-url ${FORK_URL} --ffi
trace-test  :; forge test -vvvvv --match-test $(test) --fork-url ${FORK_URL} --ffi
snapshot :; forge snapshot -vv --fork-url ${FORK_URL} --ffi
snapshot-diff :; forge snapshot --diff -vv --fork-url ${FORK_URL} --ffi
trace-setup  :; forge test -vvvv --fork-url ${FORK_URL} --ffi
trace-max  :; forge test -vvvvv --fork-url ${FORK_URL} --ffi
coverage :; forge coverage --fork-url ${FORK_URL} --ffi
coverage-report :; forge coverage --report lcov --fork-url ${FORK_URL} --ffi
coverage-debug :; forge coverage --report debug --fork-url ${FORK_URL} --ffi

coverage-html:
	@echo "Running coverage..."
	forge coverage --report lcov --fork-url ${FORK_URL} --ffi
	@if [ "`uname`" = "Darwin" ]; then \
		lcov --ignore-errors inconsistent --remove lcov.info 'src/test/**' --output-file lcov.info; \
		genhtml --ignore-errors inconsistent -o coverage-report lcov.info; \
	else \
		lcov --remove lcov.info 'src/test/**' --output-file lcov.info; \
		genhtml -o coverage-report lcov.info; \
	fi
	@echo "Coverage report generated at coverage-report/index.html"

clean  :; forge clean
