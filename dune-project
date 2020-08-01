(lang dune 2.5)
(generate_opam_files true)
(formatting disabled)

(source (github ocurrent/docker-base-images))
(authors "talex5@gmail.com" "anil@recoil.org")
(maintainers "talex5@gmail.com")

(package
  (name base-images)
  (synopsis "generate Docker base images for OCaml and opam using ocurrent")
  (depends
    current_git
    current_github
    current_docker
    current_ocluster
    current_slack
    current_web
    current_rpc
    (capnp-rpc-unix (>= "0.7.0"))
    (dockerfile (>= "6.2.0"))
    (dockerfile-opam (>= "6.2.0"))
    (ocaml-version (>= "2.6.1"))
  ))
