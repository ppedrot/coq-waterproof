(** * waterprove.v
Authors: 
    - Cosmin Manea (1298542)
    - Lulof Pirée (1363638)

Creation date: 01 June 2021

The waterprove automation function.
This function calls the automation tactics, [auto], [eauto] and [intuition], 
with a specific set of lemmas.

--------------------------------------------------------------------------------

This file is part of Waterproof-lib.

Waterproof-lib is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Waterproof-lib is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Waterproof-lib.  If not, see <https://www.gnu.org/licenses/>.
*)

From Ltac2 Require Import Ltac2.
From Ltac2 Require Option.
From Ltac2 Require Import Message.
Require Export Reals.

Require Import Waterproof.selected_databases.

Ltac2 Type exn ::= [ AutomationFailure(string) ].

Local Ltac2 fail_automation () := 
        Control.zero (AutomationFailure 
        "Waterproof could not find a proof. 
If you believe the statement should hold, 
try making a smaller step.").

Lemma dummy_lemma: True.
Proof.
    apply I.
Qed.

(** * global_enable_intuition
    Flag whether [run_automation] and [waterprove]
    should call the [intuition] tactic on top 
    of [auto] and [new auto].
*)
Ltac2 mutable global_enable_intuition := false.

(** * global_use_all_databases
    Flag whether [run_automation] and [waterprove]
    should use ALL databases that Coq can find via the [*] wildcard.
    This may include more databases than can be imported individually!
*)
Ltac2 mutable global_use_all_databases := false.

(* Subroutine of [run_automation] *)
Local Ltac2 run_automation_with_intuition (search_depth: int option)
                                          (databases: ident list option)
                                          (first_lemma: constr)
                                          (lemmas: (unit -> constr) list) :=
    first [
    solve [Std.auto Std.Off search_depth lemmas databases]
    | solve [Std.new_auto Std.Off search_depth lemmas databases]
    | solve [ltac1:(lemma |- intuition (auto using lemma with *)) 
        (Ltac1.of_constr first_lemma)]
    | solve [ltac1:(lemma|- intuition (eauto using lemma with *)) 
        (Ltac1.of_constr first_lemma)] 
    | fail_automation ()
    ].

(* Subroutine of [run_automation] *)
Local Ltac2 run_automation_without_intuition (search_depth: int option)
                                          (databases: ident list option)
                                          (lemmas: (unit -> constr) list) :=
    first [
    solve [Std.auto Std.Off search_depth lemmas databases]
    | solve [Std.new_auto Std.Off search_depth lemmas databases]
    | fail_automation ()
    ].

(** * run_automation
    Calls the automation tactics [auto] and [new auto],
    with a specific set of lemmas, search depth and databases.
    Optionally also calls [intuition] with [auto] and [eauto],
    but with all databases, and *only the first lemma*.

    (Implementation Note:
    It was not possible to convert a [ident list] to a [constr]
    otherwise, and we can only pass [constr] to Ltac1,
    and [intuition] only exists in Ltac1)

    Arguments:
        - [prop: constr], the proposition to be proven by automation.
        - [lemmas: (unit -> constr) list], list of functions mapping to
             additional lemmas to be used in the automation tactics.
             These functions take no arguments.
        - [search_depth: int], maximum search depth.
        - [hint_databases: ident list option], list of identifiers of
            registered hint databases to be used.
            If [None] given, all databases will be used
                (i.e. [auto with *]).
        - [enable_intuition: bool], flag:
            - [false], only try [auto] and [new auto].
            - [true], also try [intuition] with [auto] and with [eauto].

    Does:
        - Try to solve the goal using [auto] and [new_auto].
        - If no proof is found, print a message conveying the failure.

    Raises exceptions:
        - [AutomationFailure], if [prop] could not be proven.
*)
(** Note:
    [Std.auto ] takes the following arguments:
    - [debug]. In std there is [Ltac2 Type debug := [ Off | Info | Debug ].]
        So probably a flag for debugging info?
    - [int opion], optional maximum search depth.
    - [(unit -> constr) list], list of additional lemmas to use.
    - [ident list option], optional list of database names:
        - [with *] -> use the argument [None]
        - Default (i.e. use core) -> use the argument [Some ([])]
        - Actual list of idents (wrapped in [Some]) -> 
            use the databases in the list.
        Evidence: see [test/reverse_engineer/auto_hintdb_arg.v].

    [Std.eauto] takes a second [int option] argument.
    In [Notations.v] it is called [p], but its meaning is unknown.
    Maybe the maximum allowed number of existential variables
    it may introduce?

    [Std.new_auto] takes the same arguments as [auto],
    and is also available as the tactic [new auto].


    * Options for databases:
    
*)
Ltac2 run_automation (prop: constr) (lemmas: (unit -> constr) list) 
                 (search_depth: int) (hint_databases: ident list option) 
                 (enable_intuition: bool) :=
    
    let result () :=

    let search_depth := Some search_depth in
    let first_lemma :=
        match lemmas with
        | head::remainder => head ()
        | [] => constr:(dummy_lemma)
        end
    in
    match enable_intuition with
    | true => run_automation_with_intuition search_depth hint_databases 
                    first_lemma lemmas
    | false => run_automation_without_intuition search_depth hint_databases 
                                                lemmas
    end
    in
    match Control.case result with
    | Val _ => ()
    | Err exn => 
        print (concat 
            (of_string "Waterproof could not find a proof of ") 
            (of_constr prop));
        fail_automation ()
    end.

(** * waterprove
    Calls the automation tactics [auto], [eauto] and [new auto], 
    with a specific set of lemmas.
    
    Uses the databases encoded 
    in the global variable [global_database_selection]. 
    Uses the maximum search depth stored 
    in the global variable [global_search_depth].

    Arguments:
        - [prop: constr], the proposition to be proven by automation.
        - [lemmas: (unit -> constr) list], list of functions mapping to
             additional lemmas to be used in the automation tactics.
             These functions take no arguments.

    Does:
        - Try to solve the goal using [auto], [new_auto] and [eauto], 
        using [lemmas].
        - If no proof is found, print a message conveying the failture.

    Raises exceptions:
        - [AutomationFailure], if [prop] could not be proven.
*)
(* Note:
    [Std.auto ] takes the following arguments:
    - [debug]. In std there is [Ltac2 Type debug := [ Off | Info | Debug ].]
        So probably a flag for debugging info?
    - [int opion], optional maximum search depth.
    - [(unit -> constr) list], list of additional lemmas to use.
    - [ident list option], optional list of database names.

    [Std.eauto] takes one more [int option] argument.
    Maybe the max number of existential variables allowed?

    [Std.new_auto] takes the same arguments as [auto],
    and is available as the tactic [new auto].
*)
Ltac2 waterprove (prop: constr) (lemmas: (unit -> constr) list) :=
    let databases :=
        match global_use_all_databases with
        | true => None
        | false => Some (load_databases global_database_selection) 
        end
    in
    run_automation prop lemmas global_search_depth 
                   databases global_enable_intuition.