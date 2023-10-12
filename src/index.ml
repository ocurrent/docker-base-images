module Platform_map = Map.Make (String)
module Switch_map = Map.Make (Ocaml_version)

type state = Ok | Failed | Active
type t = state Switch_map.t Platform_map.t

let v : t ref = ref Platform_map.empty

let update ~platform ~switch state =
  let update_switch_map sm =
    Option.some @@ match sm with
    | None -> Switch_map.singleton switch state
    | Some sm -> Switch_map.update switch (fun _ -> Some state) sm
  in
  v := Platform_map.update platform update_switch_map !v

let get () = !v
