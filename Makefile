.PHONY: test lint package gauntlet release-check install doctor models

test:
	./test/run.sh

lint:
	./scripts/lint.sh

package:
	./scripts/package.sh

gauntlet:
	./scripts/gauntlet.sh

release-check:
	./scripts/release-check.sh

install:
	./install.sh

doctor:
	./bin/ocw doctor

models:
	./bin/ocw models
