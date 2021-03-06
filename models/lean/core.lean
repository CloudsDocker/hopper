
import data.bool 
import data.nat
import data.list 
-- import data.examples.vector 
import data.fin

set_option pp.all true 

check vector
inductive 
/-
debrujin representation 
-/
check nat.succ

check Type.{imax 0 1}
check Type.{imax 1 2}
check Type.{imax 2 0}
check Type.{imax 1 0}

inductive Var ( a b : Type ) : Type := 
  | Free :   a -> Var a b 
  | Bound :  b -> Var a b
check fin
check list
check Var.Free
-- this is the untyped ast 

-- inductive list.{ℓ} (a : Type.{ℓ} ) : Type.{max 1 ℓ } := 
--   |   Nil : list a 
 --  |   Cons : a -> list a  -> list a 


inductive term : Type -> Type   :=
   | V :∀ {a}, a -> term  a   
   | App : ∀ {a  }, term  a  ->  term a    -> term  a 
   | Lam : ∀  {a} (n : nat) , term (Var (fin n)  a)     -> term  a 
     -- we can introduce ct variables, which also tells us how to "upshift"
     -- any substitution, because theres now "ct" many variables as the inner most scope
-- with 
 --   Scope : nat ->   Type.{max ℓ 2}  :=
   --  | TheScope : ∀ n , @term (Var (fin n) (Term a)) -> Scope  a  n 


