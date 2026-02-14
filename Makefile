.PHONY: help up down restart logs token status build clean simple-up simple-down

COMPOSE  := docker compose
SIMPLE   := docker compose -f docker-compose.simple.yml

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ── Caddy + TeamSpeak (default) ─────────────────────────────

build: ## Build the custom Caddy image
	$(COMPOSE) build

up: .env ## Start Caddy + TeamSpeak
	$(COMPOSE) up -d

down: ## Stop all containers
	$(COMPOSE) down

restart: ## Restart all containers
	$(COMPOSE) restart

logs: ## Tail all container logs
	$(COMPOSE) logs -f

token: ## Print the TeamSpeak admin privilege key
	$(COMPOSE) logs teamspeak 2>&1 | grep -i "token"

status: ## Show running containers
	$(COMPOSE) ps

# ── Simple mode (TeamSpeak only, no Caddy) ──────────────────

simple-up: .env ## Start TeamSpeak without Caddy
	$(SIMPLE) up -d

simple-down: ## Stop TeamSpeak (simple mode)
	$(SIMPLE) down

# ── Utilities ────────────────────────────────────────────────

.env:
	@echo "Creating .env from .env.example …"
	@cp .env.example .env
	@echo "Edit .env before running 'make up'."

clean: ## Remove volumes (DESTROYS DATA)
	$(COMPOSE) down -v
	@echo "All volumes removed."
