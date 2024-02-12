val update : unit -> unit

val init_last_build_time : unit -> unit
(** Initialise the previous build time by reading
    the last build time from the OCurrent DB *)

val set_last_build_time_now : unit -> unit
(** Set the last build time to the current time *)
