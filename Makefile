.PHONY: build clean

build:
	dune build ./src/base_images.exe @install @runtest

clean:
	dune clean
