open Lwt.Infix
open Current.Syntax
module Opam_version = Dockerfile_opam.Opam_version

let ( >>!= ) x f =
  x >>= function
  | Ok y -> f y
  | Error _ as e -> Lwt.return e

module Repositories = struct
  type t = No_context

  let id = "git-repositories"

  module Key = struct
    type t = {
      opam_repository : string;
      opam : string;
      versions : Opam_version.t list;
    }

    let digest { opam_repository; opam; versions } =
      let json = `Assoc [
        "opam-repository", `String opam_repository;
        "opam", `String opam;
        "versions", `List (List.map (fun v -> `String (Opam_version.to_string v)) versions);
      ] in
      Yojson.Safe.to_string json
  end

  module Value = struct
    type hash = string [@@deriving yojson]

    type t = {
      opam_repository_master : hash;
      opam : (Opam_version.t * hash) list;
    } [@@deriving yojson]

    let marshal t = to_yojson t |> Yojson.Safe.to_string

    let unmarshal s =
      match Yojson.Safe.from_string s |> of_yojson with
      | Ppx_deriving_yojson_runtime.Result.Ok x -> x
      | Ppx_deriving_yojson_runtime.Result.Error _ -> failwith "failed to parse Git_repositories.Repositories.Value.t"
  end

  let get_commit_hash ~job ~repo ~branch =
    Current.Process.with_tmpdir ~prefix:"git-checkout" @@ fun cwd ->
    Current.Process.exec ~cwd ~cancellable:true ~job ("", [|"git"; "clone"; "-b"; branch; repo; "."|]) >>!= fun () ->
    Current.Process.check_output ~cwd ~cancellable:true ~job ("", [|"git"; "rev-parse"; "HEAD"|]) >>!= fun hash ->
    Lwt.return (Ok (String.trim hash))

  (* The newest tag, including alphas, betas and release candidates. Tracking
     the head of master instead once pulled in a commit that broke every CI
     on the next image refresh, so the "dev" opam is the newest pre-release. *)
  let get_latest_release_hash ~job ~repo =
    Current.Process.with_tmpdir ~prefix:"git-checkout" @@ fun cwd ->
    Current.Process.exec ~cwd ~cancellable:true ~job ("", [|"git"; "clone"; repo; "."|]) >>!= fun () ->
    Current.Process.check_output ~cwd ~cancellable:true ~job ("", [|"git"; "tag"; "--format"; "%(objectname) %(refname:strip=2)"|]) >>!= fun all_tags ->
    let rec parse = function
      | "" -> []
      | s -> Scanf.sscanf s "%s %s %s@!" (fun sha tag r -> (tag, sha) :: parse r) in
    let hash = parse all_tags
      |> List.filter_map (fun (tag, sha) ->
        match tag.[0] with
        | '0'..'9' ->
          let normalised = String.split_on_char '-' tag |> String.concat "~" in
          Some (OpamVersion.of_string normalised, sha)
        | _ -> None)
      |> List.sort (fun (v1, _) (v2, _) -> OpamVersion.compare v2 v1)
      |> List.hd |> snd in
    Lwt.return (Ok hash)

  let get_opam_hash ~job ~repo = function
    | `Dev -> get_latest_release_hash ~job ~repo
    | v -> get_commit_hash ~job ~repo ~branch:(Opam_version.branch v)

  let build No_context job { Key.opam_repository; opam; versions } =
    Metrics.set_last_build_time_now ();
    Current.Job.start job ~level:Current.Level.Mostly_harmless >>= fun () ->
    get_commit_hash ~job ~repo:opam_repository ~branch:"master" >>!= fun opam_repository_master ->
    let rec hashes acc = function
      | [] -> Lwt.return (Ok (List.rev acc))
      | v :: versions ->
        get_opam_hash ~job ~repo:opam v >>!= fun hash ->
        hashes ((v, hash) :: acc) versions
    in
    hashes [] versions >>!= fun opam ->
    Lwt.return (Ok { Value.opam_repository_master; opam })

  let pp f _ = Fmt.string f "Git repositories"

  let auto_cancel = true
end

module Cache = Current_cache.Make(Repositories)

type t = {
  opam_repository_master : Current_git.Commit_id.t;
  opam : (Opam_version.t * Current_git.Commit_id.t) list;
}

let get ~schedule =
  let key = {
    Repositories.Key.
    opam_repository = "https://github.com/ocaml/opam-repository";
    opam = "https://github.com/ocaml/opam";
    versions = Opam_version.all;
  } in
  let+ { Repositories.Value.opam_repository_master; opam } =
    Current.component "Git-repositories" |>
    let> key = Current.return key in
    Cache.get ~schedule Repositories.No_context key
  in
  {
    opam_repository_master =
      Current_git.Commit_id.v ~repo:key.opam_repository ~gref:"master" ~hash:opam_repository_master;
    opam =
      List.map (fun (v, hash) ->
        (v, Current_git.Commit_id.v ~repo:key.opam ~gref:(Opam_version.branch v) ~hash))
        opam;
  }
