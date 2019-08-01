.PHONY: build clean

build:
	dune build ./src/base_images.exe

clean:
	dune clean
