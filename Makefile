.PHONY: build test publish check clean help

LAYER_ZIP = layer.zip

help:
	@echo "Targets:"
	@echo "  build    Build layer.zip inside Docker (Amazon Linux 2023)"
	@echo "  test     Test layer in the Lambda Python 3.12 container"
	@echo "  publish  Publish layer to AWS (configure config.sh first)"
	@echo "  check    List published layer ARNs across configured regions"
	@echo "  clean    Remove build artifacts"

build:
	bash build.sh

test: $(LAYER_ZIP)
	bash test.sh

publish: $(LAYER_ZIP)
	bash publish.sh

check:
	bash check.sh

clean:
	rm -rf layer $(LAYER_ZIP)
