val v : ?channel:Current_slack.channel -> ocluster:Current_ocluster.t -> unit -> unit Current.t
(** The main pipeline. Builds images for all supported distribution, compiler version and architecture combinations. *)
