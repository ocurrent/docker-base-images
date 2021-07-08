(* The parts of the OCurrent API that we use. These can be replaced for tests. *)
module type OCURRENT = sig
  module Current : sig
    type 'a t
    type description

    module Primitive : sig
      type 'a t
      val const : 'a -> 'a t
    end

    val component : ('a, Format.formatter, unit, description) format4 -> 'a
    val ignore_value : 'a t -> unit t
    val all : unit t list -> unit t
    val all_labelled : (string * unit t) list -> unit t
    val collapse : key:string -> value:string -> input:_ t -> 'a t -> 'a t

    module Syntax : sig
      val (let>) : 'a t -> ('a -> 'b Primitive.t) -> description -> 'b t
    end
  end

  module Docker : sig
    val push_manifest : ?auth:(string * string) -> tag:string -> Current_docker.S.repo_id Current.t list -> Current_docker.S.repo_id Current.t
  end

  module OCluster : sig
    type t

    module Raw : sig
      val build_and_push :
        ?cache_hint:string -> t -> push_target:Cluster_api.Docker.Image_id.t -> pool:string ->
        src:Current_git.Commit_id.t list -> options:Cluster_api.Docker.Spec.options -> [ `Contents of string | `Path of string ] ->
        string Current.Primitive.t
    end
  end
end
