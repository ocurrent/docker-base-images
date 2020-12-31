open Current.Syntax

module Switch_map = Map.Make(Ocaml_version)

let weekly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 7) ()

let git_repositories () =
  Git_repositories.get ~schedule:weekly

(* [aliases_of d] gives other tags which should point to [d].
   e.g. just after the Ubuntu 20.04 release, [aliases_of ubuntu-20.04 = [ ubuntu; ubuntu-lts ]] *)
let aliases_of =
  let latest = Dockerfile_distro.latest_distros |> List.map (fun d -> Dockerfile_distro.resolve_alias d, d) in
  fun d -> List.filter_map (fun (d2, alias) -> if d = d2 then Some alias else None) latest

let master_distro = Dockerfile_distro.(resolve_alias master_distro)

let maybe_add_beta switch =
  let open Dockerfile in
  if Ocaml_version.Releases.is_dev switch then
    run "opam repo add beta git://github.com/ocaml/ocaml-beta-repository --set-default"
  else
    empty

let maybe_add_multicore switch =
  let open Dockerfile in
  if Ocaml_version.Configure_options.is_multicore switch then
    run "opam repo add multicore git://github.com/ocaml-multicore/multicore-opam --set-default"
  else
    empty

let maybe_install_secondary_compiler ~switch =
  let dune_min_native_support = Ocaml_version.Releases.v4_08 in
  let open Dockerfile in
  if Ocaml_version.compare switch dune_min_native_support < 0 then
    run "opam install -y ocaml-secondary-compiler"
  else
    empty

let install_package_archive opam_image =
  let open Dockerfile in
  from ~alias:"archive" opam_image @@
  workdir "/home/opam/opam-repository" @@
  run "opam admin cache --link=/home/opam/opam-repository/cache" @@
  from "alpine:latest" @@
  copy ~chown:"0:0" ~from:"archive" ~src:["/home/opam/opam-repository/cache"] ~dst:"/cache" ()

(* Generate a Dockerfile to install OCaml compiler [switch] in [opam_image]. *)
let install_compiler_df ~arch ~switch opam_image =
  let switch_name = Ocaml_version.to_string (Ocaml_version.with_just_major_and_minor switch) in
  let (package_name, package_version) = Ocaml_version.Opam.V2.package switch in
  let additional_packages = Ocaml_version.Opam.V2.additional_packages switch in
  let open Dockerfile in
  let personality = if Ocaml_version.arch_is_32bit arch then shell ["/usr/bin/linux32"; "/bin/sh"; "-c"] else empty in
  from opam_image @@
  personality @@
  maybe_add_beta switch @@
  maybe_add_multicore switch @@
  env ["OPAMYES", "1";
       "OPAMCONFIRMLEVEL", "unsafe-yes";
       "OPAMERRLOGLEN", "0"; (* Show the whole log if it fails *)
       "OPAMPRECISETRACKING", "1"; (* Mitigate https://github.com/ocaml/opam/issues/3997 *)
      ] @@
  run "opam switch create %s --packages=%s" switch_name (String.concat "," (Printf.sprintf "%s.%s" package_name package_version :: additional_packages)) @@
  run "opam pin add -k version %s %s" package_name package_version @@
  run "opam install -y opam-depext" @@
  maybe_install_secondary_compiler ~switch @@
  entrypoint_exec ((if Ocaml_version.arch_is_32bit arch then ["/usr/bin/linux32"] else []) @ ["opam"; "exec"; "--"]) @@
  cmd "bash" @@
  copy ~src:["Dockerfile"] ~dst:"/Dockerfile.ocaml" ()

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

(* Pipeline to build the opam base image and the compiler images for a particular architecture. *)
module Arch = struct
  let install_opam ~arch ~ocluster ~distro ~repos ~push_target =
    let arch_name = Ocaml_version.string_of_arch arch in
    let distro_tag = Dockerfile_distro.tag_of_distro distro in
    Current.component "%s@,%s" distro_tag arch_name |>
    let> {Git_repositories.opam_repository_master; opam_2_0; opam_2_1} = repos in
    let dockerfile =
      let hash_opam_2_0 = Current_git.Commit_id.hash opam_2_0 in
      let hash_opam_2_1 = Current_git.Commit_id.hash opam_2_1 in
      `Contents (
        let opam = snd @@ Dockerfile_opam.gen_opam2_distro ~arch ~clone_opam_repo:false ~hash_opam_2_0 ~hash_opam_2_1 distro in
        let open Dockerfile in
        string_of_t (
          opam @@
          copy ~chown:"opam:opam" ~src:["."] ~dst:"/home/opam/opam-repository" () @@
          run "opam-sandbox-disable" @@
          run "opam init -k local -a /home/opam/opam-repository --bare" @@
          run "rm -rf .opam/repo/default/.git" @@
          copy ~src:["Dockerfile"] ~dst:"/Dockerfile.opam" ()
        )
      )
    in
    let options = { Cluster_api.Docker.Spec.defaults with squash = true; include_git = true } in
    let cache_hint = Printf.sprintf "opam-%s" distro_tag in
    Current_ocluster.Raw.build_and_push ocluster ~src:[opam_repository_master] dockerfile
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

  let collect_archive ~ocluster ~push_target base =
    Current.component "archive" |>
    let> base = base in
    let dockerfile = `Contents (install_package_archive base |> Dockerfile.string_of_t) in
    let options = { Cluster_api.Docker.Spec.defaults with squash = true; include_git = true } in
    let cache_hint = Printf.sprintf "archive-%s" base in
    Current_ocluster.Raw.build_and_push ocluster ~src:[] dockerfile
      ~cache_hint
      ~options
      ~push_target
      ~pool:(Conf.pool_for_arch `X86_64)

  (* Build the base image for [distro], plus an image for each compiler version. *)
  let pipeline ~ocluster ~repos ~distro arch =
    let opam_image =
      let push_target =
        Tag.v distro ~arch
        |> Cluster_api.Docker.Image_id.of_string
        |> or_die
      in
      install_opam ~arch ~ocluster ~distro ~repos ~push_target
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
    (* Build the archive image for the debian 10 / x86_64 image only *)
    let archive_image =
      if distro = Dockerfile_distro.(master_distro |> resolve_alias) && arch = `X86_64 then
        let push_target =
          Tag.archive ~staging:true ()
          |> Cluster_api.Docker.Image_id.of_string
          |> or_die
        in
        Some (collect_archive ~ocluster ~push_target opam_image)
      else None
    in
    let compiler_images = Switch_map.of_seq (List.to_seq compiler_images) in
    (opam_image, compiler_images, archive_image)
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
      Fmt.str "docker-base-images status: %a" (Current_term.Output.pp Current.Unit.pp) state
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
  let repos = git_repositories () in
  Current.all (
    Conf.distros |> List.map @@ fun distro ->
    let distro_label = Dockerfile_distro.tag_of_distro distro in
    let repos = label distro_label repos in
    Current.collapse ~key:"distro" ~value:distro_label ~input:repos @@
    let distro_aliases = aliases_of distro in
    let arches = Conf.arches_for ~distro in
    let arch_results = List.map (Arch.pipeline ~ocluster ~repos ~distro) arches in
    let opam_images, ocaml_images, archive_image =
      List.fold_left (fun (aa,ba,ca) (a,b,c) ->
        let ca = match ca,c with Some v, _ -> Some v | None, v -> v in
        a::aa, b::ba, ca) ([], [], None) arch_results in
    let ocaml_images =
      all_switches ocaml_images |> List.filter_map @@ fun switch ->
      let images = List.filter_map (Switch_map.find_opt switch) ocaml_images in
      if images = [] then None
      else (
        let full_tag = Tag.v distro ~switch in
        let tags =
          (* Push the image as e.g. debian-10-ocaml-4.09 and debian-ocaml-4.09 *)
          let tags = full_tag :: List.map (Tag.v ~switch) distro_aliases in
          if switch <> Ocaml_version.Releases.latest then tags
          else (
            (* For every distro, also create a link to the latest OCaml compiler.
               e.g. debian-9 -> debian-9-ocaml-4.09 *)
            let tags = Tag.v_alias distro :: tags in
            (* If [distro] is the latest version of that distribution, make an alias like
               debian -> debian-10-ocaml-4.09 *)
            let tags = List.map Tag.v_alias distro_aliases @ tags in
            (* The top-level alias: latest -> debian-10-ocaml-4.09 *)
            if distro <> master_distro then tags
            else Tag.latest :: tags
          )
        in
        (* Fmt.pr "Aliases: %s -> %a@." full_tag Fmt.(Dump.list string) (List.sort String.compare tags); *)
        let pushes = List.map (fun tag -> Current_docker.push_manifest ?auth:Conf.auth ~tag images |> Current.ignore_value) tags in
        Some (full_tag, Current.all pushes)
      )
    in
    let archive_images =
      match archive_image with
      | None -> []
      | Some image -> [ "archive", Current_docker.push_manifest ?auth:Conf.auth ~tag:(Tag.archive ()) [image] |> Current.ignore_value ]
    in
    Current.all_labelled (
     ("base", Current_docker.push_manifest ?auth:Conf.auth ~tag:(Tag.v distro) opam_images |> Current.ignore_value)
      :: ocaml_images
      @ archive_images)
  )
  |> notify_status ?channel
