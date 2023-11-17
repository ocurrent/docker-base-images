open Prometheus

let namespace = "baseimages"
let subsystem = "pipeline"

let family =
  let help = "Number of images by platform" in
  Gauge.v_labels ~label_names:["platform"; "state"] ~help ~namespace ~subsystem
    "image_state_total"

let last_build_time =
  let help = "When the images were last built, in unix time" in
  Gauge.v ~help ~namespace ~subsystem "last_build_time"

let image_valid_time =
  let help = "How long images are valid for until they are rebuilt, in seconds" in
  Gauge.v ~help ~namespace ~subsystem "valid_time"

type stats = { ok : int; failed : int; active : int }
let stats_empty = { ok = 0; failed = 0; active = 0 }

let update () =
  let incr_stats stats = function
    | Index.Ok -> { stats with ok = stats.ok + 1 }
    | Index.Failed -> { stats with failed = stats.failed + 1 }
    | Index.Active -> { stats with active = stats.active + 1 }
  in
  let f opam_map platform sm =
    let stats =
      Index.Switch_map.fold
        (fun _ state stats -> incr_stats stats state)
        sm stats_empty
    in
    let stats =
      Option.map (incr_stats stats) (Index.Platform_map.find_opt platform opam_map)
      |> Option.value ~default:stats
    in
    Gauge.set (Gauge.labels family [platform; "ok"]) (float_of_int stats.ok);
    Gauge.set (Gauge.labels family [platform; "failed"]) (float_of_int stats.failed);
    Gauge.set (Gauge.labels family [platform; "active"]) (float_of_int stats.active)
  in
  let v = Index.get_images_per_platform () in
  Index.Platform_map.iter (f (snd v)) (fst v)

let init_last_build_time () =
  Index.get_latest_build_time ()
  |> Option.iter (Gauge.set last_build_time);
  Gauge.set image_valid_time
    (float_of_int @@ Conf.days_between_rebuilds * 60 * 60 * 24)
(** Initialise the next build time by reading
   the last build time from the OCurrent DB
   and adding `days_between_rebuilds` *)

let set_last_build_time_now () =
  Timedesc.(now ()
  |> to_timestamp_float_s
  |> min_of_local_dt_result)
  |> Gauge.set last_build_time
(** Set the next build time to the current
   time adding `days_between_rebuilds` *)
