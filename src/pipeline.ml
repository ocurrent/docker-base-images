open Current.Syntax

module Switch_map = Map.Make(Ocaml_version)

let weekly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 7) ()

let opam_repository () =
  Current_git.clone ~schedule:weekly "git://github.com/ocaml/opam-repository"
  |> Current.map Current_git.Commit.id

(* [latest_alias_of d] is [Some alias] if [d] is the latest version of its distribution family, or [None] otherwise. *)
let latest_alias_of =
  let latest = Dockerfile_distro.latest_distros |> List.map (fun d -> Dockerfile_distro.resolve_alias d, d) in
  fun d -> List.assoc_opt d latest

let master_distro = Dockerfile_distro.(resolve_alias master_distro)

let maybe_add_beta switch =
  let open Dockerfile in
  if Ocaml_version.Releases.is_dev switch then
    run "opam repo add beta git://github.com/ocaml/ocaml-beta-repository --set-default"
  else
    empty

(* Generate a Dockerfile to install OCaml compiler [switch] in [opam_image]. *)
let install_compiler_df ~arch ~switch opam_image =
  let switch_name = Ocaml_version.to_string (Ocaml_version.with_just_major_and_minor switch) in
  let open Dockerfile in
  let personality = if Ocaml_version.arch_is_32bit arch then shell ["/usr/bin/linux32"; "/bin/sh"; "-c"] else empty in
  from opam_image @@
  personality @@
  run "opam-sandbox-disable" @@
  run "opam init -k local -a /home/opam/opam-repository --bare" @@
  maybe_add_beta switch @@
  env ["OPAMYES", "1";
       "OPAMERRLOGLEN", "0";
      ] @@
  run "opam switch create %s %s" switch_name (Ocaml_version.Opam.V2.name switch) @@
  run "rm -rf .opam/repo/default/.git" @@
  run "opam install -y depext" @@
  entrypoint_exec ((if Ocaml_version.arch_is_32bit arch then ["/usr/bin/linux32"] else []) @ ["opam"; "exec"; "--"]) @@
  cmd "bash" @@
  copy ~src:["Dockerfile"] ~dst:"/Dockerfile.ocaml" ()

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

(* Pipeline to build the opam base image and the compiler images for a particular architecture. *)
module Arch = struct
  let install_opam ~arch ~ocluster ~distro ~opam_repository ~push_target =
    let arch_name = Ocaml_version.string_of_arch arch in
    let dockerfile =
      `Contents (
        let opam = snd @@ Dockerfile_opam.gen_opam2_distro ~arch ~clone_opam_repo:false distro in
        let open Dockerfile in
        string_of_t (
          opam @@
          copy ~chown:"opam:opam" ~src:["."] ~dst:"/home/opam/opam-repository" () @@
          copy ~src:["Dockerfile"] ~dst:"/Dockerfile.opam" ()
        )
      )
    in
    let distro_tag = Dockerfile_distro.tag_of_distro distro in
    Current.component "%s@,%s" distro_tag arch_name |>
    let> opam_repository = opam_repository in
    let options = { Cluster_api.Docker.Spec.defaults with squash = true; include_git = true } in
    let cache_hint = Printf.sprintf "opam-%s" distro_tag in
    Current_ocluster.Raw.build_and_push ocluster ~src:[opam_repository] dockerfile
      ~cache_hint
      ~options
      ~push_target
      ~pool:(Conf.pool_for_arch arch)

  let install_compiler ~arch ~ocluster ~switch ~push_target base =
    let arch_name = Ocaml_version.string_of_arch arch in
    Current.component "%s/%s" (Ocaml_version.to_string switch) arch_name |>
    let> base = base in
    let dockerfile = `Contents (install_compiler_df ~arch ~switch base |> Dockerfile.string_of_t) in
    (* ([include_git] doesn't do anything here, but it saves rebuilding during the upgrade) *)
    let options = { Cluster_api.Docker.Spec.defaults with squash = true; include_git = true } in
    let cache_hint = Printf.sprintf "%s-%s-%s" (Ocaml_version.to_string switch) arch_name base in
    Current_ocluster.Raw.build_and_push ocluster ~src:[] dockerfile
      ~cache_hint
      ~options
      ~push_target
      ~pool:(Conf.pool_for_arch arch)

  (* Build the base image for [distro], plus an image for each compiler version. *)
  let pipeline ~ocluster ~opam_repository ~distro arch =
    let opam_image =
      let push_target =
        Tag.v distro ~arch
        |> Cluster_api.Docker.Image_id.of_string
        |> or_die
      in
      install_opam ~arch ~ocluster ~distro ~opam_repository ~push_target
    in
    let compiler_images =
      Conf.switches ~arch ~distro |> List.map @@ fun switch ->
      let push_target =
        Tag.v distro ~switch ~arch
        |> Cluster_api.Docker.Image_id.of_string
        |> or_die
      in
      let repo_id = install_compiler ~arch ~ocluster ~switch ~push_target opam_image in
      (switch, repo_id)
    in
    let compiler_images = Switch_map.of_seq (List.to_seq compiler_images) in
    (opam_image, compiler_images)
end

module Switch_set = Set.Make(Ocaml_version)

let all_switches arches =
  arches |> ListLabels.fold_left ~init:Switch_set.empty ~f:(fun acc map ->
      Switch_map.fold (fun k _v acc -> Switch_set.add k acc) map acc
    )
  |> Switch_set.elements

let notify_status ?channel x =
  match channel with
  | None -> x
  | Some channel ->
    let s =
      let+ state = Current.catch x in
      Fmt.strf "docker-base-images status: %a" (Current_term.Output.pp Current.Unit.pp) state
    in
    Current.all [
      Current_slack.post channel ~key:"base-images-status" s;
      x   (* If [x] fails, the whole pipeline should fail too. *)
    ]

let label l t =
  Current.component "%s" l |>
  let> v = t in
  Current.Primitive.const v

(* The main pipeline. Builds images for all supported distribution, compiler version and architecture combinations. *)
let v ?channel ~ocluster () =
  let repo = opam_repository () in
  Current.all (
    Conf.distros |> List.map @@ fun distro ->
    let distro_label = Dockerfile_distro.tag_of_distro distro in
    let repo = label distro_label repo in
    Current.collapse ~key:"distro" ~value:distro_label ~input:repo @@
    let distro_latest_alias = latest_alias_of distro in
    let arches = Conf.arches_for ~distro in
    let arch_results = List.map (Arch.pipeline ~ocluster ~opam_repository:repo ~distro) arches in
    let opam_images, ocaml_images = List.split arch_results in
    let ocaml_images =
      all_switches ocaml_images |> List.filter_map @@ fun switch ->
      let images = List.filter_map (Switch_map.find_opt switch) ocaml_images in
      if images = [] then None
      else (
        let full_tag = Tag.v distro ~switch in
        let tags =
          (* Push the image as e.g. debian-10-ocaml-4.09: *)
          let tags = [full_tag] in
          if switch <> Ocaml_version.Releases.latest then tags
          else (
            (* For every distro, also create a link to the latest OCaml compiler.
               e.g. debian-9 -> debian-9-ocaml-4.09 *)
            let tags = Tag.v_alias distro :: tags in
            (* If [distro] is the latest version of that distribution, make an alias like
               debian -> debian-10-ocaml-4.09 *)
            match distro_latest_alias with
            | None -> tags
            | Some latest ->
              let tags = Tag.v_alias latest :: tags in
              (* The top-level alias: latest -> debian-10-ocaml-4.09 *)
              if distro <> master_distro then tags
              else Tag.latest :: tags
          )
        in
        (* Fmt.pr "Aliases: %s -> %a@." full_tag Fmt.(Dump.list string) tags; *)
        let pushes = List.map (fun tag -> Current_docker.push_manifest ?auth:Conf.auth ~tag images |> Current.ignore_value) tags in
        Some (full_tag, Current.all pushes)
      )
    in
    Current.all_labelled (
      ("base", Current_docker.push_manifest ?auth:Conf.auth ~tag:(Tag.v distro) opam_images |> Current.ignore_value)
      :: ocaml_images)
  )
  |> notify_status ?channel
