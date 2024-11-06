(lang dune 3.7)
(name base-images)
(generate_opam_files true)
(formatting (enabled_for dune))

(source (github ocurrent/docker-base-images))
(authors "talex5@gmail.com" "anil@recoil.org")
(maintainers "talex5@gmail.com")
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
  (lwt (>= 5.6.1))
  logs
  (fmt (>= 0.8.7))
  (current (>= 0.6.6))
  current_git
  current_github
  current_docker
  (current_ocluster (>= 0.3.0))
  current_slack
  current_web
  current_rpc
  (capnp-rpc-unix (>= 1.2.3))
  (cmdliner (>= 1.1.1))
  (dockerfile (>= 8.2.3))
  (dockerfile-opam (>= 8.2.3))
  (ocaml-version (>= 3.6.9))
  (timedesc (>= 3.0.0))))
