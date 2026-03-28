SCRIPTS_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(SCRIPTS_DIR)/..)

.PHONY: test lint coverage migrate migrate-list migrate-dry-run clean help

test: ## Run full CI (ShellCheck + Bats + Kcov) via docker compose
	$(SCRIPTS_DIR)/ci.sh

lint: ## Run ShellCheck only
	$(SCRIPTS_DIR)/ci.sh --lint-only

coverage: ## Run tests with Kcov coverage
	$(SCRIPTS_DIR)/ci.sh --coverage

migrate: ## Migrate all repos to docker_template
	$(SCRIPTS_DIR)/migrate.sh --all

migrate-list: ## List repos and their migration status
	$(SCRIPTS_DIR)/migrate.sh --list

migrate-dry-run: ## Dry-run migration for all repos
	$(SCRIPTS_DIR)/migrate.sh --dry-run --all

clean: ## Remove coverage reports
	rm -rf $(REPO_ROOT)/coverage/

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
