(lang dune 3.3)
(name base-images)
(generate_opam_files true)
(formatting disabled)
(source (github ocurrent/docker-base-images))
(authors "talex5@gmail.com" "anil@recoil.org")
(maintainers "talex5@gmail.com")
(package
 (name base-images)
 (synopsis "Generate Docker base images for OCaml and opam using ocurrent")
 (depends
  (ocaml (>= 4.12))
  (conf-libev (<> :os "win32"))
  (prometheus-app (>= 1.0))
  ppx_sexp_conv
  ppx_deriving_yojson
  ppx_deriving
  (lwt (>= 5.6.1))
  logs
  (fmt (>= 0.8.7))
  current_git
  current_github
  current_docker
  current_ocluster
  current_slack
  current_web
  current_rpc
  (capnp-rpc-unix (>= "1.2.2"))
  (cmdliner (>= "1.1.0"))
  (dockerfile (>= "7.1.0"))
  (dockerfile-opam (>= "7.1.0"))
  (ocaml-version (>= "3.5.0"))))
