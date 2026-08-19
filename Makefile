SHELL := /bin/bash

.PHONY: help cluster deploy status open smoke mcp-config fault reset down destroy validate

help:
	@./scripts/dogshop.sh help

cluster:
	@./scripts/dogshop.sh cluster

deploy:
	@./scripts/dogshop.sh deploy

status:
	@./scripts/dogshop.sh status

open:
	@./scripts/dogshop.sh open

smoke:
	@./scripts/dogshop.sh smoke

mcp-config:
	@./scripts/dogshop.sh mcp-config

fault:
	@./scripts/dogshop.sh fault "$(SCENARIO)"

reset:
	@./scripts/dogshop.sh reset

down:
	@./scripts/dogshop.sh down

destroy:
	@./scripts/dogshop.sh destroy

validate:
	@./scripts/dogshop.sh validate
