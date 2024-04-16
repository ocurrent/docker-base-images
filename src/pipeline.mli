
module Make (OCurrent : S.OCURRENT) : sig
  open OCurrent

  val v : ocluster:OCluster.t -> Git_repositories.t Current.t -> string Current.t list -> unit Current.t
end

val v : ?channel:Current_slack.channel -> ocluster:Current_ocluster.t -> unit -> unit Current.t
(** The main pipeline. Builds images for all supported distribution, compiler version and architecture combinations. *)
