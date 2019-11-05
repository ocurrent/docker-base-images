open Current.Syntax

module Switch_map = Map.Make(Ocaml_version)

let weekly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 7) ()

let opam_repository () =
  Current_git.clone ~schedule:weekly "git://github.com/ocaml/opam-repository"

(* [latest_alias_of d] is [Some alias] if [d] is the latest version of its distribution family, or [None] otherwise. *)
let latest_alias_of =
  let latest = Dockerfile_distro.latest_distros |> List.map (fun d -> Dockerfile_distro.resolve_alias d, d) in
  fun d -> List.assoc_opt d latest

let master_distro = Dockerfile_distro.(resolve_alias master_distro)

(* Prevent `.byte` executables from being installed, if possible. *)
let try_disable_bytes switch =
  let open Dockerfile in
  if Ocaml_version.compare switch Ocaml_version.Releases.v4_10_0 >= 0 then (
    run "sed -i 's!\"./configure\"!\"./configure\" \"--disable-installing-bytecode-programs\"!' \
         /home/opam/opam-repository/packages/ocaml-variants/%s/opam" (Ocaml_version.Opam.V2.name switch) @@
    run "cd opam-repository && git commit -a -m 'Disable bytecode binaries to save space'"
  ) else
  empty

let maybe_add_beta switch =
  let open Dockerfile in
  if Ocaml_version.Releases.is_dev switch then
    run "opam repo add beta git://github.com/ocaml/ocaml-beta-repository --set-default"
  else
    empty

(* Generate a Dockerfile to install OCaml compiler [switch] in [opam_image]. *)
let install_compiler_df ~switch opam_image =
  let switch_name = Ocaml_version.to_string (Ocaml_version.with_just_major_and_minor switch) in
  let open Dockerfile in
  from opam_image @@
  run "opam-sandbox-disable" @@
  try_disable_bytes switch @@
  run "opam init -k local -a /home/opam/opam-repository --bare" @@
  maybe_add_beta switch @@
  env ["OPAMYES", "1";
       "OPAMERRLOGLEN", "0";
      ] @@
  run "opam switch create %s %s" switch_name (Ocaml_version.Opam.V2.name switch) @@
  run "rm -rf .opam/repo/default/.git" @@
  run "opam install -y depext" @@
  entrypoint_exec ["opam"; "config"; "exec"; "--"] @@
  cmd "bash" @@
  copy ~src:["Dockerfile"] ~dst:"/Dockerfile.ocaml" ()

(* Pipeline to build the opam base image and the compiler images for a particular architecture. *)
module Arch(Docker : Conf.DOCKER) = struct
  let arch_name = Ocaml_version.string_of_arch Docker.arch

  let build_pool =
    let label = Fmt.strf "docker-%s" Docker.label in
    Current.Pool.create ~label Docker.pool_size

  let install_opam ~distro ~opam_repository =
    let dockerfile =
      Current.return (
        let opam = snd @@ Dockerfile_opam.gen_opam2_distro distro in
        let open Dockerfile in
        opam @@
        copy ~chown:"opam:opam" ~src:["."] ~dst:"/home/opam/opam-repository" () @@
        copy ~src:["Dockerfile"] ~dst:"/Dockerfile.opam" ()
      )
    in
    let label = Fmt.strf "%s@,%s" (Dockerfile_distro.tag_of_distro distro) arch_name in
    Docker.build ~pool:build_pool ~label ~squash:true ~dockerfile ~pull:true (`Git opam_repository)

  let install_compiler ~switch base =
    let dockerfile =
      let+ base = base in
      install_compiler_df ~switch base
    in
    let label = Fmt.strf "%s/%s" (Ocaml_version.to_string switch) arch_name in
    Docker.build ~pool:build_pool ~label ~squash:true ~dockerfile ~pull:false `No_context

  (* Tag [image] as [tag] and push to hub (if pushing is configured). *)
  let push image ~tag =
    match Conf.auth with
    | None -> let+ () = Docker.tag image ~tag in tag
    | Some auth -> Docker.push ~auth image ~tag

  (* Build the base image for [distro], plus an image for each compiler version. *)
  let pipeline ~opam_repository ~distro =
    let opam_image =
      install_opam ~distro ~opam_repository
      |> push ~tag:(Tag.v distro ~arch:Docker.arch)
    in
    let compiler_images =
      Conf.switches ~arch:Docker.arch ~distro |> List.map @@ fun switch ->
      let ocaml_image = install_compiler ~switch opam_image in
      let repo_id = push ocaml_image ~tag:(Tag.v distro ~switch ~arch:Docker.arch) in
      (switch, repo_id)
    in
    let compiler_images = Switch_map.of_seq (List.to_seq compiler_images) in
    (opam_image, compiler_images)
end

module Amd64 = Arch(Conf.Docker_amd64)
module Arm32_1 = Arch(Conf.Docker_arm32_1)
module Arm32_2 = Arch(Conf.Docker_arm32_2)
module Arm64 = Arch(Conf.Docker_arm64)
module Ppc64 = Arch(Conf.Docker_ppc64)

let build_for_arch ~opam_repository ~distro = function
  | `Aarch64 -> Some (Arm64.pipeline ~opam_repository ~distro)
  | `X86_64 -> Some (Amd64.pipeline ~opam_repository ~distro)
  | `Ppc64le -> Some (Ppc64.pipeline ~opam_repository ~distro)
  | `Aarch32 when distro = `Debian `V10 -> Some (Arm32_1.pipeline ~opam_repository ~distro)
  | `Aarch32 -> Some (Arm32_2.pipeline ~opam_repository ~distro)

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

(* The main pipeline. Builds images for all supported distribution, compiler version and architecture combinations. *)
let v ?channel () =
  let repo = opam_repository () in
  Current.all (
    Conf.distros |> List.map @@ fun distro ->
    let distro_latest_alias = latest_alias_of distro in
    let arches = Conf.arches_for ~distro in
    let arch_results = List.filter_map (build_for_arch ~opam_repository:repo ~distro) arches in
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
            (* If [distro] is the latest version of that distribuion, make an alias like
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
        let pushes = List.map (fun tag -> Current_docker.push_manifest ?auth:Conf.auth ~tag images) tags in
        Some (full_tag, Current.all pushes)
      )
    in
    Current.all_labelled (
      ("base", Current_docker.push_manifest ?auth:Conf.auth ~tag:(Tag.v distro) opam_images)
      :: ocaml_images)
  )
  |> notify_status ?channel
