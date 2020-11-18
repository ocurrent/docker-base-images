let pp_arch f = function
  | None -> ()
  | Some arch -> Fmt.pf f "-%s" (Ocaml_version.string_of_arch arch)

let tag_of_compiler switch =
  Ocaml_version.to_string ~sep:'-' (Ocaml_version.without_patch switch)
  |> String.map (function   (* e.g. "4.08-fp+flambda-amd64" *)
      | '+' -> '-'
      | x -> x
    )

let v ?arch ?switch distro =
  let repo = if arch = None then Conf.public_repo else Conf.staging_repo in
  let distro =
    if distro = `Debian `Stable then "debian"
    else Dockerfile_distro.tag_of_distro distro
  in
  let switch =
    match switch with
    | Some switch -> "ocaml-" ^ tag_of_compiler switch
    | None -> "opam"
  in
  Fmt.strf "%s:%s-%s%a" repo distro switch pp_arch arch

let v_alias alias =
  let alias =
    if alias = `Debian `Stable then "debian"
    else Dockerfile_distro.tag_of_distro alias
  in
  Fmt.strf "%s:%s" Conf.public_repo alias

let latest =
  Fmt.strf "%s:latest" Conf.public_repo
