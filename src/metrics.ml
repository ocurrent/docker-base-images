open Prometheus

let namespace = "baseimages"
let subsystem = "pipeline"

let platform_family =
  let help = "Number of images by platform" in
  Gauge.v_labels ~label_names:["platform"; "state"] ~help ~namespace ~subsystem
    "image_platform_state_total"

let version_family =
  let help = "Number of images by OCaml version" in
  Gauge.v_labels ~label_names:["version"; "state"] ~help ~namespace ~subsystem
    "image_version_state_total"

let last_build_time =
  let help = "When the images were last built, in unix time" in
  Gauge.v ~help ~namespace ~subsystem "last_build_time"

let image_valid_time =
  let help = "How long images are valid for until they are rebuilt, in seconds" in
  Gauge.v ~help ~namespace ~subsystem "valid_time"

type stats = { ok : int; failed : int; active : int }
let stats_empty = { ok = 0; failed = 0; active = 0 }

open Index

let incr_stats stats = function
  | Ok -> { stats with ok = stats.ok + 1 }
  | Failed -> { stats with failed = stats.failed + 1 }
  | Active -> { stats with active = stats.active + 1 }

let update_images_per_platform ocaml_images non_ocaml_images =
  let f opam_map platform sm =
    let stats =
      Switch_map.fold
        (fun _ state stats -> incr_stats stats state)
        sm stats_empty
    in
    let stats =
      Option.map (incr_stats stats) (Platform_map.find_opt platform opam_map)
      |> Option.value ~default:stats
    in
    Gauge.set (Gauge.labels platform_family [platform; "ok"])
      (float_of_int stats.ok);
    Gauge.set (Gauge.labels platform_family [platform; "failed"])
      (float_of_int stats.failed);
    Gauge.set (Gauge.labels platform_family [platform; "active"])
      (float_of_int stats.active)
  in
  Platform_map.iter (f non_ocaml_images) ocaml_images

let update_images_per_version ocaml_images =
  let f v state acc =
    let stats =
      Option.value ~default:stats_empty @@ Switch_map.find_opt v acc
    in
    Switch_map.add v (incr_stats stats state) acc
  in
  let stats =
    Platform_map.fold (fun _ sm acc -> Switch_map.fold f sm acc)
      ocaml_images Switch_map.empty
  in
  Switch_map.iter (fun v stats ->
    let version = Ocaml_version.to_string v in
    Gauge.set (Gauge.labels version_family [version; "ok"])
      (float_of_int stats.ok);
    Gauge.set (Gauge.labels version_family [version; "failed"])
      (float_of_int stats.failed);
    Gauge.set (Gauge.labels version_family [version; "active"])
      (float_of_int stats.active))
    stats

let update () =
  let ocaml_images, non_ocaml_images = get_images_per_platform () in
  update_images_per_platform ocaml_images non_ocaml_images;
  update_images_per_version ocaml_images

let init_last_build_time () =
  get_latest_build_time ()
  |> Option.iter (Gauge.set last_build_time);
  Gauge.set image_valid_time
    (float_of_int @@ Conf.days_between_rebuilds * 60 * 60 * 24)

let set_last_build_time_now () =
  Timedesc.(now ()
  |> to_timestamp_float_s
  |> min_of_local_date_time_result)
  |> Gauge.set last_build_time
