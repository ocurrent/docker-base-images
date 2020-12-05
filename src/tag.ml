let pp_arch f = function
  | None -> ()
  | Some arch -> Fmt.pf f "-%s" (Ocaml_version.string_of_arch arch)

let tag_of_compiler switch =
  Ocaml_version.to_string ~sep:'-' (Ocaml_version.without_patch switch)
  |> String.map (function   (* e.g. "4.08-fp+flambda-amd64" *)
      | '+' -> '-'
      | x -> x
    )

let make_tag ?arch ?switch distro_tag =
  let repo = if arch = None then Conf.public_repo else Conf.staging_repo in
  let switch =
    match switch with
    | Some switch -> "ocaml-" ^ tag_of_compiler switch
    | None -> "opam"
  in
  Fmt.strf "%s:%s-%s%a" repo distro_tag switch pp_arch arch

let v ?arch ?switch distro =
  make_tag ?arch ?switch (Dockerfile_distro.tag_of_distro distro)

let v_alt ?arch ?switch distro =
  match distro with
  | `Debian `Stable -> [ make_tag ?arch ?switch "debian" ]
  | _ -> []

let v_alias alias =
  let alias = Dockerfile_distro.tag_of_distro alias in
  Fmt.strf "%s:%s" Conf.public_repo alias

let latest =
  Fmt.strf "%s:latest" Conf.public_repo

let archive ?(staging=false) () =
  Fmt.strf "%s:archive" (if staging then Conf.staging_repo else Conf.public_repo)
