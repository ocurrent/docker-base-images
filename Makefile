CONTEXT := ci.ocamllabs.io
.PHONY: build clean

build:
	dune build ./src/base_images.exe @install @runtest

deploy:
	docker --context $(CONTEXT) build -t base-images .

deploy-stack:
	docker --context $(CONTEXT) stack deploy --prune -c stack.yml base-images

clean:
	dune clean
