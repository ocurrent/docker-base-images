(* The dune-pkg image variant.

   An ocaml-base variant for `dune pkg` builds: ships `dune` and a ocaml compiler

   This is a self-contained path: it builds FROM the distro base image (not the
   opam base image), is x86_64-only (no dune Linux-arm64 binary), and only
   targets relocatable compilers (OCaml >= 5.5), including their variants
   (e.g. +flambda). *)

module Distro = Dockerfile_opam.Distro

(* --- pure Dockerfile generation -------------------------------------------- *)

(* TODO(dune 3.24): graduate from the date-pinned nightly to a pinned stable
   dune binary once 3.24 is released *)
let nightly_date = "2026-06-11"

(* dune-pkg images are only built for relocatable compilers (OCaml >= 5.5). *)
let min_version = Ocaml_version.of_string_exn "5.5"

(* Whether [switch] gets a dune-pkg image: a compiler >= 5.5 (base or a variant
   such as +flambda) that is lockable against upstream opam-repository (we
   exclude the relocatable overlay). "Lockable" = released, OR a dev version that
   already has a published beta/rc (on track to release). Pure trunk (a dev
   version with no beta yet, e.g. 5.6.0) has no upstream package and is excluded.

   Variants are accepted here (no [without_variant] equality check): the
   selected configure options are expressed to `dune pkg` via the upstream
   `ocaml-options-only-*` packages in [install_df], mirroring how the opam
   pipeline installs variants (see [Ocaml_version.Opam.V2.additional_packages]).
   The variant set is whatever [Conf.switches] yields for the arch (on x86_64 /
   >= 5.5 that is the base plus +afl, +flambda, +no-flat-float-array). *)
let supported_switch switch =
  let same_minor a b =
    Ocaml_version.major a = Ocaml_version.major b
    && Ocaml_version.minor a = Ocaml_version.minor b
  in
  Ocaml_version.compare
    (Ocaml_version.with_just_major_and_minor switch) min_version >= 0
  && (not (Ocaml_version.Releases.is_dev switch)
      || List.exists (same_minor switch) Ocaml_version.Releases.unreleased_betas)

(* dune-pkg images are built for linux distros using apk/apt only. *)
let supported_distro distro =
  Distro.os_family_of_distro distro = `Linux
  && (match Distro.package_manager distro with `Apk | `Apt -> true | _ -> false)

let bootstrap = function
  | `Apk -> "apk add --no-cache build-base m4 git curl ca-certificates tar gzip bzip2 unzip patch coreutils bash rsync"
  | `Apt -> "apt-get update && apt-get install -y --no-install-recommends build-essential m4 git curl ca-certificates tar gzip bzip2 unzip patch coreutils rsync && rm -rf /var/lib/apt/lists/*"
  | _ -> failwith "dune-pkg: only Alpine/Debian are supported"

(* Generate the Dockerfile for the dune-pkg variant of [distro]/[arch] pinned to
   compiler [switch]. Locking against `(repositories upstream)` (opam-repository
   only — no dune/relocatable overlays) resolves the upstream compiler for that
   version, which is relocatable since 5.5.

   When [switch] carries configure variants (e.g. +flambda), the corresponding
   upstream `ocaml-options-only-*` packages are added to the seed's `depends`
   (via [Ocaml_version.Opam.V2.additional_packages]) so the solver picks the
   matching variant compiler — the same packages the opam pipeline installs. *)
let install_df ~distro ~arch ~switch ~dune_date =
  let ocaml_version = Ocaml_version.to_string (Ocaml_version.without_variant switch) in
  let depends =
    let option_packages = Ocaml_version.Opam.V2.additional_packages switch in
    String.concat " "
      (Printf.sprintf "(ocaml (= %s))" ocaml_version :: option_packages)
  in
  let base_image =
    let image, tag = Distro.base_distro_tag ~arch distro in
    Printf.sprintf "%s:%s" image tag
  in
  let target = "x86_64-unknown-linux-musl" in
  let fetch_dune =
    Printf.sprintf
      "curl -fsSL https://get.dune.build/%s/%s/dune-%s-%s.tar.gz | tar xz -C /tmp && install -m 0755 /tmp/dune-%s-%s/dune /usr/local/bin/dune && rm -rf /tmp/dune-%s-%s && dune --version"
      dune_date target dune_date target dune_date target dune_date target
  in
  let open Dockerfile in
  parser_directive (`Syntax "docker/dockerfile:1") @@
  from base_image @@
  run "%s" (bootstrap (Distro.package_manager distro)) @@
  run "%s" fetch_dune @@
  env [
    "XDG_CACHE_HOME", "/dune-cache";
    "DUNE_CACHE", "enabled";
    "DUNE_CACHE_ROOT", "/dune-cache/dune/db";
  ] @@
  (* A throwaway project whose only dependency is the compiler; building it
     populates dune's toolchain cache. Files are written via heredocs (no shell
     printf / escaping). *)
  workdir "/seed" @@
  copy_heredoc ~dst:"dune-project"
    ~src:[heredoc "(lang dune 3.20)\n(package (name seed) (allow_empty) (depends %s))" depends] () @@
  copy_heredoc ~dst:"dune-workspace"
    ~src:[heredoc "(lang dune 3.20)\n(lock_dir (repositories upstream))"] () @@
  copy_heredoc ~dst:"dune" ~src:[heredoc "(executable (name main))"] () @@
  copy_heredoc ~dst:"main.ml" ~src:[heredoc "let () = ()"] () @@
  (* Build the relocatable compiler into dune's cache, then drop the seed's
     build dir and dune's opam-repository clone in the SAME layer so neither is
     committed. `dune pkg lock` needs the clone to resolve, but the compiler is
     reused from the build cache, not the git store. (Mirrors the opam image's
     inline `rm -rf .opam/repo/default/.git`.) *)
  run "dune pkg lock && dune build && rm -rf _build /dune-cache/dune/db/git-repo" @@
  copy ~link:true ~src:["Dockerfile"] ~dst:"/Dockerfile.dune-pkg" ()

(* --- the OCurrent graph ----------------------------------------------------- *)

module Make (OCurrent : S.OCURRENT) = struct
  open OCurrent
  open Current.Syntax

  (* dune-pkg images are x86_64-only for now *)
  let arch = `X86_64

  let update_index current distro switch =
    let+ state = Current.state ~hidden:false current in
    let s = match state with
      | Ok _ -> Index.Ok
      | Error (`Active _) -> Active
      | Error (`Msg _) -> Failed
    in
    Index.update_images_per_platform
      ~platform:(Distro.human_readable_string_of_distro distro ^ " (dune-pkg)")
      ~switch s

  (* Build the dune-pkg image for [distro]/[switch] (FROM the distro base). *)
  let install ~ocluster ~distro ~switch ~push_target =
    Current.component "dune-pkg %s/%s"
      (Ocaml_version.to_string switch) (Ocaml_version.string_of_arch arch) |>
    let> () = Current.return () in
    let dockerfile =
      `Contents (install_df ~distro ~arch ~switch ~dune_date:nightly_date
                 |> Dockerfile.string_of_t)
    in
    let options = { Cluster_api.Docker.Spec.defaults with
                    squash = Distro_util.squash distro;
                    buildkit = Distro_util.buildkit distro;
                    include_git = true } in
    let cache_hint =
      Printf.sprintf "dune-pkg-%s-%s-%s"
        (Distro.tag_of_distro distro) (Ocaml_version.to_string switch)
        (Ocaml_version.string_of_arch arch)
    in
    OCluster.Raw.build_and_push ocluster ~src:[] dockerfile
      ~cache_hint
      ~options
      ~push_target
      ~pool:(Conf.pool_name distro arch)

  (* For one [distro]: build an x86_64 image per supported switch, then push a
     multi-arch manifest per switch (single-arch today) with the opam-style
     distro aliases, e.g. debian-12-dune-ocaml-5.5 plus debian-dune-ocaml-5.5. *)
  let distro_pipeline ~ocluster distro =
    let images =
      Conf.switches ~arch ~distro
      |> List.filter supported_switch
      |> List.map (fun switch ->
          let push_target =
            Tag.dune_pkg distro ~switch ~arch
            |> Cluster_api.Docker.Image_id.of_string
            |> Distro_util.or_die
          in
          let repo_id = install ~ocluster ~distro ~switch ~push_target in
          let _ = update_index repo_id distro (Some switch) in
          (switch, repo_id))
    in
    let pushes =
      images |> List.map (fun (switch, image) ->
          let full_tag = Tag.dune_pkg distro ~switch in
          let tags = full_tag :: List.map (Tag.dune_pkg ~switch) (Distro_util.aliases_of distro) in
          let manifests =
            List.map (fun tag ->
                Docker.push_manifest ?auth:Conf.auth ~tag [image] |> Current.ignore_value)
              tags
          in
          (full_tag, Current.all manifests))
    in
    Current.all_labelled pushes

  let v ~ocluster =
    Conf.distros
    |> List.filter supported_distro
    |> List.map (distro_pipeline ~ocluster)
    |> Current.all
end
