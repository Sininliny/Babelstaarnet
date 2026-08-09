.PHONY: build test test-runtime benchmark-ocr app release run install-engines clean

build:
	swift build

test:
	./Scripts/test-layout.sh

test-runtime:
	./Scripts/test-runtime.sh

benchmark-ocr:
	./Scripts/benchmark-ocr.sh

app:
	./Scripts/build-app.sh

release:
	./Scripts/package-release.sh

run: app
	open ./dist/Babelstaarnet.app

install-engines:
	./Scripts/install-local-engines.sh

clean:
	swift package clean
	rm -rf ./dist
