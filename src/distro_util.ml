(* Pure helpers shared by the opam and dune image pipelines. No OCurrent
   dependency, so both [Pipeline_opam] and [Pipeline_dune] can use them without
   either depending on the other. *)

module Distro = Dockerfile_opam.Distro

module Switch_map = Map.Make (Ocaml_version)
module Windows_map = Map.Make (Distro)

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

(* [aliases_of d] gives other tags which should point to [d].
   e.g. just after the Ubuntu 20.04 release, [aliases_of ubuntu-20.04 = [ ubuntu; ubuntu-lts ]] *)
let aliases_of =
  let latest = Distro.distros |> List.map (fun d -> (Distro.resolve_alias d : Distro.distro :> Distro.t), d) in
  fun d -> List.filter_map (fun (d2, alias) -> if d = d2 && d <> alias then Some alias else None) latest

let master_distro = Distro.((resolve_alias master_distro : distro :> t))

(* 2020-04-29: On Windows, squashing images is still experimental (broken). *)
let squash distro =
  Distro.os_family_of_distro distro <> `Windows

(* 2022-07-18: Windows Containers don't support BuildKit.
   https://github.com/microsoft/Windows-Containers/issues/34 *)
let buildkit distro =
  Distro.os_family_of_distro distro <> `Windows

(* The set of all OCaml switches present across a list of per-arch maps. *)
let all_switches arches =
  let module Switch_set = Set.Make (Ocaml_version) in
  arches |> ListLabels.fold_left ~init:Switch_set.empty ~f:(fun acc map ->
      Switch_map.fold (fun k _v acc -> Switch_set.add k acc) map acc)
  |> Switch_set.elements
