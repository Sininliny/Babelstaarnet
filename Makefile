.PHONY: build test test-runtime benchmark-ocr app release run install install-engines readme-images clean

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

install:
	./Scripts/install-app.sh

install-engines:
	./Scripts/install-local-engines.sh

readme-images:
	swift ./Scripts/generate-readme-images.swift ./docs/images

clean:
	swift package clean
	rm -rf ./dist
