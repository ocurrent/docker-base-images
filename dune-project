(lang dune 3.17)
(name base-images)
(generate_opam_files true)
(formatting (enabled_for dune))

(source (github ocurrent/docker-base-images))
(authors "talex5@gmail.com" "anil@recoil.org")
(maintainers "mark.elvers@tunbury.org")
(license "Apache-2.0")

(package
 (name base-images)
 (synopsis "Generate Docker base images for OCaml and opam using ocurrent")
 (depends
  (ocaml (>= 4.14))
  (conf-libev (<> :os "win32"))
  (prometheus-app (>= 1.0))
  ppx_sexp_conv
  ppx_deriving_yojson
  ppx_deriving
  (lwt (>= 5.9.0))
  logs
  (fmt (>= 0.8.7))
  (current (>= 0.7.0))
  current_git
  current_github
  current_docker
  (current_ocluster (>= 0.3.0))
  current_slack
  current_web
  current_rpc
  (capnp-rpc-unix (>= 1.2.3))
  (cmdliner (>= 1.3.0))
  (dockerfile (>= 8.2.5))
  (dockerfile-opam (>= 8.2.5))
  (ocaml-version (>= 3.7.3))
  (timedesc (>= 3.0.0))
  opam-core))
