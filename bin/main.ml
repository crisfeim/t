open T

let () =
  (* Sys.argv es un array con los argumentos recibidos.
     El índice 0 es el nombre del ejecutable; el resto son tus argumentos. *)
  let args = Array.to_list Sys.argv in

  Printf.printf "\n--- Argumentos recibidos por OCaml ---\n";
  List.iteri (fun i arg -> Printf.printf "Argumento [%d]: %s\n" i arg) args;
  Printf.printf "--------------------------------------\n\n"
