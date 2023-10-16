module Platform_map = Map.Make (String)
module Switch_map = Map.Make (Ocaml_version)

type state = Ok | Failed | Active
(* Each platform builds one non-OCaml opam image, and then an image for every version of OCaml *)
type t = state Switch_map.t Platform_map.t * state Platform_map.t

let v : t ref = ref Platform_map.(empty, empty)

let update ~platform ~switch state =
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

let get () = !v
