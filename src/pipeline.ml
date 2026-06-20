(* Top-level orchestration. The actual image construction lives in two
   independent paths:
     - [Pipeline_opam]: the opam base images + per-compiler images (all
       distros/arches/versions; the bulk of the matrix).
     - [Pipeline_dune]: the dune-pkg image variant (x86_64-only, apk/apt linux,
       OCaml >= 5.5; ships dune + a baked relocatable compiler, no opam).
   Shared pure helpers live in [Distro_util]. *)

(* Re-exported so existing consumers (dump.ml, base_images.ml) are unchanged. *)
module Switch_map = Distro_util.Switch_map
module Windows_map = Distro_util.Windows_map

let weekly = Current_cache.Schedule.v ~valid_for:(Duration.of_day Conf.days_between_rebuilds) ()
let daily = Current_cache.Schedule.v ~valid_for:(Duration.of_day 1) ()

let win_ver ocluster =
  Conf.windows_distros
  |> List.fold_left (fun m (distro, product, pool) ->
    let w = Win_ver.get ~schedule:daily ocluster product pool in
    Windows_map.add distro w m) Windows_map.empty

let git_repositories () =
  Git_repositories.get ~schedule:weekly

(* The main pipeline: the opam path and the dune-pkg path, run side by side. *)
module Make (OCurrent : S.OCURRENT) = struct
  module Opam = Pipeline_opam.Make (OCurrent)
  module Dune = Pipeline_dune.Make (OCurrent)

  let v ~ocluster ~repos ~windows_version =
    OCurrent.Current.all [
      Opam.v ~ocluster ~repos ~windows_version;
      Dune.v ~ocluster;
    ]
end

module Real = Make(struct
    module Current = Current
    module OCluster = Current_ocluster
    module Docker = Current_docker
  end)

open Current.Syntax

let notify_status ?channel x =
  match channel with
  | None -> x
  | Some channel ->
    let s =
      let+ state = Current.catch x in
      Fmt.str "docker-base-images status: %a" (Current_term.Output.pp Current.Unit.pp) state
    in
    Current.all [
      Current_slack.post channel ~key:"base-images-status" s;
      x   (* If [x] fails, the whole pipeline should fail too. *)
    ]

let v ?channel ~connection ~ocluster () =
  if Conf.auth = None then Fmt.pr "Password file %S not found; images will not be pushed to hub@." Conf.password_path;
  let repos = git_repositories () in
  let wv = win_ver connection  in
  Real.v ~ocluster ~repos ~windows_version:wv |> notify_status ?channel
