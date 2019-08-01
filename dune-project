(lang dune 1.10)
(generate_opam_files true)

(package
  (name base-images)
  (depends
    (dune (>= 1.10))
    (dockerfile-opam (>= 6.2.0))
  ))
