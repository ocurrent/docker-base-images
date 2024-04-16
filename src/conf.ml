(* For staging arch-specific builds before creating the manifest. *)
let staging_repo = "ocurrent/opam-staging"

let public_repo = "ocaml/opam"

let password_path =
  let open Fpath in
  let root = v (if Sys.win32 then "C:\\ProgramData\\Docker" else "/run") in
  root / "secrets" / "ocurrent-hub" |> to_string

let days_between_rebuilds = 7

module Capnp = struct
  (* Cap'n Proto RPC is enabled by passing --capnp-public-address. These values are hard-coded
     (because they're just internal to the Docker container). *)
  let secret_key = "/capnp-secrets/secret-key.pem"
  let cap_file = "/capnp-secrets/base-images.cap"
  let internal_port = 9000
end

let auth =
  if Sys.file_exists password_path then (
    let ch = open_in_bin password_path in
    let len = in_channel_length ch in
    let password = really_input_string ch len |> String.trim in
    close_in ch;
    Some ("ocurrent", password)
  ) else (
    None
  )

module Distro = Dockerfile_opam.Distro

let pool_name (distro:Distro.t) arch =
  let os_family = Distro.os_family_of_distro distro in
  let os_str = match os_family with
  | `Cygwin -> "windows"
  | `Windows -> begin match distro with
     | `Windows _ -> "windows-1809"
     | `WindowsServer _ -> "windows"
     | _ -> assert false end
  | `Linux -> "linux"
  in
  let arch_str = match arch with
  | `X86_64 | `I386     -> "x86_64"
  | `Aarch64 | `Aarch32 -> "arm64"
  | `Ppc64le            -> "ppc64"
  | `S390x              -> "s390x"
  | `Riscv64            -> "riscv64" in
  os_str ^ "-" ^ arch_str

let switches ~arch ~distro =
  let is_tier1 = List.mem distro (Distro.active_tier1_distros arch) in
  (* opam-repository-mingw doesn't package the development version of
     the compiler. *)
  (* TODO: Does Windows include alpha, beta, and release candidate versions? *)
  let with_unreleased = match distro with `WindowsServer _ | `Windows _ -> false | _ -> true in
  let filter_windows main_switches =
    (* opam-repository-mingw doesn't package OCaml 5.0.
       TODO: remove when upstream opam gains OCaml packages on Windows. *)
    match distro with
    | `WindowsServer _
    | `Windows _ ->
       List.filter (fun ov -> Ocaml_version.(compare ov Releases.v4_14) <= 0) main_switches
    | _ -> main_switches
  in
  let main_switches =
    Ocaml_version.Releases.(if with_unreleased then recent_with_dev @ unreleased_betas else recent)
    |> List.filter (fun ov -> Distro.distro_supported_on arch ov distro)
    |> filter_windows
  in
  if is_tier1 then (
    List.concat_map (Ocaml_version.Opam.V2.switches arch) main_switches
  ) else (
    main_switches
  )

(* We can't get the active distros directly, but assume x86_64 is a superset of everything else. *)
let distros = Distro.(active_distros `X86_64 |> List.filter (fun d ->
  match os_family_of_distro d with
  | `Linux | `Windows -> true
  | _ -> false))

let windows_distros = Distro.(latest_distros |> List.filter (fun d ->
  match os_family_of_distro d with
  | `Windows -> true
  | _ -> false)
  |> List.map (fun d ->
     let bdt = base_distro_tag d in
     (fst bdt) ^ ":" ^ (snd bdt), pool_name d `X86_64))

let arches_for ~distro =
  match distro with
  (* opam-repository-mingw doesn't package OCaml 5.0.
     TODO: remove when upstream opam gains OCaml packages on Windows. *)
  | `WindowsServer _
  | `Windows _ -> Distro.distro_arches Ocaml_version.Releases.v4_14 distro
  | `Ubuntu (`V23_10) ->
    (* There does not yet exist risc-v ubuntu 23.10 docker images
       https://github.com/ocurrent/docker-base-images/issues/206 *)
    Distro.distro_arches Ocaml_version.Releases.latest distro
    |> List.filter (fun arch -> arch != `Riscv64)
  | _ -> Distro.distro_arches Ocaml_version.Releases.latest distro

(* For testing, you can uncomment these lines to limit the number of combinations: *)

(*
let distros = ignore distros; [`Debian `V11]
let switches ~arch:_ ~distro:_ = ignore switches; Ocaml_version.Releases.[v4_08]
let arches_for ~distro:_ = ignore arches_for; [`X86_64]
*)
