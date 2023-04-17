module Log = struct
  type t = {
    mutable indent : string;
    mutable lines : string list;
  }

  let run fn =
    let t = { indent = ""; lines = [] } in
    fn t;
    List.rev t.lines

  let note t msg =
    let lines =
      String.split_on_char '\n' msg
      |> List.rev_map (function "" -> "" | x -> t.indent ^ x)
    in
    t.lines <- lines @ t.lines

  let with_indent fn t =
    let old = t.indent in
    t.indent <- t.indent ^ "\t";
    let x = fn t in
    t.indent <- old;
    x
end

module Fake = struct
  module Current = struct
    type description = string

    type 'a t = {
      mutable state : [`Ready of (Log.t -> 'a) | `Done of 'a];
    }

    let of_fn f =
      { state = `Ready f }

    module Primitive = struct
      type nonrec 'a t = 'a t
      let const x = of_fn (fun _log -> x)
    end

    module Level = struct
      type nonrec t
    end

    let force t log =
      match t.state with
      | `Ready fn -> let x = fn log in t.state <- `Done x; x
      | `Done x -> x

    let component fmt =
      fmt |> Fmt.kstr @@ fun msg ->
      msg |> String.split_on_char '\n' |> String.concat "/"

    let ignore_value t =
      of_fn (fun log -> ignore (force t log))

    let all xs = of_fn (fun log -> List.iter (fun x -> force x log) xs)
    let all_labelled xs = of_fn (fun log -> List.iter (fun (_l, x) -> force x log) xs)

    let collapse ~key:_ ~value:_ ~input:_ x = x

    module Syntax = struct
      let (let>) x fn description =
        of_fn @@ fun log ->
        let x = force x log in
        Log.note log description;
        Log.with_indent (force (fn x)) log
    end
  end

  module Docker = struct
    let push_manifest ?auth:_ ~tag ids =
      Current.of_fn @@ fun log ->
      let ids = List.map (fun x -> Current.force x log) ids in
      Log.note log @@ Fmt.str "@[<h>%a -> %s@]" Fmt.(list string ~sep:comma) ids tag;
      tag
  end

  module OCluster = struct
    type t = unit

    module Raw = struct
      let build_and_push ?level:_ ?cache_hint:_ () ~push_target ~pool:_ ~src:_ ~options:_ spec =
        Current.of_fn @@ fun log ->
        begin match spec with
          | `Contents c -> Log.note log c;
          | `Path p -> Log.note log p;
        end;
        Cluster_api.Docker.Image_id.to_string push_target
    end
  end
end

module Dump = Pipeline.Make(Fake)

let run () =
  let repos =
    Fake.Current.Primitive.const { Git_repositories.
      opam_repository_master = Current_git.Commit_id.v ~repo:"opam_repository" ~gref:"master" ~hash:"master";
      opam_repository_mingw_sunset = Current_git.Commit_id.v ~repo:"opam_repository_mingw_sunset" ~gref:"sunset" ~hash:"sunset";
      opam_overlays = Current_git.Commit_id.v ~repo:"opam_repository_mingw_overlay" ~gref:"overlay" ~hash:"overlay";
      opam_2_0 = Current_git.Commit_id.v ~repo:"opam" ~gref:"2.0" ~hash:"2.0";
      opam_2_1 = Current_git.Commit_id.v ~repo:"opam" ~gref:"2.1" ~hash:"2.1";
      opam_master = Current_git.Commit_id.v ~repo:"opam" ~gref:"master" ~hash:"master";
    } in
  let log = Log.run @@ Fake.Current.force (Dump.v ~ocluster:() repos) in
  List.iter print_endline log
