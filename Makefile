.PHONY: build test test-runtime app run install-engines clean

build:
	swift build

test:
	./Scripts/test-layout.sh

test-runtime:
	./Scripts/test-runtime.sh

app:
	./Scripts/build-app.sh

run: app
	open ./dist/Babelstaarnet.app

install-engines:
	./Scripts/install-local-engines.sh

clean:
	swift package clean
	rm -rf ./dist
