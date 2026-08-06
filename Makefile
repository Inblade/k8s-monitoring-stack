.PHONY: check render lint test yaml clean

check: render lint test yaml ## Everything CI runs

render: ## Unwrap the PrometheusRule CRDs into plain rule files
	python3 scripts/render-rules.py

lint: render ## promtool syntax and semantic checks
	promtool check rules .rendered/*.yaml

test: render ## promtool unit tests for the alerting rules
	promtool test rules tests/*.test.yaml

yaml: ## yamllint over every manifest
	yamllint -c .yamllint.yaml alerts/ argocd/ helm/ tests/

clean:
	rm -rf .rendered
