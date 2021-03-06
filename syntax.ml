open Format
open Support.Error
open Support.Pervasive

(* ---------------------------------------------------------------------- *)
(* Datatypes *)

type ty =
    TyVar of int * int
  | TyId of string
  | TyArr of ty * ty
  | TyUnit
  | TyRecord of (string * ty) list
  | TyVariant of (string * ty) list
  | TyBool
  | TyString
  | TyFloat
  | TyNat
  (* @yzy for chord normalizer *)
  | TyNote of int
  | TyNoteset of int
  | TyPhrase of int * int
  | TySegment of int * string
  | TyPassage of int * string * int * string
  | TyExportPsg

type term =
    TmTrue of info
  | TmFalse of info
  | TmIf of info * term * term * term
  | TmCase of info * term * (string * (string * term)) list
  | TmTag of info * string * term * ty
  | TmVar of info * int * int
  | TmAbs of info * string * ty * term
  | TmApp of info * term * term
  | TmLet of info * string * term * term
  | TmFix of info * term
  | TmString of info * string
  | TmUnit of info
  | TmAscribe of info * term * ty
  | TmRecord of info * (string * term) list
  | TmProj of info * term * string
  | TmFloat of info * float
  | TmTimesfloat of info * term * term
  | TmZero of info
  | TmSucc of info * term
  | TmPred of info * term
  | TmIsZero of info * term
  | TmInert of info * ty
  (* @yzy for chord normalizer *)
  | TmNote of info * string * string * string * int
  | TmNoteset of info * term * term
  | TmPhrase of info * term * term
  | TmSegment of info * term * int * string
  | TmPassage of info * term * term
  | TmExportPsg of info * term * term

type binding =
    NameBind 
  | TyVarBind
  | VarBind of ty
  | TmAbbBind of term * (ty option)
  | TyAbbBind of ty

type context = (string * binding) list

type command =
  | Eval of info * term
  | Bind of info * string * binding

(* ---------------------------------------------------------------------- *)
(* Context management *)

let emptycontext = []

let ctxlength ctx = List.length ctx

let addbinding ctx x bind = (x,bind)::ctx

let addname ctx x = addbinding ctx x NameBind

let rec isnamebound ctx x =
  match ctx with
      [] -> false
    | (y,_)::rest ->
        if y=x then true
        else isnamebound rest x

let rec pickfreshname ctx x =
  if isnamebound ctx x then pickfreshname ctx (x^"'")
  else ((x,NameBind)::ctx), x

let index2name fi ctx x =
  try
    let (xn,_) = List.nth ctx x in
    xn
  with Failure _ ->
    let msg =
      Printf.sprintf "Variable lookup failure: offset: %d, ctx size: %d" in
    error fi (msg x (List.length ctx))

let rec name2index fi ctx x =
  match ctx with
      [] -> error fi ("Identifier " ^ x ^ " is unbound")
    | (y,_)::rest ->
        if y=x then 0
        else 1 + (name2index fi rest x)

(* ---------------------------------------------------------------------- *)
(* Shifting *)

let tymap onvar c tyT = 
  let rec walk c tyT = match tyT with
    TyVar(x,n) -> onvar c x n
  | TyId(b) as tyT -> tyT
  | TyString -> TyString
  | TyUnit -> TyUnit
  | TyRecord(fieldtys) -> TyRecord(List.map (fun (li,tyTi) -> (li, walk c tyTi)) fieldtys)
  | TyFloat -> TyFloat
  | TyBool -> TyBool
  | TyNat -> TyNat
  (* @yzy for chord normalizer *)
  | TyNote(rank) -> TyNote(rank)
  | TyNoteset(rank) -> TyNoteset(rank)
  | TyPhrase(begin_rank,end_rank) -> TyPhrase(begin_rank,end_rank)
  | TySegment(mode_pitch,mode_class) -> TySegment(mode_pitch,mode_class)
  | TyPassage(begin_mp,begin_mc,end_mp,end_mc) -> TyPassage(begin_mp,begin_mc,end_mp,end_mc)
  | TyExportPsg -> TyExportPsg
  | TyArr(tyT1,tyT2) -> TyArr(walk c tyT1,walk c tyT2)
  | TyVariant(fieldtys) -> TyVariant(List.map (fun (li,tyTi) -> (li, walk c tyTi)) fieldtys)  
  in walk c tyT

let tmmap onvar ontype c t = 
  let rec walk c t = match t with
    TmInert(fi,tyT) -> TmInert(fi,ontype c tyT)
  | TmVar(fi,x,n) -> onvar fi c x n
  | TmAbs(fi,x,tyT1,t2) -> TmAbs(fi,x,ontype c tyT1,walk (c+1) t2)
  | TmApp(fi,t1,t2) -> TmApp(fi,walk c t1,walk c t2)
  | TmLet(fi,x,t1,t2) -> TmLet(fi,x,walk c t1,walk (c+1) t2)
  | TmFix(fi,t1) -> TmFix(fi,walk c t1)
  | TmTrue(fi) as t -> t
  | TmFalse(fi) as t -> t
  | TmIf(fi,t1,t2,t3) -> TmIf(fi,walk c t1,walk c t2,walk c t3)
  | TmString _ as t -> t
  | TmUnit(fi) as t -> t
  | TmProj(fi,t1,l) -> TmProj(fi,walk c t1,l)
  | TmRecord(fi,fields) -> TmRecord(fi,List.map (fun (li,ti) ->
                                               (li,walk c ti))
                                    fields)
  | TmAscribe(fi,t1,tyT1) -> TmAscribe(fi,walk c t1,ontype c tyT1)
  | TmFloat _ as t -> t
  | TmTimesfloat(fi,t1,t2) -> TmTimesfloat(fi, walk c t1, walk c t2)
  | TmZero(fi)      -> TmZero(fi)
  | TmSucc(fi,t1)   -> TmSucc(fi, walk c t1)
  | TmPred(fi,t1)   -> TmPred(fi, walk c t1)
  | TmIsZero(fi,t1) -> TmIsZero(fi, walk c t1)
  | TmTag(fi,l,t1,tyT) -> TmTag(fi, l, walk c t1, ontype c tyT)
  | TmCase(fi,t,cases) ->
      TmCase(fi, walk c t,
             List.map (fun (li,(xi,ti)) -> (li, (xi,walk (c+1) ti)))
               cases)
  (* @yzy for chord normalizer *)
  | TmNote _ as t -> t
  | TmNoteset(fi,t1,t2) -> TmNoteset(fi, walk c t1, walk c t2)
  | TmPhrase(fi,t1,t2) -> TmPhrase(fi, walk c t1, walk c t2)
  | TmSegment(fi,t1,mode_pitch,mode_class) -> 
    TmSegment(fi, walk c t1, mode_pitch,mode_class)
  | TmPassage(fi,t1,t2) -> TmPassage(fi, walk c t1, walk c t2)
  | TmExportPsg(fi,t1,t2) -> TmExportPsg(fi, walk c t1, walk c t2)
  in walk c t

let typeShiftAbove d c tyT =
  tymap
    (fun c x n -> if x>=c then TyVar(x+d,n+d) else TyVar(x,n+d))
    c tyT

let termShiftAbove d c t =
  tmmap
    (fun fi c x n -> if x>=c then TmVar(fi,x+d,n+d) 
                     else TmVar(fi,x,n+d))
    (typeShiftAbove d)
    c t

let termShift d t = termShiftAbove d 0 t

let typeShift d tyT = typeShiftAbove d 0 tyT

let bindingshift d bind =
  match bind with
    NameBind -> NameBind
  | TyVarBind -> TyVarBind
  | TmAbbBind(t,tyT_opt) ->
     let tyT_opt' = match tyT_opt with
                      None->None
                    | Some(tyT) -> Some(typeShift d tyT) in
     TmAbbBind(termShift d t, tyT_opt')
  | VarBind(tyT) -> VarBind(typeShift d tyT)
  | TyAbbBind(tyT) -> TyAbbBind(typeShift d tyT)

(* ---------------------------------------------------------------------- *)
(* Substitution *)

let termSubst j s t =
  tmmap
    (fun fi j x n -> if x=j then termShift j s else TmVar(fi,x,n))
    (fun j tyT -> tyT)
    j t

let termSubstTop s t = 
  termShift (-1) (termSubst 0 (termShift 1 s) t)

let typeSubst tyS j tyT =
  tymap
    (fun j x n -> if x=j then (typeShift j tyS) else (TyVar(x,n)))
    j tyT

let typeSubstTop tyS tyT = 
  typeShift (-1) (typeSubst (typeShift 1 tyS) 0 tyT)

let rec tytermSubst tyS j t =
  tmmap (fun fi c x n -> TmVar(fi,x,n))
        (fun j tyT -> typeSubst tyS j tyT) j t

let tytermSubstTop tyS t = 
  termShift (-1) (tytermSubst (typeShift 1 tyS) 0 t)

(* ---------------------------------------------------------------------- *)
(* Context management (continued) *)

let rec getbinding fi ctx i =
  try
    let (_,bind) = List.nth ctx i in
    bindingshift (i+1) bind 
  with Failure _ ->
    let msg =
      Printf.sprintf "Variable lookup failure: offset: %d, ctx size: %d" in
    error fi (msg i (List.length ctx))
 let getTypeFromContext fi ctx i =
   match getbinding fi ctx i with
         VarBind(tyT) -> tyT
     | TmAbbBind(_,Some(tyT)) -> tyT
     | TmAbbBind(_,None) -> error fi ("No type recorded for variable "
                                        ^ (index2name fi ctx i))
     | _ -> error fi 
       ("getTypeFromContext: Wrong kind of binding for variable " 
         ^ (index2name fi ctx i)) 
(* ---------------------------------------------------------------------- *)
(* Extracting file info *)

let tmInfo t = match t with
    TmInert(fi,_) -> fi
  | TmTrue(fi) -> fi
  | TmFalse(fi) -> fi
  | TmIf(fi,_,_,_) -> fi
  | TmTag(fi,_,_,_) -> fi
  | TmCase(fi,_,_) -> fi
  | TmVar(fi,_,_) -> fi
  | TmAbs(fi,_,_,_) -> fi
  | TmApp(fi, _, _) -> fi
  | TmLet(fi,_,_,_) -> fi
  | TmFix(fi,_) -> fi
  | TmString(fi,_) -> fi
  | TmUnit(fi) -> fi
  | TmAscribe(fi,_,_) -> fi
  | TmProj(fi,_,_) -> fi
  | TmRecord(fi,_) -> fi
  | TmFloat(fi,_) -> fi
  | TmTimesfloat(fi,_,_) -> fi
  | TmZero(fi) -> fi
  | TmSucc(fi,_) -> fi
  | TmPred(fi,_) -> fi
  | TmIsZero(fi,_) -> fi 
  (* @yzy for chord normalizer *)
  | TmNote(fi,_,_,_,_) -> fi
  | TmNoteset(fi,_,_) -> fi
  | TmPhrase(fi,_,_) -> fi
  | TmSegment(fi,_,_,_) -> fi
  | TmPassage(fi,_,_) -> fi
  | TmExportPsg(fi,_,_) -> fi

(* ---------------------------------------------------------------------- *)
(* Printing *)

(* The printing functions call these utility functions to insert grouping
  information and line-breaking hints for the pretty-printing library:
     obox   Open a "box" whose contents will be indented by two spaces if
            the whole box cannot fit on the current line
     obox0  Same but indent continuation lines to the same column as the
            beginning of the box rather than 2 more columns to the right
     cbox   Close the current box
     break  Insert a breakpoint indicating where the line maybe broken if
            necessary.
  See the documentation for the Format module in the OCaml library for
  more details. 
*)

(* @yzy for chord normalizer *)
let rec stringOfMusicTerm t isLeftMost isRightMost = match t with
    TmExportPsg(fi,psg,TmString(_,filename)) -> 
      String.concat "" ["{\"filename\":\""; filename; "\"";
                        ",\"passage\":"; stringOfMusicTerm psg true true; "}"]
  (* export-passage can have only 1 passage so passage don't add comma itself *)
  | TmPassage(fi,lt,rt) -> 
      let lstr = ref "" in let rstr = ref "" in (
        (match lt with
            TmPassage(_) -> lstr := stringOfMusicTerm lt isLeftMost false;
          | TmSegment(_) -> 
              lstr := stringOfMusicTerm lt true true; 
              if isLeftMost then lstr := String.concat "" ["[";!lstr] else ();
          | _ -> error fi "exporting error: invalid passage left term");
        (match rt with
            TmPassage(_) -> rstr := stringOfMusicTerm rt false isRightMost;
          | TmSegment(_) -> 
              rstr := stringOfMusicTerm rt true true; 
              if isRightMost 
              then rstr := String.concat "" [String.sub !rstr 0 ((String.length !rstr) - 1);"]"]
              else ();
          | _ -> error fi "exporting error: invalid passage right term");
        String.concat "" [!lstr;!rstr]
      )
  (* passage can have multiple segments so segments add comma itself *)
  | TmSegment(fi,t1,mode_pitch,mode_class) -> 
      String.concat "" ["{\"pitch\":"; string_of_int mode_pitch;
                        ",\"class\":\""; mode_class; "\"";
                        ",\"phrase\":"; stringOfMusicTerm t1 true true; "},"]
  (* segment can have only 1 phrase so phrase don't add comma itself *)
  | TmPhrase(fi,lt,rt) -> 
      let lstr = ref "" in let rstr = ref "" in let noteStr = ref "" in (
        (match lt with
            TmPhrase(_) -> lstr := stringOfMusicTerm lt isLeftMost false;
          | TmNoteset(_) -> 
              lstr := stringOfMusicTerm lt true true; 
              if isLeftMost then lstr := String.concat "" ["[";!lstr] else ();
          | TmNote(_) -> 
              noteStr := stringOfMusicTerm lt true true;
              lstr := String.concat "" ["[";String.sub !noteStr 0 ((String.length !noteStr) - 1);"],"]; 
              if isLeftMost then lstr := String.concat "" ["[";!lstr] else ();
          | _ -> error fi "exporting error: invalid phrase left term");
        (match rt with
            TmPhrase(_) -> rstr := stringOfMusicTerm rt false isRightMost;
          | TmNoteset(_) -> 
              rstr := stringOfMusicTerm rt true true; 
              if isRightMost 
              then rstr := String.concat "" [String.sub !rstr 0 ((String.length !rstr) - 1);"]"]
              else ();
          | TmNote(_) -> 
              noteStr := stringOfMusicTerm rt true true;
              rstr := String.concat "" ["[";String.sub !noteStr 0 ((String.length !noteStr) - 1);"],"]; 
              if isRightMost 
              then rstr := String.concat "" [String.sub !rstr 0 ((String.length !rstr) - 1);"]"]
              else ();
          | _ -> error fi "exporting error: invalid phrase right term");
        String.concat "" [!lstr;!rstr]
      )
  (* phrase can have multiple notesets so noteset add comma itself *)
  | TmNoteset(fi,lt,rt) -> 
      let lstr = ref "" in let rstr = ref "" in (
        (match lt with
            TmNoteset(_) -> lstr := stringOfMusicTerm lt isLeftMost false;
          | TmNote(_) -> 
              lstr := stringOfMusicTerm lt true true; 
              if isLeftMost then lstr := String.concat "" ["[";!lstr] else ();
          | _ -> error fi "exporting error: invalid noteset left term");
        (match rt with
            TmNoteset(_) -> rstr := stringOfMusicTerm rt false isRightMost;
          | TmNote(_) -> 
              rstr := stringOfMusicTerm rt true true; 
              if isRightMost 
              then rstr := String.concat "" [String.sub !rstr 0 ((String.length !rstr) - 1);"],"]
              else ();
          | _ -> error fi "exporting error: invalid noteset right term");
        String.concat "" [!lstr;!rstr]
      )
  | TmNote(fi,ty,seq,height,len) -> 
      String.concat "" ["{\"type\":\""; ty; "\"";
                        ",\"sequence\":\""; seq; "\"";
                        ",\"height\":\""; height; "\"";
                        ",\"length\":"; string_of_int len; "},"]
  | _ -> error dummyinfo "exporting error: invalid music element"

let obox0() = open_hvbox 0
let obox() = open_hvbox 2
let cbox() = close_box()
let break() = print_break 0 0

let small t = 
  match t with
    TmVar(_,_,_) -> true
  | _ -> false

let rec printty_Type outer ctx tyT = match tyT with
      tyT -> printty_ArrowType outer ctx tyT

and printty_ArrowType outer ctx  tyT = match tyT with 
    TyArr(tyT1,tyT2) ->
      obox0(); 
      printty_AType false ctx tyT1;
      if outer then pr " ";
      pr "->";
      if outer then print_space() else break();
      printty_ArrowType outer ctx tyT2;
      cbox()
  | tyT -> printty_AType outer ctx tyT

and printty_AType outer ctx tyT = match tyT with
    TyVar(x,n) ->
      if ctxlength ctx = n then
        pr (index2name dummyinfo ctx x)
      else
        pr ("[bad index: " ^ (string_of_int x) ^ "/" ^ (string_of_int n)
            ^ " in {"
            ^ (List.fold_left (fun s (x,_) -> s ^ " " ^ x) "" ctx)
            ^ " }]")
  | TyId(b) -> pr b
  | TyBool -> pr "Bool"
  | TyVariant(fields) ->
        let pf i (li,tyTi) =
          if (li <> ((string_of_int i))) then (pr li; pr ":"); 
          printty_Type false ctx tyTi 
        in let rec p i l = match l with
            [] -> ()
          | [f] -> pf i f
          | f::rest ->
              pf i f; pr","; if outer then print_space() else break(); 
              p (i+1) rest
        in pr "<"; open_hovbox 0; p 1 fields; pr ">"; cbox()
  | TyString -> pr "String"
  | TyUnit -> pr "Unit"
  | TyRecord(fields) ->
        let pf i (li,tyTi) =
          if (li <> ((string_of_int i))) then (pr li; pr ":"); 
          printty_Type false ctx tyTi 
        in let rec p i l = match l with 
            [] -> ()
          | [f] -> pf i f
          | f::rest ->
              pf i f; pr","; if outer then print_space() else break(); 
              p (i+1) rest
        in pr "{"; open_hovbox 0; p 1 fields; pr "}"; cbox()
  | TyFloat -> pr "Float"
  | TyNat -> pr "Nat"
  (* @yzy for chord normalizer *)
  | TyNote(rank) -> pr (String.concat "@" ["Note";string_of_int rank])
  | TyNoteset(rank) -> pr (String.concat "@" ["Noteset";string_of_int rank])
  | TyPhrase(begin_rank,end_rank) -> pr (String.concat "@" 
    ["Phrase";(String.concat "->" [string_of_int begin_rank; string_of_int end_rank])])
  | TySegment(mode_pitch,mode_class) -> pr (String.concat "@" 
    ["Segment";(String.concat "_" [string_of_int mode_pitch;mode_class])])
  | TyPassage(begin_mp,begin_mc,end_mp,end_mc) -> pr 
  (String.concat "@" 
  [
    "Passage";
    (String.concat "->" 
    [
      (String.concat "_" 
      [string_of_int begin_mp; begin_mc]);
      (String.concat "_" 
      [string_of_int end_mp; end_mc])
    ])
  ])
  | TyExportPsg -> pr "Exported Passage"
  | tyT -> pr "("; printty_Type outer ctx tyT; pr ")"

let printty ctx tyT = printty_Type true ctx tyT 

let rec printtm_Term outer ctx t = match t with
    TmIf(fi, t1, t2, t3) ->
       obox0();
       pr "if ";
       printtm_Term false ctx t1;
       print_space();
       pr "then ";
       printtm_Term false ctx t2;
       print_space();
       pr "else ";
       printtm_Term false ctx t3;
       cbox()
  | TmCase(_, t, cases) ->
      obox();
      pr "case "; printtm_Term false ctx t; pr " of";
      print_space();
      let pc (li,(xi,ti)) = let (ctx',xi') = (pickfreshname ctx xi) in
                              pr "<"; pr li; pr "="; pr xi'; pr ">==>"; 
                              printtm_Term false ctx' ti 
      in let rec p l = match l with 
            [] -> ()
          | [c] -> pc c
          | c::rest -> pc c; print_space(); pr "| "; p rest
      in p cases;
      cbox()
  | TmAbs(fi,x,tyT1,t2) ->
      (let (ctx',x') = (pickfreshname ctx x) in
         obox(); pr "lambda ";
         pr x'; pr ":"; printty_Type false ctx tyT1; pr ".";
         if (small t2) && not outer then break() else print_space();
         printtm_Term outer ctx' t2;
         cbox())
  | TmLet(fi, x, t1, t2) ->
       obox0();
       pr "let "; pr x; pr " = "; 
       printtm_Term false ctx t1;
       print_space(); pr "in"; print_space();
       printtm_Term false (addname ctx x) t2;
       cbox()
  | TmFix(fi, t1) ->
       obox();
       pr "fix "; 
       printtm_Term false ctx t1;
       cbox()
  | t -> printtm_AppTerm outer ctx t

and printtm_AppTerm outer ctx t = match t with
    TmApp(fi, t1, t2) ->
      obox0();
      printtm_AppTerm false ctx t1;
      print_space();
      printtm_ATerm false ctx t2;
      cbox()
  | TmTimesfloat(_,t1,t2) ->
       pr "timesfloat "; printtm_ATerm false ctx t2; 
       pr " "; printtm_ATerm false ctx t2
  | TmPred(_,t1) ->
       pr "pred "; printtm_ATerm false ctx t1
  | TmIsZero(_,t1) ->
       pr "iszero "; printtm_ATerm false ctx t1
  | t -> printtm_PathTerm outer ctx t

and printtm_AscribeTerm outer ctx t = match t with
    TmAscribe(_,t1,tyT1) ->
      obox0();
      printtm_AppTerm false ctx t1;
      print_space(); pr "as ";
      printty_Type false ctx tyT1;
      cbox()
  | t -> printtm_ATerm outer ctx t

and printtm_PathTerm outer ctx t = match t with
    TmProj(_, t1, l) ->
      printtm_ATerm false ctx t1; pr "."; pr l
  | t -> printtm_AscribeTerm outer ctx t

and printtm_ATerm outer ctx t = match t with
    TmInert(_,tyT) -> pr "inert["; printty_Type false ctx tyT; pr "]"
  | TmTrue(_) -> pr "true"
  | TmFalse(_) -> pr "false"
  | TmTag(fi, l, t, tyT) ->
      obox();
      pr "<"; pr l; pr "="; printtm_Term false ctx t; pr ">";
      print_space();
      pr "as "; printty_Type outer ctx tyT;
      cbox();
  | TmVar(fi,x,n) ->
      if ctxlength ctx = n then
        pr (index2name fi ctx x)
      else
        pr ("[bad index: " ^ (string_of_int x) ^ "/" ^ (string_of_int n)
            ^ " in {"
            ^ (List.fold_left (fun s (x,_) -> s ^ " " ^ x) "" ctx)
            ^ " }]")
  | TmString(_,s) -> pr ("\"" ^ s ^ "\"")
  | TmUnit(_) -> pr "unit"
  | TmRecord(fi, fields) ->
       let pf i (li,ti) =
         if (li <> ((string_of_int i))) then (pr li; pr "="); 
         printtm_Term false ctx ti 
       in let rec p i l = match l with
           [] -> ()
         | [f] -> pf i f
         | f::rest ->
             pf i f; pr","; if outer then print_space() else break(); 
             p (i+1) rest
       in pr "{"; open_hovbox 0; p 1 fields; pr "}"; cbox()
  | TmFloat(_,s) -> pr (string_of_float s)
  | TmZero(fi) ->
       pr "0"
  | TmSucc(_,t1) ->
     let rec f n t = match t with
         TmZero(_) -> pr (string_of_int n)
       | TmSucc(_,s) -> f (n+1) s
       | _ -> (pr "(succ "; printtm_ATerm false ctx t1; pr ")")
     in f 1 t1
  (* @yzy for chord normalizer *)
  | TmNote(fi,_,_,_,_) -> pr "note"
  | TmNoteset(fi,_,_) -> pr "noteset"
  | TmPhrase(fi,_,_) -> pr "phrase"
  | TmSegment(fi,_,_,_) -> pr "segment"
  | TmPassage(fi,_,_) -> pr "passage"
  | TmExportPsg(fi,_,filename_term) ->
    (match filename_term with
        TmString(_,filename) -> 
          let oc = open_out (String.concat "" ["output/";filename]) in
            Printf.fprintf oc "%s" (stringOfMusicTerm t true true);
            close_out oc;
            pr (String.concat " " ["passage exported to file";filename])
      | _ -> pr "invalid export file name (evaluating)" )
  | t -> pr "("; printtm_Term outer ctx t; pr ")"

let printtm ctx t = printtm_Term true ctx t 

let prbinding ctx b = match b with
    NameBind -> ()
  | TyVarBind -> ()
  | VarBind(tyT) -> pr ": "; printty ctx tyT
  | TmAbbBind(t,tyT) -> pr "= "; printtm ctx t
  | TyAbbBind(tyT) -> pr "= "; printty ctx tyT 
