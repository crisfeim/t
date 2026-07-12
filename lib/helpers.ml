
let replace_word ~target ~replacement str =
  str
  |> String.split_on_char ' '
  |> List.map (fun word -> if word = target then replacement else word)
  |> List.filter (fun word -> word <> "")
  |> String.concat " "

let string_contains ~needle haystack =
  let nlen = String.length needle in
  let hlen = String.length haystack in
  let rec loop i =
    if i + nlen > hlen then false
    else if String.sub haystack i nlen = needle then true
    else loop (i + 1)
  in
  if nlen = 0 then true else loop 0


let sort_matches projects =
	List.sort (fun path1 path2 ->
		let count1 = List.length (String.split_on_char '/' path1) in
    let count2 = List.length (String.split_on_char '/' path2) in

    if count1 <> count2 then
      compare count1 count2
    else
    	let len1 = String.length path1 in
     	let len2 = String.length path2 in

      if len1 <> len2 then
     		compare len1 len2
      else
     		String.compare path1  path2
	) projects


let first = function
	| first :: _ -> Some first
	| [] -> None

let list_from string = String.split_on_char ',' string


let drop n str =
	if n >=String.length str then ""
	else String.sub str n (String.length str - n)

let is_numeric str = Option.is_some (int_of_string_opt str)
