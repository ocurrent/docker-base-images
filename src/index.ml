module Platform_map = Map.Make (String)
module Switch_map = Map.Make (Ocaml_version)

type state = Ok | Failed | Active
(* Each platform builds one non-OCaml opam image, and then an image for every version of OCaml *)
type t = state Switch_map.t Platform_map.t * state Platform_map.t

let v : t ref = ref Platform_map.(empty, empty)

let update_images_per_platform ~platform ~switch state =
  let update_switch_map switch sm =
    Option.some @@ match sm with
    | None -> Switch_map.singleton switch state
    | Some sm -> Switch_map.update switch (fun _ -> Some state) sm
  in
  let m = !v in
  match switch with
  | None ->
      v := fst m, Platform_map.update platform (fun _ -> Some state) (snd m)
  | Some switch ->
      v := Platform_map.update platform (update_switch_map switch) (fst m), snd m

let get_images_per_platform () = !v

module Db = Current.Db

type db_t = {
  get_latest_build_time : Sqlite3.stmt;
}

let db =
  lazy
    (let db = Lazy.force Current.Db.v in
     Current_cache.Db.init ();
     let get_latest_build_time =
       Sqlite3.prepare db
         "SELECT MAX(ready) FROM cache WHERE op = 'git-repositories'"
     in
     {
      get_latest_build_time;
     })

let get_latest_build_time () =
  let t = Lazy.force db in
  let ts =
    Db.query t.get_latest_build_time []
    |> List.map @@ function
      | [ ready ] -> ready
      | row -> Fmt.failwith "get_latest_build_time: invalid row %a" Db.dump_row row
  in
  let parse v =
    (* Timedesc parsing will fail without a timezone, so add Z for UTC *)
    let v = Printf.sprintf "%sZ" v in
    match Timedesc.of_iso8601 v with
    | Error msg -> Fmt.failwith "get_latest_build_time: failure parsing %s: %s" v msg
    | Ok v ->
      Timedesc.(to_timestamp_float_s v
      |> min_of_local_dt_result)
      |> Option.some
  in
  match ts with
  | [] -> None
  | [ ready ] ->
    (match ready with
    | Sqlite3.Data.TEXT v -> parse v
    | Sqlite3.Data.NULL -> None
    | _ -> Fmt.failwith "get_latest_build_time: data was not type TEXT")
  | row -> Fmt.failwith "get_latest_build_time: more than one value returned %a" Db.dump_row row
