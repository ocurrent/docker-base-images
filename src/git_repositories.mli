type t = {
  opam_repository_master : Current_git.Commit_id.t;
  opam_repository_mingw_opam2 : Current_git.Commit_id.t;
  opam_2_0 : Current_git.Commit_id.t;
  opam_2_1 : Current_git.Commit_id.t;
}

val get : schedule:Current_cache.Schedule.t -> t Current.t
