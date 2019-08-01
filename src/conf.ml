(* For staging arch-specific builds before creating the manifest. *)
let staging_repo = "ocurrent/opam-staging"      

let public_repo = "ocurrent/opam"

let arm64_builder = "ssh://root@147.75.205.46"

let password_path = "/run/secrets/ocurrent-hub"

let auth =
  if Sys.file_exists password_path then (
    let ch = open_in_bin "/run/secrets/ocurrent-hub" in
    let len = in_channel_length ch in
    let password = really_input_string ch len |> String.trim in
    close_in ch;
    Some ("ocurrent", password)
  ) else (
    Fmt.pr "Password file %S not found; images will not be pushed to hub@." password_path;
    None
  )

module type DOCKER = sig
  include Current_docker.S.DOCKER
  val arch : Ocaml_version.arch
end

module Docker_amd64 = struct
  include Current_docker.Default
  let arch = `X86_64
end

module Docker_arm64 = struct
  include Current_docker.Make(struct let docker_host = Some arm64_builder end)
  let arch = `Aarch64
end
