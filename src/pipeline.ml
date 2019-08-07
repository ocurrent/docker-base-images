open Current.Syntax

module Switch_map = Map.Make(Ocaml_version)

let weekly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 7) ()

let opam_repository () =
  Current_git.clone ~schedule:weekly "git://github.com/ocaml/opam-repository"

let switches ~arch ~distro =
  Ocaml_version.Releases.recent
  |> List.filter (fun ov -> Dockerfile_distro.distro_supported_on arch ov distro)

(* We can't get the active distros directly, but assume x86_64 is a superset of everything else. *)
let distros = Dockerfile_distro.active_distros `X86_64

let arches_for ~distro = Dockerfile_distro.distro_arches Ocaml_version.Releases.latest distro

(*
let distros = ignore distros; [`Debian `V10]
let switches ~arch:_ ~distro:_ = ignore switches; Ocaml_version.Releases.[v4_08]
let arches_for ~distro:_ = ignore arches_for; [`X86_64]
*)

(* Prevent `.byte` executables from being installed, if possible. *)
let try_disable_bytes _switch =
  let open Dockerfile in
  (* Doesn't work, due to https://github.com/ocaml/ocaml/issues/8855 *)
  (*
  if Ocaml_version.compare switch Ocaml_version.Releases.v4_08_0 >= 0 then (
    run "sed -i 's!\"./configure\"!\"./configure\" \"--disable-installing-bytecode-programs\"!' \
         /home/opam/opam-repository/packages/ocaml-base-compiler/%s/opam" (Ocaml_version.Opam.V2.name switch) @@
    run "cd opam-repository && git commit -a -m 'Disable bytecode binaries to save space'"
  ) else
  *)
  empty

(* Generate a Dockerfile to install OCaml compiler [switch] in [opam_image]. *)
let install_compiler_df ~switch opam_image =
  let switch_name = Ocaml_version.to_string (Ocaml_version.with_just_major_and_minor switch) in
  let open Dockerfile in
  from opam_image @@
  run "opam-sandbox-disable" @@
  try_disable_bytes switch @@
  run "opam init -k local -a /home/opam/opam-repository --bare" @@
  run "opam switch create %s %s" switch_name (Ocaml_version.Opam.V2.name switch) @@
  run "rm -rf .opam/repo/default/.git" @@
  run "opam install -y depext" @@
  env ["OPAMYES", "1"] @@
  entrypoint_exec ["opam"; "config"; "exec"; "--"] @@
  cmd "bash" @@
  copy ~src:["Dockerfile"] ~dst:"/Dockerfile.ocaml" ()

(* Pipeline to build the opam base image and the compiler images for a particular architecture. *)
module Arch(Docker : Conf.DOCKER) = struct
  let build_pool = Lwt_pool.create 10 Lwt.return

  let arch_name = Ocaml_version.string_of_arch Docker.arch

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
    let label = Fmt.strf "%s/%s" (Dockerfile_distro.tag_of_distro distro) arch_name in
    Docker.build ~pool:build_pool ~label ~squash:true ~dockerfile ~pull:true (`Git opam_repository)

  let install_compiler ~switch base =
    let dockerfile =
      let+ base = base in
      install_compiler_df ~switch (Docker.Image.hash base)
    in
    let switch_name = Ocaml_version.to_string (Ocaml_version.with_just_major_and_minor switch) in
    Docker.build ~pool:build_pool ~label:switch_name ~squash:true ~dockerfile ~pull:false `No_context

  (* Tag [image] as [tag] and push to hub (if pushing is configured). *)
  let push image ~tag =
    match Conf.auth with
    | None -> let+ () = Docker.tag image ~tag in tag
    | Some auth -> Docker.push ~auth image ~tag

  (* Build the base image for [distro], plus an image for each compiler version. *)
  let pipeline ~opam_repository ~distro =
    let opam_image = install_opam ~distro ~opam_repository in
    let compiler_images =
      switches ~arch:Docker.arch ~distro |> List.map @@ fun switch ->
      let ocaml_image = install_compiler ~switch opam_image in
      let repo_id = push ocaml_image ~tag:(Tag.v distro ~switch ~arch:Docker.arch) in
      (switch, repo_id)
    in
    let compiler_images = Switch_map.of_seq (List.to_seq compiler_images) in
    let base_image = push opam_image ~tag:(Tag.v distro ~arch:Docker.arch) in
    (base_image, compiler_images)
end

module Amd64 = Arch(Conf.Docker_amd64)
module Arm64 = Arch(Conf.Docker_arm64)
module Ppc64 = Arch(Conf.Docker_ppc64)

let build_for_arch ~opam_repository ~distro = function
  | `Aarch64 -> Some (Arm64.pipeline ~opam_repository ~distro)
  | `X86_64 -> Some (Amd64.pipeline ~opam_repository ~distro)
  | `Ppc64le -> Some (Ppc64.pipeline ~opam_repository ~distro)
  | `Aarch32 -> None

(* The main pipeline. Builds images for all supported distribution, compiler version and architecture combinations. *)
let v () =
  let repo = opam_repository () in
  Current.all (
    distros |> List.map @@ fun distro ->
    let arches = arches_for ~distro in
    let arch_results = List.filter_map (build_for_arch ~opam_repository:repo ~distro) arches in
    let opam_images, ocaml_images = List.split arch_results in
    let ocaml_images =
      Ocaml_version.Releases.all |> List.filter_map @@ fun switch ->
      let images = List.filter_map (Switch_map.find_opt switch) ocaml_images in
      if images = [] then None
      else (
        let tag = Tag.v distro ~switch in
        Some (Current_docker.push_manifest ?auth:Conf.auth ~tag images)
      )
    in
    Current.all (Current_docker.push_manifest ?auth:Conf.auth ~tag:(Tag.v distro) opam_images :: ocaml_images)
  )
