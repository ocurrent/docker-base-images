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

  (* Every branch and tag on [repo] as [(ref, hash)] pairs, e.g.
     [("refs/heads/2.6", "921b53..."); ("refs/tags/2.6.0", "a310b2...")].
     Nothing downstream needs a checkout: the hashes only end up as strings in
     the generated Dockerfile and in the Commit_id handed to the cluster, so
     one [ls-remote] per repository replaces a full clone per version. *)
  let ls_remote ~job repo =
    Current.Process.check_output ~cancellable:true ~job
      ("", [|"git"; "ls-remote"; "--heads"; "--tags"; repo|]) >>!= fun output ->
    String.split_on_char '\n' output
    |> List.filter_map (fun line ->
      match String.index_opt line '\t' with
      | Some i -> Some (String.sub line (i + 1) (String.length line - i - 1), String.sub line 0 i)
      | None -> None)
    |> Result.ok |> Lwt.return

  let branch_hash refs branch =
    match List.assoc_opt ("refs/heads/" ^ branch) refs with
    | Some hash -> Ok hash
    | None -> Error (`Msg (Fmt.str "Branch %S not found" branch))

  (* The newest tag, including alphas, betas and release candidates, so the
     "dev" opam is the newest pre-release and the images only move when the
     opam team tags one.
     Annotated tags are listed twice by ls-remote, as the tag object and as the
     peeled commit ("^{}"); keep the tag object, which is what [git tag] gave. *)
  let latest_release_hash refs =
    let prefix = "refs/tags/" in
    refs
    |> List.filter_map (fun (ref, sha) ->
      match String.(starts_with ~prefix ref, ends_with ~suffix:"^{}" ref) with
      | true, false ->
        let tag = String.sub ref (String.length prefix) (String.length ref - String.length prefix) in
        (match tag.[0] with
         | '0'..'9' ->
           let normalised = String.split_on_char '-' tag |> String.concat "~" in
           Some (OpamVersion.of_string normalised, sha)
         | _ -> None)
      | _ -> None)
    |> List.sort (fun (v1, _) (v2, _) -> OpamVersion.compare v2 v1)
    |> function
    | (_, sha) :: _ -> Ok sha
    | [] -> Error (`Msg "No release tags found")

  let opam_hash refs = function
    | `Dev -> latest_release_hash refs
    | v -> branch_hash refs (Opam_version.branch v)

  let build No_context job { Key.opam_repository; opam; versions } =
    Metrics.set_last_build_time_now ();
    Current.Job.start job ~level:Current.Level.Mostly_harmless >>= fun () ->
    ls_remote ~job opam_repository >>!= fun opam_repository_refs ->
    ls_remote ~job opam >>!= fun opam_refs ->
    Lwt.return @@
    let ( let* ) = Result.bind in
    let* opam_repository_master = branch_hash opam_repository_refs "master" in
    let* opam =
      List.fold_right (fun v acc ->
          let* acc = acc in
          let* hash = opam_hash opam_refs v in
          Ok ((v, hash) :: acc))
        versions (Ok [])
    in
    Ok { Value.opam_repository_master; opam }

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
