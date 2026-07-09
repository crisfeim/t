type expect =
  { is : bool -> string -> unit
  ; equal : 'a. 'a -> 'a -> unit
  ; fail : string -> unit
  }

val case : string -> ((string -> (expect -> unit) -> unit) -> unit) -> unit
