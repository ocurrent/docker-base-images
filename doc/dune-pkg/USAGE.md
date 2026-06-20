# Using a `dune` image

Ships `dune` + a pre-built OCaml compiler baked into dune's cache. You bring a
committed `dune.lock`; the image builds it, reusing the baked compiler — no opam,
no network, no compiler rebuild.

Tag: `ocaml/opam:<distro>-dune-ocaml-<version>[-<variant>]`, x86_64 only.
E.g. `debian-dune-ocaml-5.5`, `alpine-dune-ocaml-5.5-flambda`.

## On the host (once)

`dune` must be installed. Lock from opam-repository only, so the locked compiler
matches the baked one:

```sh
cat > dune-workspace <<'EOF'
(lang dune 3.20)
(lock_dir (repositories upstream))
EOF

dune pkg lock          # writes dune.lock/ — commit it; re-run only when deps change
```

## In the image

```sh
docker run --rm -v "$PWD:/src" -w /src \
  ocaml/opam:debian-dune-ocaml-5.5 dune exec ./main.exe
```

Or `COPY . .` the sources in via a Dockerfile (the natural CI shape).

## Gotchas

- **Version/variant must match the tag.** A `dune-ocaml-5.5` image only reuses
  the baked compiler if your lock resolves OCaml `5.5` (`(ocaml (= 5.5.0))`); a
  `-flambda` image needs `ocaml-options-only-flambda` in your `depends`. A
  mismatch forces a from-source compiler build.
- **x86_64 only** — no dune Linux-arm64 binary.
