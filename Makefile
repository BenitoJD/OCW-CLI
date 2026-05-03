.PHONY: test lint package release-check install doctor models

test:
	./test/run.sh

lint:
	./scripts/lint.sh

package:
	./scripts/package.sh

release-check:
	./scripts/release-check.sh

install:
	./install.sh

doctor:
	./bin/ocw doctor

models:
	./bin/ocw models
